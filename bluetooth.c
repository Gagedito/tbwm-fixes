#include <fcntl.h>
#include <signal.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>
#include <wayland-server.h>
#include <xkbcommon/xkbcommon.h>

#include "bluetooth.h"

#define BLT_MAC_LEN  32
#define BLT_NAME_LEN 128
#define BLT_CMD_LEN  384   /* big enough for the agent/pair/reject sequences */

/* Rolling state of the pairing session. Everything here is private to the
 * module; tbwm.c only sees it through the blt_*() accessors. */
static struct wl_display *bt_dpy = NULL;
static int (*bt_scan_cb)(void) = NULL;
static void (*bt_refresh_cb)(void) = NULL;

static int bt_dialog = 0;      /* 1 = draw/key the pairing dialog (session alive) */
static pid_t bt_pid = -1;
static int bt_in_fd = -1;      /* write side: to bluetoothctl's stdin */
static int bt_out_fd = -1;     /* read side: bluetoothctl's stdout */
static struct wl_event_source *bt_source = NULL;
static struct wl_event_source *bt_watch_timer = NULL; /* passive listener keepalive */
static char bt_mac[BLT_MAC_LEN] = "";
static char bt_name[BLT_NAME_LEN] = "";
static char bt_log[2048];      /* recent bluetoothctl output */
static int bt_log_len = 0;
static char bt_pin[64] = "";
static int bt_prompt = 0;      /* 1 = waiting for yes/no (passkey shown) */
static int bt_done = 0;        /* 1 = pairing finished (ok or fail) */
static int bt_ok = 0;          /* 1 = pairing succeeded */
static int bt_connected = 0;   /* 1 = "connect" sent after pairing */
static int bt_saw_pair = 0;    /* 1 = "Pairing successful" seen (real pairing done) */
static int bt_incoming = 0;    /* 1 = pairing request came from the phone (watch) */

static void blt_send(const char *line);
static void blt_finish(int ok);
static void blt_watch(void);
static int blt_watchdog(void *data);

/* Send a line to bluetoothctl's stdin (the pairing session). */
static void
blt_send(const char *line)
{
	if (bt_in_fd >= 0) {
		if (write(bt_in_fd, line, strlen(line)) < 0) {
			/* ignore EPIPE (child already gone) */
		}
	}
}

/* Debug helper: append a line to /tmp/tbwm-bt.log for post-mortem of the
 * pairing session (bluetoothctl is stateful, so we log what it prints and
 * what we decide). */
static void
blt_dbg(const char *fmt, ...)
{
	FILE *f = NULL;
	va_list ap;

	/* Only log when TBWM_DEBUG=1 is set (avoids growing /tmp/tbwm-bt.log on
	 * every normal session). Used for post-mortem of the pairing session. */
	if (!getenv("TBWM_DEBUG"))
		return;
	f = fopen("/tmp/tbwm-bt.log", "a");
	if (!f)
		return;
	va_start(ap, fmt);
	vfprintf(f, fmt, ap);
	va_end(ap);
	fputc('\n', f);
	fclose(f);
}

/* Mark the pairing as finished, clean up the session, and keep the dialog
 * open showing the result until the user presses a key. */
static void
blt_finish(int ok)
{
	if (bt_done)
		return;
	bt_done = 1;
	bt_ok = ok;
	blt_dbg("blt_finish: %s", ok ? "ok" : "fail");
	if (bt_source) {
		wl_event_source_remove(bt_source);
		bt_source = NULL;
	}
	if (bt_out_fd >= 0) {
		close(bt_out_fd);
		bt_out_fd = -1;
	}
	if (bt_pid > 0) {
		waitpid(bt_pid, NULL, WNOHANG);
		bt_pid = -1;
	}
	if (bt_refresh_cb)
		bt_refresh_cb();
}

/* Parse bluetoothctl output for a passkey and a yes/no prompt. The child
 * runs `bluetoothctl` interactively: we must only read its stdout here and,
 * when we need to answer a passkey prompt, write "yes\n"/"no\n" to the pipe
 * from the key handler. We never pre-enqueue a command that would be eaten
 * as an answer by a prompt still pending. */
static void
blt_parse(const char *buf, int len)
{
	int i;

	for (i = 0; i < len; i++) {
		blt_dbg("%02x%c", (unsigned char)buf[i] >= 0x20 ? '.' : '+', buf[i]);
	}
	/* Append to the rolling log */
	for (i = 0; i < len && bt_log_len < (int)sizeof(bt_log) - 1; i++) {
		bt_log[bt_log_len++] = buf[i];
	}
	bt_log[bt_log_len] = '\0';

	/* Keep only the tail (last ~1KB) so memory stays bounded */
	if (bt_log_len > 1024) {
		memmove(bt_log, bt_log + bt_log_len - 1024, 1024);
		bt_log_len = 1024;
		bt_log[1024] = '\0';
	}

	/* Show the passkey when bluetoothctl asks for confirmation.
	 * bluetoothctl 5.?? prints, e.g.:
	 *   [agent] Confirm passkey 123456 (yes/no)
	 *   Requesting confirmation
	 *   [agent] No input no output (auto accept) ...
	 * In interactive pairing of a phone the agent prompts with
	 * "(yes/no)". We also match the older "Confirm passkey" text. */
	if (!bt_prompt && !bt_done &&
	    (strstr(bt_log, "(yes/no") != NULL ||
	     strstr(bt_log, "(yes,no") != NULL ||
	     strstr(bt_log, "Confirm passkey") != NULL)) {
		bt_prompt = 1;
		blt_dbg("prompt: confirmed");
		/* If this is an incoming pairing (no target set), try to name the
		 * device from the associated "[NEW] Device <MAC> <name>" line that
		 * bluetoothctl emits when the request arrives, then show the dialog. */
		if (bt_mac[0] == '\0' && !bt_dialog) {
			const char *nd = strstr(bt_log, "[NEW] Device ");
			if (nd) {
				const char *sp = strchr(nd + 13, ' ');
				if (sp) {
					char mac[BLT_MAC_LEN];
					int j;
					for (j = 0; j < BLT_MAC_LEN - 1 && (nd[13 + j] != ' ') && nd[13 + j]; j++)
						mac[j] = nd[13 + j];
					mac[j] = '\0';
					strncpy(bt_mac, mac, BLT_MAC_LEN - 1);
					bt_mac[BLT_MAC_LEN - 1] = '\0';
					j = 0;
					while (sp[j + 1] && j < BLT_NAME_LEN - 1 &&
					       sp[j + 1] != ' ' && sp[j + 1] != '\n') {
						bt_name[j] = sp[j + 1];
						j++;
					}
					bt_name[j] = '\0';
					blt_dbg("incoming from %s (%s)", bt_mac, bt_name);
				}
			}
			if (bt_name[0] == '\0')
				strncpy(bt_name, "Dispositivo nuevo", BLT_NAME_LEN - 1);
			bt_incoming = 1;
			bt_dialog = 1;
		}
		if (bt_refresh_cb)
			bt_refresh_cb();
	}

	/* Extract the passkey itself: "passkey <digits>", "PIN code:" or digits on a line */
	{
		const char *pk = strstr(bt_log, "passkey ");
		if (pk) {
			pk += 8;
			if (pk[0] >= '0' && pk[0] <= '9') {
				int j = 0;
				while (pk[j] >= '0' && pk[j] <= '9' && j < (int)sizeof(bt_pin) - 1)
					j++;
				memcpy(bt_pin, pk, j);
				bt_pin[j] = '\0';
				blt_dbg("passkey captured: %s", bt_pin);
			}
		}
		if (!bt_pin[0]) {
			const char *pin = strstr(bt_log, "PIN ");
			if (pin) {
				pin += 4;
				if (pin[0] >= '0' && pin[0] <= '9') {
					int j = 0;
					while (pin[j] >= '0' && pin[j] <= '9' && j < (int)sizeof(bt_pin) - 1)
						bt_pin[j] = pin[j], j++;
					bt_pin[j] = '\0';
					blt_dbg("passkey (PIN) captured: %s", bt_pin);
				}
			}
		}
	}

	/* Detect completion. "Connected: yes" alone is NOT proof of pairing:
	 * bluetoothctl prints it as soon as the ACL link comes up, which can
	 * happen while pairing is still in progress (and the phone shows the
	 * passkey). We only trust "Pairing successful"/"Pairing complete" as
	 * the real finish marker, then send "connect" and finally accept
	 * "Connected: yes" once pairing has truly finished. */
	if (!bt_done) {
		if (!bt_saw_pair &&
		    (strstr(bt_log, "Pairing successful") != NULL ||
		     strstr(bt_log, "Pairing complete") != NULL)) {
			bt_saw_pair = 1;
			blt_dbg("pairing confirmed");
		}
		if (bt_saw_pair && !bt_connected) {
			char con[BLT_CMD_LEN];
			bt_connected = 1;
			snprintf(con, sizeof(con), "connect %s\n", bt_mac);
			blt_send(con);
			blt_dbg("sent connect after pairing");
		}
		if (strstr(bt_log, "Pairing successful") != NULL ||
		    strstr(bt_log, "Pairing complete") != NULL) {
			blt_finish(1);
		} else if (bt_saw_pair &&
		           (strstr(bt_log, "Connected: yes") != NULL ||
		            strstr(bt_log, "[Connected") != NULL ||
		            strstr(bt_log, "Connection successful") != NULL)) {
			blt_finish(1);
		} else if (strstr(bt_log, "Failed to pair") != NULL ||
		           strstr(bt_log, "Failed to connect") != NULL ||
		           strstr(bt_log, "org.bluez.Error.AuthenticationFailed") != NULL ||
		           strstr(bt_log, "org.bluez.Error.Rejected") != NULL ||
		           strstr(bt_log, "org.bluez.Error.RemoveFailed") != NULL) {
			blt_finish(0);
		}
	}
}

/* Read bluetoothctl's output as it arrives (pairing session). */
static int
blt_read_cb(int fd, uint32_t mask, void *data)
{
	char buf[4096];
	ssize_t r;
	int done = 0;
	(void)data;

	if (mask & (WL_EVENT_HANGUP | WL_EVENT_ERROR))
		done = 1;

	while ((r = read(fd, buf, sizeof(buf))) > 0)
		blt_parse(buf, (int)r);
	if (r == 0)
		done = 1;

	if (done && !bt_done) {
		/* bluetoothctl exited (or quit command processed). Determine success
		 * from what it printed. */
		blt_finish(strstr(bt_log, "successful") != NULL ||
		           strstr(bt_log, "Connected") != NULL);
	} else if (bt_done) {
		/* Already finalized by content detection; nothing more to do. */
	}
	return 1;
}

/* Spawn a fresh bluetoothctl session with an agent and wire up the pipes.
 * Returns 1 on success; on return the new session is in bt_in_fd /
 * bt_out_fd / bt_pid. The stdout fd watcher is registered here (not in
 * tbwm.c's setup()) so module state stays in one place. */
static int
blt_spawn(void)
{
	int in_pipe[2], out_pipe[2];
	pid_t pid;

	if (pipe(in_pipe) < 0 || pipe(out_pipe) < 0) {
		if (in_pipe[0] >= 0) { close(in_pipe[0]); close(in_pipe[1]); }
		if (out_pipe[0] >= 0) { close(out_pipe[0]); close(out_pipe[1]); }
		return 0;
	}

	pid = fork();
	if (pid == 0) {
		setsid();
		close(in_pipe[1]);   /* parent writes into child's stdin */
		close(out_pipe[0]);
		dup2(in_pipe[0], STDIN_FILENO);
		close(in_pipe[0]);
		dup2(out_pipe[1], STDOUT_FILENO);
		dup2(out_pipe[1], STDERR_FILENO);
		close(out_pipe[1]);
		execl("/usr/bin/bluetoothctl", "bluetoothctl", (char *)NULL);
		_exit(127);
	}

	/* Parent */
	close(in_pipe[0]);   /* reading from child's stdin side is closed */
	close(out_pipe[1]);
	bt_in_fd = in_pipe[1];    /* write here to send commands/answers */
	bt_out_fd = out_pipe[0];  /* read here to see prompts */
	bt_pid = pid;

	{
		int flags = fcntl(bt_out_fd, F_GETFL, 0);
		if (flags >= 0)
			fcntl(bt_out_fd, F_SETFL, flags | O_NONBLOCK);
		flags = fcntl(bt_in_fd, F_GETFL, 0);
		if (flags >= 0)
			fcntl(bt_in_fd, F_SETFL, flags | O_NONBLOCK);
	}

	if (bt_dpy) {
		bt_source = wl_event_loop_add_fd(wl_display_get_event_loop(bt_dpy),
			bt_out_fd, WL_EVENT_READABLE, blt_read_cb, NULL);
	}
	return 1;
}

/* Ensure a bluetoothctl session exists; spawn it if needed and register the
 * KeyboardDisplay agent. Shared by the menu-initiated pairing (blt_start)
 * and the passive listener (blt_watch). Resets the rolling state. */
static void
blt_ensure_session(void)
{
	if (bt_pid <= 0)
		blt_spawn();
	bt_log_len = 0;
	bt_log[0] = '\0';
	bt_pin[0] = '\0';
	bt_prompt = 0;
	bt_done = 0;
	bt_ok = 0;
	bt_connected = 0;
	bt_saw_pair = 0;
}

/* Start an interactive bluetoothctl pairing session for a discovered device.
 * bluetoothctl runs with our pipes as its stdin/stdout; we register an agent
 * and pair; the passkey prompt is answered with yes/no from the keyboard. */
void
blt_start(const char *mac, const char *name)
{
	char seq[BLT_CMD_LEN];

	if (bt_pid > 0)
		blt_stop();
	blt_ensure_session();

	strncpy(bt_mac, mac, BLT_MAC_LEN - 1);
	bt_mac[BLT_MAC_LEN - 1] = '\0';
	strncpy(bt_name, name, BLT_NAME_LEN - 1);
	bt_name[BLT_NAME_LEN - 1] = '\0';

	/* Register a KeyboardDisplay agent and request the pairing. We do NOT
	 * enqueue "connect" here: bluetoothctl reads stdin line by line, so a
	 * pre-queued "connect AA:BB" would be consumed as the answer to the
	 * passkey prompt. The "connect" is sent only once "Pairing successful"
	 * shows up (see blt_parse). */
	snprintf(seq, sizeof(seq),
		"agent KeyboardDisplay\ndefault-agent\ntrust %s\npair %s\n",
		mac, mac);
	blt_send(seq);

	bt_incoming = 0;
	bt_dialog = 1;
	if (bt_refresh_cb)
		bt_refresh_cb();
}

/* Passive listener: keep a bluetoothctl agent registered so an incoming
 * pairing request started from the phone reaches us and shows the passkey
 * dialog inside "Buscar dispositivos". No device is targeted here. */
static void
blt_watch(void)
{
	if (bt_pid <= 0)
		blt_spawn();

	bt_mac[0] = '\0';
	bt_name[0] = '\0';
	bt_log_len = 0;
	bt_log[0] = '\0';
	bt_pin[0] = '\0';
	bt_prompt = 0;
	bt_done = 0;
	bt_ok = 0;
	bt_connected = 0;
	bt_saw_pair = 0;
	bt_incoming = 0;
	bt_dialog = 0;

	/* Only register the agent once: after the session bootstraps, further
	 * "agent" lines would just print "Agent is already registered". We
	 * always re-send so a just-spawned session gets its agent. */
	blt_send("agent KeyboardDisplay\ndefault-agent\n");
}

/* Stop and clean up an active pairing session. */
void
blt_stop(void)
{
	if (bt_source) {
		wl_event_source_remove(bt_source);
		bt_source = NULL;
	}
	if (bt_out_fd >= 0) {
		close(bt_out_fd);
		bt_out_fd = -1;
	}
	if (bt_in_fd >= 0) {
		close(bt_in_fd);
		bt_in_fd = -1;
	}
	if (bt_pid > 0) {
		kill(bt_pid, SIGTERM);
		waitpid(bt_pid, NULL, WNOHANG);
		bt_pid = -1;
	}
	bt_dialog = 0;
	bt_incoming = 0;
}

/* Confirm (yes) or reject (no) the pairing passkey. */
static void
blt_answer(int accept)
{
	if (accept)
		blt_send("yes\n");
	else
		blt_send("no\n");
}

/* Passive listener watchdog: while the menu is open on the "Buscar
 * dispositivos" sub-topic, keep a bluetoothctl agent alive so pairing
 * requests initiated from the phone are caught and shown in the dialog.
 * When the user leaves that view or closes the menu, stop the session. */
static int
blt_watchdog(void *data)
{
	(void)data;
	if (bt_scan_cb && bt_scan_cb()) {
		/* On "Buscar dispositivos": keep a passive agent (unless a pairing
		 * dialog from the user already owns the session). */
		if (bt_pid <= 0 && !bt_dialog)
			blt_watch();
	} else if (bt_pid > 0 && !bt_dialog) {
		blt_stop();
	}
	wl_event_source_timer_update(bt_watch_timer, 3000);
	return 1;
}

void
bluetooth_init(struct wl_display *dpy, int (*scan_cb)(void), void (*refresh_cb)(void))
{
	bt_dpy = dpy;
	bt_scan_cb = scan_cb;
	bt_refresh_cb = refresh_cb;
	bt_watch_timer = wl_event_loop_add_timer(wl_display_get_event_loop(dpy),
		blt_watchdog, NULL);
	wl_event_source_timer_update(bt_watch_timer, 3000);
}

int
blt_dialog(void)
{
	return bt_dialog;
}

int
blt_prompt(void)
{
	return bt_prompt;
}

int
blt_done(void)
{
	return bt_done;
}

int
blt_ok(void)
{
	return bt_ok;
}

int
blt_incoming(void)
{
	return bt_incoming;
}

const char *
blt_pin(void)
{
	return bt_pin;
}

const char *
blt_name(void)
{
	return bt_name;
}

/* Route a net menu key event while the pairing dialog owns the keyboard.
 * Mirrors the old inline handling in netmenukey: Escape/N reject, Enter/S
 * accept (or close the dialog once the pairing finished). */
int
blt_key(unsigned int sym)
{
	if (!bt_dialog)
		return BLKEY_IGNORED;

	if (sym == XKB_KEY_Escape || sym == XKB_KEY_N || sym == XKB_KEY_n) {
		if (bt_prompt) {
			blt_answer(0);
			bt_prompt = 0;
		} else {
			blt_stop();
		}
		return BLKEY_HANDLED;
	}

	if (sym == XKB_KEY_Return || sym == XKB_KEY_KP_Enter ||
	    sym == XKB_KEY_S || sym == XKB_KEY_s) {
		if (bt_prompt) {
			blt_answer(1);
			bt_prompt = 0;
			return BLKEY_HANDLED;
		}
		if (bt_done) {
			int was_incoming = bt_incoming;
			blt_stop();
			return was_incoming ? BLKEY_HANDLED : BLKEY_CLOSE_MENU;
		}
		return BLKEY_HANDLED;
	}

	/* swallow everything else while pairing */
	return BLKEY_HANDLED;
}
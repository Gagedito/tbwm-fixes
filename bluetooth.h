#ifndef TBWM_BLUETOOTH_H
#define TBWM_BLUETOOTH_H

/*
 * Bluetooth pairing driver for tbwm's network menu.
 *
 * tbwm.c owns the GUI (drawing the PIN dialog, the S/N/Esc/Enter handling in
 * netmenukey) and only talks to this module through these opaque accessors:
 * no struct or pipe state is ever exposed. bluetooth.c owns the bluetoothctl
 * session (spawn, pipes, fd watcher, passkey watchdog) entirely.
 *
 * The fd watcher and the passive-listener timer are registered/unregistered
 * inside this module (blt_init / blt_start / blt_stop), never from tbwm.c's
 * setup().
 */

struct wl_display;

/* Returns from blt_key() */
enum {
	BLKEY_IGNORED = 0,  /* no active pairing dialog: key not handled */
	BLKEY_HANDLED = 1,  /* consumed by the dialog, menu stays open */
	BLKEY_CLOSE_MENU = 2 /* consumed, pairing finished from the menu: close menu */
};

/*
 * Initialize the module. dpy is used to reach the event loop (fd watcher and
 * watchdog timer). scan_cb() returns 1 while the netmenu is focused on a
 * "Buscar dispositivos" sub-topic (passive listener keepalive). refresh_cb()
 * is called to repaint the net menu whenever pairing state changes.
 */
void bluetooth_init(struct wl_display *dpy,
		int (*scan_cb)(void), void (*refresh_cb)(void));

/* Start a menu-initiated pairing for mac (device name for the dialog). */
void blt_start(const char *mac, const char *name);

/* Stop the session and drop the dialog (menu key and WM shutdown). */
void blt_stop(void);

/* Opaque accessors for the dialog rendering. */
int blt_dialog(void);       /* 1 = dialog is open (draw + key interception) */
int blt_prompt(void);       /* 1 = passkey shown, waiting for yes/no */
int blt_done(void);         /* 1 = pairing finished (ok or fail) */
int blt_ok(void);           /* 1 = the finished pairing succeeded */
int blt_incoming(void);     /* 1 = pairing started from the phone (watch) */
const char *blt_pin(void);  /* captured passkey, "" if none yet */
const char *blt_name(void); /* device name shown in the dialog */

/* Route a net menu key event; returns a BLKEY_* constant. */
int blt_key(unsigned int sym);

#endif /* TBWM_BLUETOOTH_H */
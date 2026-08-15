;;; TurboWM config.scm - Scheme configuration
;;; All settings can be changed at runtime with (reload-config)

;;;; ==================== APPEARANCE ====================

;; Colors - Format: #RRGGBB
;; Background/REPL color (black)
(set-bg-color "#000000")

;; Background/REPL text color (grey)
(set-bg-text-color "#aaaaaa")

;; Status bar background (the blue)
(set-bar-color "#0000aa")

;; Status bar text color (grey)
(set-bar-text-color "#aaaaaa")

;; Window highlight/border background (the blue)
(set-border-color "#0000aa")

;; Box-drawing border lines (the grey)
(set-border-line-color "#aaaaaa")

;; Number of virtual desktops/tags (1-9)
(set-tag-count 9)

;;;; ==================== STARTUP COMMANDS ====================

;; Commands to run when the compositor starts
;; Uncomment and customize as needed:
;; (on-startup "waybar" "mako" "foot --server")

;; Start the PipeWire audio stack and the dynamic wallpaper (scripts
;; installed into PATH by install.sh: tbwm-audio, tbwm-wallpaper)
(on-startup "tbwm-audio" "tbwm-wallpaper")

;;;; ==================== STATUS BAR ====================

;; Show date and time in status bar
(set-show-date #t)
(set-show-time #t)

;; Custom status text (if set, replaces date/time)
;; Use this from scripts to show anything: battery, wifi, etc.
;; (set-status-text "Battery: 85%")

;; Automatic battery percentage in the status bar (reads /sys/class/power_supply).
;; Shown alongside the date/time (no longer replaces them). Second arg = refresh
;; interval in seconds (default 60).
;; (set-battery-poll #t 30)

;; Title bar scrolling for long titles
(set-title-scroll-mode 1)   ; 1 = scroll, 0 = truncate with ...

;;;; ==================== BEHAVIOR ====================

;; Focus follows mouse (sloppy focus)
(set-sloppy-focus #t)

;; Keyboard repeat rate and delay (chars/sec, ms before repeat)
(set-repeat-rate 25 600)

;;;; ==================== INPUT DEVICES ====================

;; Trackpad settings
(set-tap-to-click #t)
(set-natural-scrolling #f)
(set-accel-speed 0.0)  ; -1.0 to 1.0

;;;; ==================== MOUSE BINDINGS ====================
;; (bind-mouse "MODIFIER-button" callback)
;; Buttons: button1 (left), button2 (middle), button3 (right)

;; Super+Left: move window
(bind-mouse "M-button1" (lambda () (move-window)))
;; Super+Right: resize window
(bind-mouse "M-button3" (lambda () (resize-window)))

;;;; ==================== KEYBINDINGS ====================
;; Modifiers: M = Super, S = Shift, C = Control, A = Alt

;; Terminal
(bind-key "M-Return" (lambda () (spawn "foot")))

;; Launcher
(bind-key "M-d" (lambda () (toggle-launcher)))

;; App menu
(bind-key "M-x" (lambda () (toggle-appmenu)))

;; Theme menu (in-WM): frame/bar/background colors, palette or custom
(bind-key "M-t" (lambda () (toggle-thememenu)))

;; Settings menu (in-WM): all options in categories, editable live
(bind-key "M-S-s" (lambda () (toggle-settings-menu)))

;; Close window
(bind-key "M-q" (lambda () (kill-client)))

;; Quit TurboWM
(bind-key "M-S-e" (lambda () (quit)))

;; Focus direction (vim keys)
(bind-key "M-h" (lambda () (focus-dir DIR-LEFT)))
(bind-key "M-j" (lambda () (focus-dir DIR-DOWN)))
(bind-key "M-k" (lambda () (focus-dir DIR-UP)))
(bind-key "M-l" (lambda () (focus-dir DIR-RIGHT)))

;; Focus direction (arrow keys)
(bind-key "M-Left" (lambda () (focus-dir DIR-LEFT)))
(bind-key "M-Down" (lambda () (focus-dir DIR-DOWN)))
(bind-key "M-Up" (lambda () (focus-dir DIR-UP)))
(bind-key "M-Right" (lambda () (focus-dir DIR-RIGHT)))

;; Swap windows (vim keys)
(bind-key "M-S-h" (lambda () (swap-dir DIR-LEFT)))
(bind-key "M-S-j" (lambda () (swap-dir DIR-DOWN)))
(bind-key "M-S-k" (lambda () (swap-dir DIR-UP)))
(bind-key "M-S-l" (lambda () (swap-dir DIR-RIGHT)))
(bind-key "M-S-Left" (lambda () (swap-dir DIR-LEFT)))
(bind-key "M-S-Down" (lambda () (swap-dir DIR-DOWN)))
(bind-key "M-S-Up" (lambda () (swap-dir DIR-UP)))
(bind-key "M-S-Right" (lambda () (swap-dir DIR-RIGHT)))
;; Fullscreen and floating
(bind-key "M-f" (lambda () (toggle-fullscreen)))
(bind-key "M-S-space" (lambda () (toggle-floating)))

;; Tags 1-9
(bind-key "M-1" (lambda () (view-tag 1)))
(bind-key "M-2" (lambda () (view-tag 2)))
(bind-key "M-3" (lambda () (view-tag 3)))
(bind-key "M-4" (lambda () (view-tag 4)))
(bind-key "M-5" (lambda () (view-tag 5)))
(bind-key "M-6" (lambda () (view-tag 6)))
(bind-key "M-7" (lambda () (view-tag 7)))
(bind-key "M-8" (lambda () (view-tag 8)))
(bind-key "M-9" (lambda () (view-tag 9)))

;; Move window to tag (Shift+number gives symbols on US keyboard)
(bind-key "M-S-exclam" (lambda () (tag-window 1)))
(bind-key "M-S-at" (lambda () (tag-window 2)))
(bind-key "M-S-numbersign" (lambda () (tag-window 3)))
(bind-key "M-S-dollar" (lambda () (tag-window 4)))
(bind-key "M-S-percent" (lambda () (tag-window 5)))
(bind-key "M-S-asciicircum" (lambda () (tag-window 6)))
(bind-key "M-S-ampersand" (lambda () (tag-window 7)))
(bind-key "M-S-asterisk" (lambda () (tag-window 8)))
(bind-key "M-S-parenleft" (lambda () (tag-window 9)))
;; Refresh layout
(bind-key "M-S-r" (lambda () (refresh)))

;; Reload config (hot reload!)
(bind-key "M-S-c" (lambda () (reload-config) (log "Config reloaded!")))

;; Screenshots (requires grim, slurp, wl-copy)
(bind-key "Print" (lambda () (spawn-grab "sh -c 'grim - | wl-copy'")))
(bind-key "S-Print" (lambda () (spawn-grab "sh -c 'grim -g \"$(slurp)\" - | wl-copy'")))

;; Network menu (WiFi + Bluetooth) - requires networkmanager, bluez and the
;; tbwm-network helper (installed by install.sh)
(set-net-menu-cmd "tbwm-network")
(bind-key "M-n" (lambda () (toggle-net-menu)))

;; Audio menu (volume / outputs / microphones) - requires wpctl (pipewire)
;; and the tbwm-audio-menu helper (installed by install.sh)
(set-audio-menu-cmd "tbwm-audio-menu")
(bind-key "M-a" (lambda () (toggle-audio-menu)))

;; Volume control (requires wpctl/wireplumber)
(bind-key "XF86AudioRaiseVolume" (lambda () (spawn "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+")))
(bind-key "XF86AudioLowerVolume" (lambda () (spawn "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-")))
(bind-key "XF86AudioMute" (lambda () (spawn "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle")))
(bind-key "XF86AudioMicMute" (lambda () (spawn "wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle")))

;; Brightness control (requires brightnessctl)
(bind-key "XF86MonBrightnessUp" (lambda () (spawn "brightnessctl set +5%")))
(bind-key "XF86MonBrightnessDown" (lambda () (spawn "brightnessctl set 5%-")))

;; REPL - Scheme console on the desktop
;; Super+Shift+; (Win+:) to open, Escape to close
(bind-key "M-S-colon" (lambda () (toggle-repl)))

;; TTY switching (Ctrl+Alt+F1-F12)
(bind-key "C-A-F1" (lambda () (chvt 1)))
(bind-key "C-A-F2" (lambda () (chvt 2)))
(bind-key "C-A-F3" (lambda () (chvt 3)))
(bind-key "C-A-F4" (lambda () (chvt 4)))
(bind-key "C-A-F5" (lambda () (chvt 5)))
(bind-key "C-A-F6" (lambda () (chvt 6)))
(bind-key "C-A-F7" (lambda () (chvt 7)))
(bind-key "C-A-F8" (lambda () (chvt 8)))
(bind-key "C-A-F9" (lambda () (chvt 9)))
(bind-key "C-A-F10" (lambda () (chvt 10)))
(bind-key "C-A-F11" (lambda () (chvt 11)))
(bind-key "C-A-F12" (lambda () (chvt 12)))

;;; Complete Scheme binding examples removed (duplicated bindings above broke focus keys)

;; Advanced setters (examples - not necessarily key bound):
;; (set-border-width 2)
;; (set-border-color "#FF0000")
;; (set-frame-bg-color "#FF0000FF")
;; (set-font "/path/to/font.ttf" 16)

;;;; ==================== EXTERNAL CONFIG SYNC ====================
;; Sync colors to external apps. Uncomment and modify as needed.
;; This runs every time config is loaded/reloaded.

;; --- Foot terminal ---
;; (let* ((home (getenv "HOME"))
;;        (conf (string-append home "/.config/foot/foot.ini")))
;;   (system (string-append "mkdir -p " home "/.config/foot"))
;;   (if (file-exists? conf)
;;       (system (string-append "cp " conf " " conf ".bak")))
;;   (call-with-output-file conf
;;     (lambda (p)
;;       (display "[main]\nfont=monospace:size=10\n\n[colors]\n" p)
;;       (display "background=000000\nforeground=aaaaaa\n" p))))

(log "TurboWM config loaded!")

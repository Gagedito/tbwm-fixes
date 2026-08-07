# tbwm-fixes

Arreglos para [tbwm](https://github.com/WheeledCord/tbwm) (TurboWM), un
compositor Wayland. Todo lo necesario para aplicarlos está en este repo:

- **`tbwm-fixes.patch`** — parche con los arreglos de `tbwm.c`, `config.h`,
  `config.def.h`, `config.mk` e `install.sh`.
- **`config.scm`** — configuración de ejemplo funcional (bindings, Flatpak,
  audio, brillo, REPL, TTYs).
- **`tbwm-audio`** — script para arrancar PipeWire/PipeWire-pulse/WirePlumber
  desde `(on-startup ...)` (tbwm no procesa XDG autostart). Si a los 2s solo
  existe el sink "Dummy Output" (WirePlumber arrancó antes de que la tarjeta de
  sonido/udev estuviera lista), lo reinicia una vez para detectar el hardware
  real. Funciona con cualquier tarjeta de sonido.

## Qué arregla el parche

### 1. Config por defecto rota (focus/keys rotos)
El bloque "Complete Scheme binding examples" en `default_config_parts[]`
sobrescribía los bindings de foco por defecto (`M-h`, `M-j`, `M-k`, `M-l`) y
hacía que `M-k` matara el cliente. El bloque se elimina para que la config
default sea funcional.

### 2. Captura de pantalla colgada
`handlesig()` reapeaba todos los hijos con un bucle `waitpid(...WNOHANG)`, con
lo que `signal_fd_cb()` nunca encontraba a `screenshot_pid` y `screenshot_mode`
quedaba activo para siempre. Ahora `handlesig()` solo marca el pid y
`signal_fd_cb()` es quien reapea y resetea el estado.

### 3. REPL abierta en segundo plano
Al iniciar el WM, la REPL quedaba visible aunque no hubiera entrada activa.
Ahora `repl_visible` arranca en 0, `togglerepl()` la sincroniza con
`repl_input_active` y la tecla Escape la oculta.

### 4. Soporte Flatpak en el menú y en el launcher
- El menú de apps ahora escanea los directorios de exports de Flatpak
  (`/var/lib/flatpak/...`, `/usr/share/flatpak/...` y `~/.local/share/flatpak/...`).
- El launcher reconoce las apps Flatpak por su nombre legible (extraído del
  `.desktop`) en lugar del binario, usando la ruta completa para lanzarlas.

### 5. Layout de teclado elegible al instalar
En vez de hardcodear un layout, el layout XKB se compila vía la macro
`TBWM_XKB_LAYOUT`:
- `install.sh` pregunta por el layout y exporta `TBWM_XKB_LAYOUT`.
- `config.mk` agrega `-DTBWM_XKB_LAYOUT="<layout>"` a `CFLAGS`.
- `config.h`/`config.def.h` usan `NULL` por defecto (layout del sistema).

## Cómo aplicarlo

```sh
git clone https://github.com/WheeledCord/tbwm
cd tbwm
git apply /ruta/a/tbwm-fixes.patch   # o: patch -p1 < /ruta/a/tbwm-fixes.patch
```

## Cómo compilar

Dependencias: `wlroots` (probado con 0.19, pkg-config `wlroots-0.19`),
`wayland`, `xkbcommon`, `libinput`, `freetype2`, `pixman`, `xcb`,
`xcb-icccm`, y un Scheme (S7 viene incluido).

```sh
# Layout por defecto (sistema):
make
sudo make install

# O con layout específico (p. ej. latinoamericano):
TBWM_XKB_LAYOUT=latam make
sudo make install

# O simplemente dejando que install.sh pregunte:
sudo sh install.sh
```

El instalador también copia `tbwm.desktop` a `/usr/local/share/wayland-sessions`
para poder arrancar tbwm desde el display manager.

## Configuración de ejemplo (config.scm)

Copia `config.scm` a `~/.config/tbwm/config.scm` y ajusta la ruta del
`on-startup`:

```scm
(on-startup "/ruta/a/tbwm-audio")
```

Incluye:
- Terminal (`M-Return` → foot), launcher (`M-d`), menú de apps (`M-x`).
- Navegación de foco/swap con vim keys y flechas.
- 9 tags con mover ventana (`M-S-1..9` en US, `M-S-exclam..parenleft`).
- Captura de pantalla con `grim` + `slurp` (copia al portapapeles).
- Volumen/brillo (`XF86Audio*`, `XF86MonBrightness*`) con `wpctl` y
  `brightnessctl`.
- REPL (`M-S-colon`) y cambio de TTY (`C-A-F1..F12`).

## Notas del entorno de prueba

- Artix Linux (runit), wlroots 0.19.3 del repo `world`.
- Para captura de pantalla (M-S-s): `grim`, `slurp` y `wl-clipboard`.
- Para las teclas de brillo: `brightnessctl`.
- Para audio (música, micrófono): PipeWire/PipeWire-pulse/WirePlumber
  (arrancados con `tbwm-audio`).

# tbwm-fixes

Arreglos para [tbwm](https://github.com/WheeledCord/tbwm) (TurboWM), un
compositor Wayland. Todo lo necesario para aplicarlos está en este repo:

- **`tbwm-fixes.patch`** — parche con los arreglos de `tbwm.c`, `config.h`,
  `config.def.h`, `config.mk` e `install.sh`.
- **`config.scm`** — configuración de ejemplo funcional (bindings, Flatpak,
  audio, brillo, REPL, TTYs, menú de red).
- **`tbwm-audio`** — script para arrancar PipeWire/PipeWire-pulse/WirePlumber
  desde `(on-startup ...)` (tbwm no procesa XDG autostart). Si a los 2s solo
  existe el sink "Dummy Output" (WirePlumber arrancó antes de que la tarjeta de
  sonido/udev estuviera lista), lo reinicia una vez para detectar el hardware
  real. Funciona con cualquier tarjeta de sonido.
- **`tbwm-network`** — script para el menú de red (WiFi + Bluetooth): lista
  redes y dispositivos disponibles/conectados y genera los comandos para
  conectarse o desconectarse.

El código fuente completo con todos estos cambios está en el fork
[Gagedito/tbwm](https://github.com/Gagedito/tbwm).

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

### 6. Reloj cortado en el borde derecho de la barra
La estimación del ancho del área derecha de la barra (botón `[N]` + fecha/hora)
subestimaba el espacio que consumen los separadores, por lo que la hora
(AM/PM) quedaba cortada por el borde de la pantalla. La estimación ahora
coincide exactamente con lo que dibuja el render.

### 7. Menú de red (WiFi + Bluetooth)
El parche agrega un menú combinado de WiFi y Bluetooth accesible desde el botón
`[N]` en la barra o con `M-n`. Detalles en la sección "Menú de red" más abajo.

## Menú de red (WiFi + Bluetooth)

Menú combinado de WiFi y Bluetooth. Se abre con `M-n` o haciendo clic en el
botón `[N]` de la barra (justo a la izquierda de la fecha/hora).

### Qué hace
- Categorías **Wifi** y **Bluetooth**, cada una con sub-temas **Connect** y
  **Connected**:
  - **Connected**: redes/dispositivos ya conectados. Elegir uno lo desconecta
    (Bluetooth) o reconecta (WiFi).
  - **Connect**: el resto de redes/dispositivos disponibles para conectarse.
- Navegación con flechas o vim (`j`/`k`), `Enter` para entrar/elegir,
  `Esc`/`←`/`Backspace` para volver un nivel (y cerrar en el nivel superior),
  y clics de ratón.
- Los datos se cargan de forma **asíncrona** (proceso hijo + pipe en el event
  loop de Wayland), así que abrir el menú nunca congela el compositor; mientras
  carga se muestra `Loading...`.
- Para una red WiFi **protegida sin perfil guardado**, el menú pide la
  **contraseña en el mismo menú** (enmascarada con `*`): se escribe y `Enter`
  conecta; `Esc`/`←` cancela y vuelve a la lista.

### Configuración
```scm
;; Script que lista redes y dispositivos (ver más abajo)
(set-net-menu-cmd "/home/gage/.local/bin/tbwm-network")

;; Abrir el menú
(bind-key "M-n" (lambda () (toggle-net-menu)))

;; Opcional: texto del botón en la barra
(set-net-menu-button "N")
```

### Script `tbwm-network`
Copia el script a `~/.local/bin/tbwm-network` y hazlo ejecutable:

```sh
chmod +x tbwm-network
```

Depende de `nmcli` (paquete `networkmanager`) para WiFi y `bluetoothctl`
(paquete `bluez-utils`, con el daemon `bluez`) para Bluetooth. Emite una línea
por elemento con el formato
`Categoría<TAB>Grupo<TAB>Nombre<TAB>comando[<TAB>needspass]`:
- **Categoría**: `Wifi` o `Bluetooth`.
- **Grupo**: `Connect` o `Connected`.
- **Nombre**: etiqueta mostrada en el menú (p. ej. `[WiFi] SSID (75%)`).
- **comando**: shell command que se ejecuta al elegir el elemento
  (`nmcli dev wifi connect 'SSID'`, `bluetoothctl connect MAC`,
  `bluetoothctl disconnect MAC`).
- **needspass** (opcional): `1` si es una red WiFi protegida sin perfil
  guardado; en ese caso tbwm pide la contraseña antes de ejecutar.

## Cómo aplicarlo

```sh
git clone https://github.com/WheeledCord/tbwm
cd tbwm
git apply /ruta/a/tbwm-fixes.patch   # o: patch -p1 < /ruta/a/tbwm-fixes.patch
```

Para el menú de red, copia también `tbwm-network` a `~/.local/bin/` (o a
cualquier directorio en `PATH`) y hazlo ejecutable (ver sección
"Menú de red").

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
- Menú de red WiFi/Bluetooth (`M-n` → `toggle-net-menu`, con el script
  `tbwm-network`).
- Navegación de foco/swap con vim keys y flechas.
- 9 tags con mover ventana (`M-S-1..9` en US, `M-S-exclam..parenleft`).
- Captura de pantalla con `grim` + `slurp` (copia al portapapeles).
- Volumen/brillo (`XF86Audio*`, `XF86MonBrightness*`) con `wpctl` y
  `brightnessctl`.
- REPL (`M-S-colon`) y cambio de TTY (`C-A-F1..F12`).

## Notas del entorno de prueba

- Artix Linux (runit), wlroots 0.19.3 del repo `world`.
- Para captura de pantalla (M-S-s): `grim`, `slurp` y `wl-clipboard`.
- Para WiFi (menú de red): `networkmanager` (provee `nmcli`), con el servicio
  `NetworkManager` activo.
- Para Bluetooth (menú de red): `bluez` (daemon) + `bluez-utils` (provee
  `bluetoothctl`), con el servicio `bluetoothd` activo.
- Para las teclas de brillo: `brightnessctl`.
- Para audio (música, micrófono): PipeWire/PipeWire-pulse/WirePlumber
  (arrancados con `tbwm-audio`).

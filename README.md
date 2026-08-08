# tbwm-fixes

Arreglos para [tbwm](https://github.com/WheeledCord/tbwm) (TurboWM), un
compositor Wayland. Todo lo necesario para aplicarlos está en este repo:

- **`tbwm-fixes.patch`** — parche con los arreglos de `tbwm.c`, `config.h`,
  `config.def.h`, `config.mk`, `Makefile` e `install.sh`. El parche también
  **añade los archivos nuevos** `bluetooth.c`, `bluetooth.h` (módulo de
  emparejado Bluetooth del menú de red) y `tbwm-network`.
- **`config.scm`** — configuración de ejemplo funcional (bindings, Flatpak,
  audio, brillo, REPL, TTYs, menú de red).
- **`tbwm-audio`** — script para arrancar PipeWire/PipeWire-pulse/WirePlumber
  desde `(on-startup ...)` (tbwm no procesa XDG autostart). Si el stack queda
  solo con el sink "Dummy Output" (WirePlumber arrancó antes de que la tarjeta
  de sonido/udev estuviera lista), reinicia WirePlumber hasta 6 veces con una
  espera de 2s hasta detectar el hardware real. Funciona con cualquier tarjeta
  de sonido.
- **`tbwm-network`** — script para el menú de red (WiFi + Bluetooth): lista
  redes y dispositivos disponibles/conectados y genera los comandos para
  conectarse o desconectarse.
- **`tbwm-session`** — launcher de sesión opcional: arranca tbwm dentro de un
  bus de sesión D-Bus (`dbus-run-session`, o `dbus-launch` como fallback).
  Ya no es imprescindible: el propio tbwm auto-arranca el bus si falta (fix
  14), pero sirve si se quiere acotar el ciclo de vida del bus a la sesión.

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

### 8. Menú de red: el resaltado sigue al mouse
Igual que el menú de apps, el menú de red actualiza la fila resaltada según la
posición del mouse (`motionnotify`), con comprobación de límites y sin interferir
con el modo contraseña.

### 9. Captura de pantalla: selección con slurp
En modo `spawn-grab`, `motionnotify` reenviaba el movimiento del puntero al seat
sin enviar `wlr_seat_pointer_notify_enter` antes; wlroots solo entrega
motion/button a la superficie con foco de puntero, así que la superficie de slurp
nunca recibía los eventos y no se podía seleccionar región (solo se veía el
overlay y Esc cancelaba). Ahora se recalcula la superficie bajo el cursor y se le
da foco de puntero si cambió (Enter y luego Motion), de modo que `S-Print`
(grim + slurp) funciona.

### 10. install.sh: soporte para Artix y paquete wlroots0.19
Artix reporta `ID=artix` en `/etc/os-release`, así que `install.sh` caía en la
rama "unknown distro": no instalaba dependencias (incluido meson/ninja) y luego
fallaba al compilar wlroots desde source con `meson: command not found`.
- Se agrega `artix` a los casos arch-based de `install_deps` y `build_wlroots`.
- En Artix se instala el paquete `wlroots0.19` (en Arch el `wlroots` normal ya es
  0.19+), con lo que `pkg-config wlroots-0.19` se encuentra y se **salta** la
  compilación de wlroots desde source.
- Antes de `meson setup` se verifica que `meson`/`ninja` existan y se aborta con
  un mensaje claro en vez de "command not found".
- Los `pacman` de arch-based usan `-Sy` para refrescar la base de datos antes de
  instalar: una DB desactualizada hace que pacman pida versiones que ya no están
  en los mirrors (404 en todos, p. ej. `python-tqdm`, dependencia de `meson`) y
  aborte toda la transacción sin instalar nada.
- El layout de teclado ya no se pide a ciegas: `install.sh` **detecta el layout
  activo** del sistema/DE (KDE `kxkbrc`, `/etc/default/keyboard`, config de Xorg,
  `localectl` en systemd, `gsettings` en GNOME, y `setxkbmap` solo en sesión X11
  pura) y lo ofrece como valor por defecto (`Enter` lo acepta,   `none`/`system
  default` usa el default del sistema). Valida la entrada para que un valor con
  espacios no rompa el flag `-DTBWM_XKB_LAYOUT=\"...\"`.

### 11. install.sh: instala las herramientas de captura (grim, slurp, wl-clipboard)
La config por defecto de tbwm genera bindings de captura con `grim` + `slurp` +
`wl-copy`, pero `install.sh` no instalaba esas herramientas: en una instalación
limpia `Print`/`S-Print` fallaban con `grim: command not found` (y no se podía
sacar ninguna captura). Ahora `install.sh` los instala en las dependencias de
todas las distros (Arch/Artix, Debian, Fedora, openSUSE, Void) y los lista en el
mensaje de "unknown distro".

### 12. Menú de red funcional de serie (deps + script + config)
El menú de red (WiFi + Bluetooth) no funcionaba en instalaciones limpias por tres
motivos: no se instalaban `networkmanager` (nmcli) ni `bluez`/`bluez-utils`
(bluetoothctl), el helper `tbwm-network` no se instalaba, y la config por defecto
no incluía `(set-net-menu-cmd ...)` (así que `netmenu_cmd` quedaba vacío y el
menú no mostraba nada aunque hubiera herramientas).
- `install.sh` instala `networkmanager bluez bluez-utils` (con sus paquetes
  `-runit` en Artix: `networkmanager-runit`, `bluez-runit`, `dbus-runit`),
  copia `tbwm-network` a `/usr/local/bin/tbwm-network` y activa
  `NetworkManager`/`bluetoothd` según el init detectado (systemd con
  `enable --now`, runit con symlinks en `runsvdir/current`, openrc con
  `rc-update`).
- `tbwm-network` ahora avisa en el menú cuando falta `nmcli` o `bluetoothctl`
  (entrada "Info" con el paquete a instalar) en vez de mostrar un menú vacío.
- La config por defecto incluye `(set-net-menu-cmd "tbwm-network")` y el binding
  `M-n` → `(toggle-net-menu)`. Nota: la config por defecto solo se crea si
  `~/.config/tbwm/config.scm` no existe; quien ya tenga una config debe añadir
  esas dos líneas o borrar el archivo para regenerarlo.

### 13. Audio: sockets de PipeWire huérfanos tras un crash
Si el WM crashea y los procesos de PipeWire se matan a la fuerza (p. ej. con
`pkill -9` desde `artix-pipewire-launcher`), los sockets del stack de audio
pueden quedar huérfanos: `wpctl status` falla con "Could not connect to
PipeWire" aunque los daemons estén corriendo y las tarjetas ALSA existan. El
script `tbwm-audio` detecta ese estado (falta el socket
`$XDG_RUNTIME_DIR/pipewire-0` o `wpctl status` falla) y reinicia **todo** el
stack (pipewire, pipewire-pulse y wireplumber), no solo WirePlumber; después
mantiene el bucle de reintentos hasta encontrar el sink real (nada de "Dummy
Output").

### 14. Sesión sin bus D-Bus (Flatpak y portales de captura)
Lanzar tbwm directamente desde una TTY deja a todas las apps spawnadas sin
`DBUS_SESSION_BUS_ADDRESS`: Flatpak falla con
`Can't find bus: ... «dbus-launch» (No existe el fichero o el directorio)` y
los XDG desktop portals no pueden activarse. Además, en Wayland la captura de
pantalla (p. ej. GPU Screen Recorder) pasa por el portal
`org.freedesktop.portal.ScreenCast`, que necesita el backend
`xdg-desktop-portal-wlr` para implementarse sobre `wlr-screencopy`.
- **`tbwm.c`**: en `main()` arranca un bus de sesión automáticamente si no hay
  `DBUS_SESSION_BUS_ADDRESS` (típico al lanzar desde TTY): spawna
  `dbus-launch --sh-syntax`, exporta la dirección y el pid, y lo apaga en
  `cleanup()`. Así **tbwm funciona tal cual**, sin launcher. Además exporta
  `XDG_CURRENT_DESKTOP=tbwm` (si no está definida): el frontend de
  xdg-desktop-portal elige su backend comparando ese valor con el `UseIn=` de
  cada `.portal`; sin él no se seleccionaba el backend `wlr` (el único que
  implementa ScreenCast/captura en Wayland) y compartir pantalla (Discord,
  Brave) fallaba en silencio.
- `install.sh` instala `xdg-desktop-portal xdg-desktop-portal-gtk
  xdg-desktop-portal-wlr` y añade `tbwm` al `UseIn=` de `wlr.portal` para que
  el frontend elija el backend wlr para ScreenCast.
- (Opcional) Launcher `tbwm-session`: arranca la sesión con
  `dbus-run-session`/`dbus-launch` antes de tbwm. Ya no es necesario con el
  auto-start del propio tbwm, pero no estorba si se prefiere acotar el ciclo
  de vida del bus a la sesión. El `.desktop` de sesión usa
  `Exec=/usr/local/bin/tbwm-session` si está instalado.
- Nota: hay que **relanzar la sesión**; las apps ya corriendo no heredan el bus
  retroactivamente.

### 15. Menú de red con connman y NetworkManager (elegir gestor activo)
`tbwm-network` solo hablaba con `nmcli`, así que en un sistema que usa **connman**
el menú no mostraba nada. Peor: `install.sh` (fix 12) activaba el servicio
NetworkManager en **todos** los sistemas, de modo que en una máquina connman
quedaban instalados/activados los dos gestores a la vez, y al no poder operar la
interfaz el sistema se quedaba sin internet (la "incompatibilidad" era eso: dos
gestores de red instalados a la vez, aunque el servicio NetworkManager no llegara
a estar activo).
- `tbwm-network` ahora **detecta el gestor activo** y usa el apropiado:
  - `connmand` corriendo → lista y conecta con `connmanctl` (`enable wifi`,
    `scan wifi`, `services`), marcando las redes `wifi_*_psk`/`wifi_*_wep` como
    `needspass=1`. Para conectar con contraseña usa
    `connmanctl config <id> --passphrase ... --save && connmanctl connect <id>`
    (tbwm añade ` password '<...>'` al comando, y el helper lo recibe en `$3`).
  - NetworkManager corriendo (`nmcli ... RUNNING = running`) → rama `nmcli`
    original.
  - Ninguno → entrada "Info" indicando cuál activar (en vez de menú vacío).
- `install.sh`:
  - `detect_net_backend()` elige connman si `connmand` corre (o `connmanctl`
    existe) y NetworkManager si no.
  - En Artix instala `connman connman-runit` en vez de `networkmanager
    networkmanager-runit` cuando el backend es connman.
  - `enable_net_services()` **activa solo un gestor y desactiva el otro**
    (systemd `disable --now`, runit `rm`+`sv down` del symlink contrario, openrc
    `rc-update del`), además de `bluetoothd`, para que no vuelvan a pelear.
- Para quien ya tenga el sistema roto: desactivar uno de los dos gestores y
  reconectar las redes guardadas (cada gestor guarda su propia lista, así que al
  cambiar de gestor hay que reconectar las redes una vez).

### 16. Bluetooth: la categoría desaparecía del menú
El bloque Bluetooth de `tbwm-network` solo imprimía `bluetoothctl devices`
(dispositivos ya cacheados por `bluetoothd`), y el escaneo duraba 2s. Como el
menú de tbwm solo muestra categorías con al menos una entrada, si la caché estaba
vacía la sección Bluetooth no aparecía:
- El escaneo ahora dura ~8s (`timeout 10 bluetoothctl scan on` + `sleep 8`) para
  que los dispositivos cercanos se descubran y queden cacheados.
- Si aun así no hay dispositivos, se emite siempre una entrada `Info` "[BT] Sin
  dispositivos cerca (reintenta)" para que la categoría **nunca** desaparezca.
- Conectar un dispositivo no emparejado ahora hace
  `bluetoothctl pair <MAC>; bluetoothctl trust <MAC>; bluetoothctl connect <MAC>`
  (con `;` y no `&&`: si ya estaba emparejado, `pair` falla y no debe cortar el
  `connect`).
- Nota: si la categoría sigue sin aparecer, verificar que `bluez`/`bluez-utils`/
  `bluez-runit` estén instalados y que el servicio esté activo
  (`sudo ln -sf /etc/runit/sv/bluetoothd /run/runit/service/bluetoothd` y
  `sudo sv up bluetoothd`; en Artix/runit), y que el adaptador no esté bloqueado
  (`rfkill list bluetooth`, `sudo rfkill unblock bluetooth`).

### 17. Menú de red: cada red/dispositivo con acciones (Conectar/Desconectar/Olvidar)
`tbwm-network` ahora emite cada red WiFi y cada dispositivo Bluetooth como su
**propio sub-tema** (grupo) del menú, con sus acciones como entradas. Al pulsar
Enter o hacer clic sobre una red/dispositivo en vez de ejecutar directamente:
- **Guardada o visible**: acciones `Conectar a <nombre>` y `Olvidar <nombre>`.
- **Conectada**: acciones `Desconectar <nombre>` y `Olvidar <nombre>`.
- Wifi (NetworkManager): guardadas vía `nmcli connection up/down/delete`; las
  disponibles no guardadas solo `Conectar` (pide contraseña con el diálogo del
  menú si hay seguridad).
- Wifi (connman): `connmanctl connect/disconnect/remove`; las protegidas sin
  guardar piden contraseña (`connmanctl config <id> --passphrase ... --save`).
- Bluetooth: conectado → `bluetoothctl disconnect`/`remove`; emparejado →
  `bluetoothctl connect`/`remove`; visible sin emparejar → `pair`+`trust`+
  `connect`.
- Las redes que aparecen guardadas y en el escaneo a la vez se emiten **una sola
  vez** (sin duplicados en el menú).

### 18. Menú de red: sub-apartados por tipo (Conectado / Guardadas / Buscar)
Los grupos de `tbwm-network` se reordenan en sub-apartados para que la red
conectada aparezca siempre primero y la lista no sea un batiburrillo:
- **Wifi**: `Conectado` (acciones `Desconectar` + `Olvidar`) → `Guardadas`
  (`Conectar` + `Olvidar`) → `Buscar red` (`Conectar`, con %) de las visibles
  no guardadas.
- **Bluetooth**: `Conectado` → `Emparejados` → `Buscar dispositivos` (nuevos
  sin emparejar). Cada dispositivo lleva sus MAC correctos en los comandos
  (`bluetoothctl disconnect/remove <MAC>`, `connect <MAC>`, ...).
- Todos los sub-apartados **aparecen siempre**; los que quedan sin contenido
  muestran un placeholder `[sin ...]`, así ningún sub-apartado desaparece del
  menú aunque no haya dispositivos en ese estado.

### 19. Menú de red con 4 niveles (guardadas con sub-tema por red)
El menú de red ahora soporta **jerarquía de 4 niveles** en `tbwm.c`:

`Categoría → Sub-apartado → Red/Dispositivo → Acción`

- `tbwm-network` emite `Category<TAB>Group<TAB>Subgroup<TAB>Name<TAB>exec` (5
  columnas; el parser de `tbwm.c` también acepta el formato viejo de 4).
- Ejemplo: `Wifi → Guardadas → AndroidAP_2708 → Conectar` / `Olvidar`, y
  `Wifi → Conectado → Wifi-Claro (83%) → Desconectar` / `Olvidar`.
- La red conectada se muestra con nombre + % de señal en el sub-tema: entrar en
  ella revela `Desconectar` / `Olvidar`.
- Bluetooth igual: `Conectado` / `Emparejados` / `Buscar dispositivos`, cada
  dispositivo como sub-tema con sus acciones.
- Requiere recompilar `tbwm` (`make` + instalar binario); Navgación igual
  (Enter/←, `< Back`, Esc).
- Para que los **sub-apartados** (p. ej. `Conectado`, `Guardadas`, `Buscar red`)
  se dibujen, `updatenetmenu()` debe tener la rama `net_current_group < 0` que
  pinta la lista de sub-temas antes del nivel de entidades; sin ella el menú
  quedaba vacío (leía `net_groups[-1]`).

### 20. Bluetooth: rescan en vivo + diálogo de emparejado en el menú (confirmar PIN)
El flujo de Bluetooth ahora se completa **dentro del menú de red**, sin salir a
la terminal:

- `tbwm-network` hace **rescan en vivo**: re-lanza el escaneo bluetooth mientras
  el menú está en el sub-apartado "Buscar dispositivos", fusiona los
  dispositivos descubiertos con los ya cacheados y emite cada uno con el flag
  `BTPAIR` en la 6ª columna (`...<TAB><MAC><TAB>BTPAIR`).
- Al elegir "Conectar" sobre un dispositivo sin emparejar, `tbwm` abre un
  **diálogo de emparejado** que muestra el **PIN/passkey** que BlueZ está
  pidiendo y dos filas de teclas/estado. El usuario confirma con `S`/`Enter`
  (`yes` al prompt de bluetoothctl) o rechaza con `N`/`Esc` (`no`), y el `connect`
  solo se envía una vez visto "Pairing successful/complete". El `connect` nunca
  se cola antes de tiempo
  (bluetoothctl lee stdin línea a línea y consumiría el comando como respuesta
  al prompt).
- **Escucha pasiva**: las peticiones de emparejado **iniciadas desde el celular**
  mientras el menú está abierto en "Buscar dispositivos" también abren el
  diálogo (con el nombre/MAC extraídos de la línea `[NEW] Device ...` emitida por
  bluetoothctl) para confirmar el PIN y cerrar el emparejado sin salir del menú.
  Un watchdog (`blt_watchdog`, cada 3s) mantiene el agente `KeyboardDisplay`
  vivo solo mientras se navega esa sub-vista y lo detiene al salir/cerrar.
- **`bluetooth.c` como módulo**: toda la lógica de emparejado (spawn de
  `bluetoothctl`, pipes stdin/stdout, fd watcher del event loop, watchdog y
  máquina de estados del PIN) vive en un módulo separado (`bluetooth.h`
  expone la API opaca `blt_*`); `tbwm.c` solo dibuja el diálogo y enruta las
  teclas del menú vía `blt_key()`. En `cleanup()` se mata la sesión de
  `bluetoothctl` si el WM muere con un diálogo abierto (evita huérfanos).
- Requiere recompilar `tbwm` (`make` + instalar binario).

## Menú de red (WiFi + Bluetooth)

Menú combinado de WiFi y Bluetooth. Se abre con `M-n` o haciendo clic en el
botón `[N]` de la barra (justo a la izquierda de la fecha/hora).

### Qué hace
- Categorías **Wifi** y **Bluetooth**, cada una mostrando **una entrada por
  red/dispositivo**:
  - Seleccionando una red/dispositivo se ven sus acciones: **Conectar a ...**,
    **Desconectar ...** (si está conectada) y **Olvidar ...**.
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
(paquete `bluez-utils`, con el daemon `bluez`) para Bluetooth. `install.sh` los
instala y activa los servicios automáticamente; en una instalación manual
asegúrate de que los daemons `NetworkManager` y `bluetoothd` estén corriendo.
Emite una línea
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
"Menú de red"). Para que las apps Flatpak y los portales de captura funcionen,
lanza la sesión con `tbwm-session` (ver fix 14) en vez de `tbwm`.

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

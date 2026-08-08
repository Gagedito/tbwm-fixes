#!/bin/bash
set -e

# Get the directory where this script lives
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Detect distro
detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO="$ID"
        DISTRO_LIKE="$ID_LIKE"
    elif [ -f /etc/arch-release ]; then
        DISTRO="arch"
    elif [ -f /etc/debian_version ]; then
        DISTRO="debian"
    elif [ -f /etc/fedora-release ]; then
        DISTRO="fedora"
    else
        DISTRO="unknown"
    fi
    info "Detected distro: $DISTRO"
}

# Check if running as root
check_not_root() {
    if [ "$EUID" -eq 0 ]; then
        error "Don't run this script as root. It will ask for sudo when needed."
    fi
}

# Install dependencies based on distro
install_deps() {
    info "Installing dependencies..."
    
    case "$DISTRO" in
        arch|endeavouros|manjaro|garuda|cachyos|artix)
            # Arch-based. Artix ships wlroots 0.19 as the wlroots0.19 package;
            # on Arch the regular wlroots package is already 0.19+.
            if [ "$DISTRO" = "artix" ]; then
                WLROOTS_PKG="wlroots0.19"
                # runit service packages for the WiFi/Bluetooth menu. If connman
                # is already installed, keep using it instead of NetworkManager
                # (installing both leaves the network menu without a backend).
                if [ "$NET_BACKEND" = "connman" ]; then
                    NET_DEPS="connman connman-runit bluez bluez-utils bluez-runit dbus-runit"
                else
                    NET_DEPS="networkmanager networkmanager-runit bluez bluez-utils bluez-runit dbus-runit"
                fi
            else
                WLROOTS_PKG="wlroots"
                NET_DEPS="networkmanager bluez bluez-utils"
            fi
            sudo pacman -Sy --needed --noconfirm \
                "$WLROOTS_PKG" wayland wayland-protocols libinput libxkbcommon \
                pixman freetype2 pango cairo libxcb xcb-util-wm \
                xorg-xwayland meson ninja gcc pkgconf make git \
                fontconfig ttf-font grim slurp wl-clipboard $NET_DEPS \
                xdg-desktop-portal xdg-desktop-portal-gtk xdg-desktop-portal-wlr || true
            ;;
        debian|ubuntu|pop|linuxmint|elementary)
            # Debian-based - note: libwlroots-dev often not available or too old
            sudo apt-get update
            sudo apt-get install -y \
                libwayland-dev wayland-protocols \
                libinput-dev libxkbcommon-dev libpixman-1-dev \
                libfreetype-dev libpango1.0-dev libcairo2-dev \
                libxcb1-dev libxcb-icccm4-dev xwayland \
                libdrm-dev libgbm-dev libseat-dev \
                libdisplay-info-dev libliftoff-dev hwdata \
                meson ninja-build gcc pkg-config make git \
                fontconfig grim slurp wl-clipboard networkmanager bluez || true
            ;;
        fedora|rhel|centos|rocky|almalinux)
            # Fedora/RHEL-based
            sudo dnf install -y \
                wlroots-devel wayland-devel wayland-protocols-devel \
                libinput-devel libxkbcommon-devel pixman-devel \
                freetype-devel pango-devel cairo-devel \
                libxcb-devel xcb-util-wm-devel xorg-x11-server-Xwayland \
                meson ninja-build gcc pkg-config make git \
                fontconfig grim slurp wl-clipboard NetworkManager bluez || true
            ;;
        opensuse*|suse*)
            # openSUSE
            sudo zypper install -y \
                wlroots-devel wayland-devel wayland-protocols-devel \
                libinput-devel libxkbcommon-devel libpixman-1-0-devel \
                freetype2-devel pango-devel cairo-devel \
                libxcb-devel xwayland meson ninja gcc pkg-config make git \
                fontconfig grim slurp wl-clipboard NetworkManager bluez || true
            ;;
        void)
            # Void Linux
            sudo xbps-install -Sy \
                wlroots-devel wayland-devel wayland-protocols \
                libinput-devel libxkbcommon-devel pixman-devel \
                freetype-devel pango-devel cairo-devel \
                libxcb-devel xcb-util-wm-devel xorg-server-xwayland \
                meson ninja gcc pkg-config make git fontconfig \
                grim slurp wl-clipboard NetworkManager bluez || true
            ;;
        gentoo)
            warn "Gentoo detected. Please ensure you have the following USE flags enabled:"
            warn "  dev-libs/wlroots gui-wm/dwl"
            warn "Run: sudo emerge --ask wlroots wayland freetype pango xwayland"
            ;;
        nixos)
            warn "NixOS detected. Dependencies should be in your configuration.nix"
            warn "Or use: nix-shell -p wlroots wayland freetype pango"
            ;;
        *)
            warn "Unknown distro: $DISTRO"
            warn "Please install these dependencies manually:"
            echo "  - wlroots >= 0.19"
            echo "  - wayland, wayland-protocols"
            echo "  - libinput, libxkbcommon"
            echo "  - freetype2, pango, cairo, pixman"
            echo "  - libxcb, xcb-util-wm"
            echo "  - grim, slurp, wl-clipboard (for screenshots)"
            echo "  - networkmanager (nmcli) and bluez/bluez-utils (bluetoothctl) for the network menu"
            echo "  - xwayland (optional, for X11 apps)"
            echo ""
            read -p "Continue anyway? [y/N] " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                exit 1
            fi
            ;;
    esac
    success "Dependencies installed"
}

# Detect the keyboard layout currently used on the system / DE.
# Order matters: file-based sources reflect the real layout, while
# setxkbmap -query reports the X layout and is only reliable in a pure
# X11 session (under Wayland it would query XWayland, which is wrong).
detect_keyboard_layout() {
    local detected=""

    # 1. KDE Plasma
    if [ -z "$detected" ] && [ -f "$HOME/.config/kxkbrc" ]; then
        detected="$(sed -n 's/^LayoutList=//p' "$HOME/.config/kxkbrc" | head -1)"
    fi

    # 2. /etc/default/keyboard (Debian/Ubuntu, also present on some Arch/Artix systems)
    if [ -z "$detected" ] && [ -f /etc/default/keyboard ]; then
        detected="$(sed -n 's/^XKBLAYOUT="\?\([^"]*\)"\?.*/\1/p' /etc/default/keyboard)"
    fi

    # 3. Xorg keyboard config
    if [ -z "$detected" ] && [ -d /etc/X11/xorg.conf.d ]; then
        detected="$(grep -rhoE 'XkbLayout[[:space:]]+"[^"]+"' /etc/X11/xorg.conf.d 2>/dev/null | head -1 | sed -E 's/.*"([^"]+)"/\1/')"
    fi

    # 4. systemd-based distros
    if [ -z "$detected" ] && command -v localectl >/dev/null 2>&1; then
        detected="$(localectl status 2>/dev/null | awk '/X11 Layout/{print $3}')"
    fi

    # 5. GNOME
    if [ -z "$detected" ] && command -v gsettings >/dev/null 2>&1; then
        detected="$(gsettings get org.gnome.desktop.input-sources sources 2>/dev/null | sed -n "s/.*'xkb', *'\([^']*\)'.*/\1/p")"
    fi

    # 6. Pure X11 session only (setxkbmap is unreliable under Wayland/XWayland)
    if [ -z "$detected" ] && [ "$XDG_SESSION_TYPE" = "x11" ] && command -v setxkbmap >/dev/null 2>&1; then
        detected="$(setxkbmap -query 2>/dev/null | awk -F': *' '/layout/{print $2; exit}')"
    fi

    # Sanitize: layouts never contain spaces
    if [[ "$detected" =~ [^A-Za-z0-9_,()+.-] ]]; then
        detected=""
    fi

    echo "$detected"
}

# Ask for the keyboard layout to bake into the compositor, defaulting to the
# layout detected on the system / DE when possible.
setup_keyboard_layout() {
    local detected
    detected="$(detect_keyboard_layout)"

    echo ""
    if [ -n "$detected" ]; then
        echo "Detected keyboard layout: $detected"
        echo "  (press Enter to use it, type another layout, or 'none' for system default)"
        read -r -p "Keyboard layout [$detected]: " kblayout
        case "$kblayout" in
            "")
                kblayout="$detected"
                ;;
            "system default"|"system"|"default"|"none")
                kblayout=""
                ;;
        esac
    else
        echo "No keyboard layout detected on this system."
        echo "  e.g. latam, us, es, de, fr, gb  (empty = system default)"
        read -r -p "Keyboard layout: " kblayout
        case "$kblayout" in
            ""|"system default"|"system"|"default"|"none")
                kblayout=""
                ;;
        esac
    fi

    # Safety net: layouts are single tokens without spaces; reject anything else.
    if [[ "$kblayout" =~ [^A-Za-z0-9_,()+.-] ]]; then
        warn "Invalid keyboard layout '$kblayout'. Using system default."
        kblayout=""
    fi

    if [ -n "$kblayout" ]; then
        export TBWM_XKB_LAYOUT="$kblayout"
        info "Will build with keyboard layout: $kblayout"
    else
        info "Using system default keyboard layout"
    fi
}

# Check wlroots version
check_wlroots() {
    info "Checking wlroots version..."
    
    if ! pkg-config --exists wlroots-0.19 2>/dev/null; then
        if pkg-config --exists wlroots 2>/dev/null; then
            WLROOTS_VER=$(pkg-config --modversion wlroots 2>/dev/null || echo "unknown")
            warn "Found wlroots $WLROOTS_VER but need wlroots 0.19+"
        else
            warn "wlroots not found"
        fi
        
        echo ""
        echo "TurboWM requires wlroots 0.19 or newer."
        echo ""
        echo "Options:"
        echo "  1) Build wlroots 0.19 from source (recommended)"
        echo "  2) Skip and try to build anyway"
        echo "  3) Exit"
        echo ""
        read -p "Choice [1/2/3]: " -n 1 -r
        echo
        
        case $REPLY in
            1)
                build_wlroots
                ;;
            2)
                warn "Continuing without wlroots 0.19 - build may fail"
                ;;
            *)
                exit 1
                ;;
        esac
    else
        WLROOTS_VER=$(pkg-config --modversion wlroots-0.19)
        success "Found wlroots $WLROOTS_VER"
    fi
}

# Build wlroots from source
build_wlroots() {
    info "Building wlroots 0.19 from source..."
    
    # Install meson build deps
    case "$DISTRO" in
        arch|endeavouros|manjaro|garuda|cachyos|artix)
            sudo pacman -Sy --needed --noconfirm \
                meson ninja hwdata libdisplay-info libliftoff seatd || true
            ;;
        debian|ubuntu|pop|linuxmint|elementary)
            sudo apt-get install -y \
                meson ninja-build libdrm-dev libgbm-dev libseat-dev \
                libdisplay-info-dev libliftoff-dev hwdata || true
            ;;
        fedora|rhel|centos|rocky|almalinux)
            sudo dnf install -y \
                meson ninja-build libdrm-devel mesa-libgbm-devel \
                libseat-devel libdisplay-info-devel libliftoff-devel hwdata || true
            ;;
    esac
    
    WLROOTS_BUILD_DIR="/tmp/wlroots-build-$$"
    mkdir -p "$WLROOTS_BUILD_DIR"
    cd "$WLROOTS_BUILD_DIR"
    
    info "Cloning wlroots..."
    git clone --depth 1 --branch 0.19.0 https://gitlab.freedesktop.org/wlroots/wlroots.git
    cd wlroots
    
    info "Configuring..."
    if ! command -v meson >/dev/null 2>&1 || ! command -v ninja >/dev/null 2>&1; then
        error "meson/ninja not found. Install them and re-run (e.g. 'sudo pacman -S meson ninja' on Arch/Artix, 'sudo apt install meson ninja-build' on Debian/Ubuntu)."
    fi
    meson setup build --prefix=/usr/local -Dexamples=false
    
    info "Building..."
    ninja -C build
    
    info "Installing (requires sudo)..."
    sudo ninja -C build install
    
    # Update library cache
    sudo ldconfig
    
    # Cleanup
    cd /
    rm -rf "$WLROOTS_BUILD_DIR"
    
    # Check if it worked
    export PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:/usr/local/lib64/pkgconfig:$PKG_CONFIG_PATH"
    if pkg-config --exists wlroots-0.19 2>/dev/null; then
        success "wlroots 0.19 installed to /usr/local"
    else
        error "wlroots installation failed"
    fi
}

# Build TurboWM
build_tbwm() {
    info "Building TurboWM..."
    
    # Go back to source directory (in case we built wlroots)
    cd "$SCRIPT_DIR"
    
    # Make sure we can find locally-installed wlroots
    export PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:/usr/local/lib64/pkgconfig:/usr/local/lib/x86_64-linux-gnu/pkgconfig:$PKG_CONFIG_PATH"
    export LD_LIBRARY_PATH="/usr/local/lib:/usr/local/lib64:/usr/local/lib/x86_64-linux-gnu:$LD_LIBRARY_PATH"
    
    # Clean without regenerating protocol headers
    rm -f tbwm *.o 2>/dev/null || true
    
    # Touch protocol headers to prevent make from regenerating them
    # (they're already in the repo, but git clone can mess up timestamps)
    touch *-protocol.h 2>/dev/null || true
    
    TMPDIR="$HOME" make -j$(nproc)
    
    success "TurboWM built successfully"
}

# Install TurboWM
install_tbwm() {
    info "Installing TurboWM..."
    
    # Binary
    sudo cp tbwm /usr/local/bin/
    sudo chmod 755 /usr/local/bin/tbwm
    success "Installed /usr/local/bin/tbwm"
    
    # Font: copy from local fonts/ directory (no network)
    sudo mkdir -p /usr/share/fonts/tbwm
    if [ -f fonts/PxPlus_IBM_VGA_8x16.ttf ]; then
        sudo cp fonts/PxPlus_IBM_VGA_8x16.ttf /usr/share/fonts/tbwm/
    elif [ -f PxPlus_IBM_VGA_8x16.ttf ]; then
        sudo cp PxPlus_IBM_VGA_8x16.ttf /usr/share/fonts/tbwm/
    else
        warn "PxPlus_IBM_VGA_8x16.ttf not found in fonts/; skipping font install"
    fi

    if [ -f fonts/unscii-8x16.ttf ]; then
        sudo cp fonts/unscii-8x16.ttf /usr/share/fonts/tbwm/
    elif [ -f unscii-8x16.ttf ]; then
        sudo cp unscii-8x16.ttf /usr/share/fonts/tbwm/
    else
        warn "unscii-8x16.ttf not found in fonts/; skipping fallback font install"
    fi

    sudo fc-cache -f /usr/share/fonts/tbwm 2>/dev/null || true
    success "Installed fonts (from fonts/ directory)"
    
    # tbwm-network helper for the WiFi/Bluetooth menu
    if [ -f "$SCRIPT_DIR/tbwm-network" ]; then
        sudo cp "$SCRIPT_DIR/tbwm-network" /usr/local/bin/tbwm-network
        sudo chmod 755 /usr/local/bin/tbwm-network
        success "Installed /usr/local/bin/tbwm-network"
    else
        warn "tbwm-network not found; the network menu (WiFi/Bluetooth) will be empty"
    fi
    
    # tbwm-session launcher (starts a session D-Bus bus so Flatpak apps and
    # the XDG desktop portals can connect)
    if [ -f "$SCRIPT_DIR/tbwm-session" ]; then
        sudo cp "$SCRIPT_DIR/tbwm-session" /usr/local/bin/tbwm-session
        sudo chmod 755 /usr/local/bin/tbwm-session
        success "Installed /usr/local/bin/tbwm-session"
    else
        warn "tbwm-session not found; apps may have no session D-Bus bus (Flatpak/portals may fail)"
    fi
    
    # tbwm-wallpaper: wallpaper dinámico con waywallen (opcional, con degradado:
    # sin waywallen instalado el script no hace nada y el fondo queda por defecto)
    if [ -f "$SCRIPT_DIR/tbwm-wallpaper" ]; then
        sudo cp "$SCRIPT_DIR/tbwm-wallpaper" /usr/local/bin/tbwm-wallpaper
        sudo chmod 755 /usr/local/bin/tbwm-wallpaper
        success "Installed /usr/local/bin/tbwm-wallpaper"
        warn "wallpaper dinámico opcional: requerirá waywallen (Flatpak) y waywallen-layer-shell; ver sección \"Fondo de pantalla\" del README"
    fi
    
    # Session file for display managers
    sudo mkdir -p /usr/share/wayland-sessions
    sudo tee /usr/share/wayland-sessions/tbwm.desktop > /dev/null << 'EOF'
[Desktop Entry]
Name=TurboWM
Comment=A Wayland compositor with s7 Scheme configuration
Exec=/usr/local/bin/tbwm-session
Type=Application
EOF
    success "Installed session file"
    
    # Create default config if it doesn't exist
    if [ ! -f "$HOME/.config/tbwm/config.scm" ]; then
        mkdir -p "$HOME/.config/tbwm"
        if [ -f "docs/example-config.scm" ]; then
            cp docs/example-config.scm "$HOME/.config/tbwm/config.scm"
            success "Created default config at ~/.config/tbwm/config.scm"
        fi
    fi
    
    # If wlroots was built from source, create a wrapper that sets LD_LIBRARY_PATH
    if [ -f "/usr/local/lib/libwlroots-0.19.so" ] || [ -f "/usr/local/lib64/libwlroots-0.19.so" ]; then
        info "Custom wlroots detected, creating launcher wrapper..."
        # Move the real binary
        if [ -f /usr/local/bin/tbwm ] && [ ! -L /usr/local/bin/tbwm ]; then
            sudo mv /usr/local/bin/tbwm /usr/local/bin/tbwm.bin
        fi
        # Create wrapper as the main command
        sudo tee /usr/local/bin/tbwm > /dev/null << 'EOF'
#!/bin/bash
export LD_LIBRARY_PATH="/usr/local/lib:/usr/local/lib64:$LD_LIBRARY_PATH"
exec /usr/local/bin/tbwm.bin "$@"
EOF
        sudo chmod 755 /usr/local/bin/tbwm
    fi

    enable_net_services

    # Make the XDG desktop portal frontend pick xdg-desktop-portal-wlr for
    # screen capture (ScreenCast). The frontend matches XDG_CURRENT_DESKTOP
    # (tbwm sets it to "tbwm") against each .portal file's UseIn= list, so
    # "tbwm" must be in that list for the wlr backend to be chosen.
    WLR_PORTAL="/usr/share/xdg-desktop-portal/portals/wlr.portal"
    if [ -f "$WLR_PORTAL" ]; then
        if ! grep -q 'UseIn=.*tbwm' "$WLR_PORTAL"; then
            sudo sed -i 's/^UseIn=\(.*\)$/UseIn=tbwm;\1/' "$WLR_PORTAL"
            success "Added tbwm to UseIn in wlr.portal"
        else
            info "tbwm already in UseIn of wlr.portal"
        fi
    else
        warn "wlr.portal not found; screen capture (ScreenCast) may not work"
    fi
}

# Pick which network manager is in use (connman and NetworkManager conflict if
# both are enabled at the same time, so we always enable exactly one of them).
detect_net_backend() {
    NET_BACKEND="networkmanager"
    if pgrep -x connmand >/dev/null 2>&1; then
        NET_BACKEND="connman"
    elif [ "$(nmcli -t -f RUNNING general status 2>/dev/null)" = "running" ]; then
        NET_BACKEND="networkmanager"
    elif command -v connmanctl >/dev/null 2>&1; then
        NET_BACKEND="connman"
    fi
    info "Network backend: $NET_BACKEND"
}

# Enable the active network manager and Bluetooth services for the menu
enable_net_services() {
    detect_net_backend
    if [ "$NET_BACKEND" = "connman" ]; then
        NET_SERVICE="connmand"
        info "Enabling connman ($NET_SERVICE) and Bluetooth services..."
    else
        NET_SERVICE="NetworkManager"
        info "Enabling NetworkManager and Bluetooth services..."
    fi

    if [ -d /run/systemd/system ] && command -v systemctl >/dev/null 2>&1; then
        # ensure only one network manager is enabled/started
        if [ "$NET_SERVICE" = "connmand" ]; then
            sudo systemctl disable --now NetworkManager 2>/dev/null || true
        else
            sudo systemctl disable --now connmand 2>/dev/null || true
        fi
        sudo systemctl enable --now "$NET_SERVICE" bluetooth 2>/dev/null || \
            warn "Could not enable $NET_SERVICE/bluetooth (systemd)"
    elif [ -d /etc/runit/runsvdir/current ]; then
        # runit (Artix, Void): link service dirs into runsvdir
        OTHER="connmand"
        [ "$NET_SERVICE" = "connmand" ] && OTHER="NetworkManager"
        # remove the other manager so they never fight over the interface
        if [ -d "/etc/runit/sv/$OTHER" ]; then
            sudo rm -f "/etc/runit/runsvdir/current/$OTHER"
            sudo sv down "$OTHER" 2>/dev/null || true
            info "runit service '$OTHER' disabled"
        fi
        for svc in "$NET_SERVICE" bluetoothd; do
            if [ -d "/etc/runit/sv/$svc" ]; then
                sudo ln -sf "/etc/runit/sv/$svc" "/etc/runit/runsvdir/current/"
                sudo sv up "$svc" 2>/dev/null || true
                info "runit service '$svc' enabled"
            else
                warn "runit service dir /etc/runit/sv/$svc not found (is the -runit package installed?)"
            fi
        done
    elif command -v rc-update >/dev/null 2>&1; then
        # openrc (Gentoo, Artix-openrc)
        OTHER="connmand"
        [ "$NET_SERVICE" = "connmand" ] && OTHER="NetworkManager"
        sudo rc-update del "$OTHER" default 2>/dev/null || true
        sudo rc-service "$OTHER" stop 2>/dev/null || true
        sudo rc-update add "$NET_SERVICE" default 2>/dev/null || \
            warn "could not add $NET_SERVICE to openrc default"
        sudo rc-update add bluetoothd default 2>/dev/null || \
            warn "could not add bluetoothd to openrc default"
        sudo rc-service "$NET_SERVICE" start 2>/dev/null || true
        sudo rc-service bluetoothd start 2>/dev/null || true
    else
        warn "Unknown init system: enable $NET_SERVICE and Bluetooth manually"
    fi
}

# Main
main() {
    echo ""
    echo "╔════════════════════════════════════════╗"
    echo "║     TurboWM Installer                  ║"
    echo "╚════════════════════════════════════════╝"
    echo ""alternitivealternitive
    
    check_not_root
    detect_distro
    detect_net_backend
    setup_keyboard_layout
    
    # Ask what to do
    echo ""
    echo "Options:"
    echo "  1) Full install (deps + build + install)"
    echo "  2) Build only (assumes deps installed)"
    echo "  3) Install only (assumes already built)"
    echo ""
    read -p "Choice [1/2/3]: " -n 1 -r
    echo
    
    case $REPLY in
        1)
            install_deps
            check_wlroots
            build_tbwm
            install_tbwm
            ;;
        2)
            check_wlroots
            build_tbwm
            ;;
        3)
            install_tbwm
            ;;
        *)
            error "Invalid choice"
            ;;
    esac
    
    echo ""
    echo "╔════════════════════════════════════════╗"
    echo "║     Installation Complete!             ║"
    echo "╚════════════════════════════════════════╝"
    echo ""
    echo "To use TurboWM:"
    echo "  • Log out and select 'TurboWM' from your display manager"
    echo "  • Or run: tbwm-session (from a TTY) - starts a session D-Bus bus"
    echo "    (use 'tbwm' directly only if you know you don't need one)"
    echo ""
    echo "Config file: ~/.config/tbwm/config.scm"
    echo ""
}

main "$@"

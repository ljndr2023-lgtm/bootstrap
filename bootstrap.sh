#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
log()  { printf "${GREEN}[✓]${NC} %s\n" "$1"; }
warn() { printf "${YELLOW}[!]${NC} %s\n" "$1"; }
err()  { printf "${RED}[✗]${NC} %s\n" "$1"; exit 1; }
info() { printf "${CYAN}[i]${NC} %s\n" "$1"; }

detect_os() {
    case "$(uname -s)" in
        Linux)
            if   [ -f /etc/arch-release ];     then OS="arch"
            elif [ -f /etc/debian_version ];   then OS="debian"
            elif [ -f /etc/fedora-release ];   then OS="fedora"
            else OS="linux"; fi
            ;;
        Darwin) OS="macos" ;;
        *) err "OS no soportado: $(uname -s)" ;;
    esac
    info "Sistema detectado: $OS"
}

check_sudo() {
    if [ "$EUID" -eq 0 ]; then
        err "No ejecutes como root. Usa un usuario normal con sudo."
    fi
    sudo -v
}

install_pkgs() {
    case "$OS" in
        arch)   sudo pacman -S --needed --noconfirm "$@" ;;
        debian) sudo apt-get install -y "$@" ;;
        fedora) sudo dnf install -y "$@" ;;
        macos)
            if ! command -v brew &>/dev/null; then
                /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
            fi
            brew install "$@"
            ;;
    esac
}

ensure_aur() {
    if command -v paru &>/dev/null; then return; fi
    warn "Instalando paru (AUR helper)..."
    sudo pacman -S --needed --noconfirm base-devel git
    git clone https://aur.archlinux.org/paru.git /tmp/paru
    (cd /tmp/paru && makepkg -si --noconfirm)
    rm -rf /tmp/paru
}

# ============================================================
#  DRIVERS
# ============================================================
setup_drivers() {
    info "--- Instalando drivers necesarios ---"

    # Detectar GPU
    if lspci | grep -E "VGA|3D" | grep -qi nvidia; then
        log "GPU NVIDIA detectada"
        case "$OS" in
            arch)   install_pkgs nvidia nvidia-utils nvidia-settings ;;
            debian) install_pkgs nvidia-driver nvidia-settings ;;
            fedora) install_pkgs akmod-nvidia xorg-x11-drv-nvidia-cuda ;;
        esac
    elif lspci | grep -E "VGA|3D" | grep -qi amd; then
        log "GPU AMD detectada"
        case "$OS" in
            arch)   install_pkgs mesa mesa-utils vulkan-radeon libva-mesa-driver ;;
            debian) install_pkgs mesa mesa-utils mesa-vulkan-drivers libva-drm2 ;;
            fedora) install_pkgs mesa mesa-utils mesa-vulkan-drivers libva-mesa-driver ;;
        esac
    elif lspci | grep -E "VGA|3D" | grep -qi intel; then
        log "GPU Intel detectada"
        case "$OS" in
            arch)   install_pkgs mesa mesa-utils vulkan-intel libva-intel-driver ;;
            debian) install_pkgs mesa mesa-utils mesa-vulkan-drivers intel-media-va-driver ;;
            fedora) install_pkgs mesa mesa-utils mesa-vulkan-drivers libva-intel-driver ;;
        esac
    else
        warn "No se pudo detectar GPU o es una GPU no soportada automáticamente."
    fi

    # Vulkan siempre útil (Steam, Heroic)
    case "$OS" in
        arch)   install_pkgs vulkan-icd-loader lib32-vulkan-icd-loader ;;
        debian) install_pkgs vulkan-tools libvulkan1 mesa-vulkan-drivers ;;
        fedora) install_pkgs vulkan-loader vulkan-tools ;;
    esac

    # Paquetes base para gaming
    case "$OS" in
        arch)   install_pkgs steam-native-runtime gamemode lib32-gamemode ;;
        debian) install_pkgs gamemode libgamemode0 ;;
        fedora) install_pkgs gamemode ;;
    esac
}

# ============================================================
#  GOOGLE CHROME
# ============================================================
setup_chrome() {
    info "--- Instalando Google Chrome ---"
    if command -v google-chrome-stable &>/dev/null; then
        log "Google Chrome ya está instalado"
        return
    fi
    case "$OS" in
        arch)
            ensure_aur
            paru -S --noconfirm google-chrome
            ;;
        debian)
            wget -qO /tmp/chrome.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
            sudo apt-get install -y /tmp/chrome.deb
            rm /tmp/chrome.deb
            ;;
        fedora)
            wget -qO /tmp/chrome.rpm https://dl.google.com/linux/direct/google-chrome-stable_current_x86_64.rpm
            sudo dnf install -y /tmp/chrome.rpm
            rm /tmp/chrome.rpm
            ;;
        macos)
            brew install --cask google-chrome
            ;;
    esac
    log "Google Chrome instalado"
}

# ============================================================
#  STEAM
# ============================================================
setup_steam() {
    info "--- Instalando Steam ---"
    if command -v steam &>/dev/null; then
        log "Steam ya está instalado"
        return
    fi
    case "$OS" in
        arch)
            install_pkgs steam
            # Habilitar multilib si no está
            if ! grep -q "\[multilib\]" /etc/pacman.conf; then
                warn "Habilitando repositorio multilib..."
                sudo sed -i '/\[multilib\]/{n;s/^#//}' /etc/pacman.conf
                sudo pacman -Sy
            fi
            install_pkgs steam
            ;;
        debian)
            sudo dpkg --add-architecture i386
            sudo apt-get update
            install_pkgs steam-installer
            ;;
        fedora)
            sudo dnf install -y fedora-workstation-repositories
            sudo dnf config-manager --set-enabled rpmfusion-nonfree-steam
            install_pkgs steam
            ;;
        macos)
            brew install --cask steam
            ;;
    esac
    log "Steam instalado"
}

# ============================================================
#  EPIC GAMES (Heroic Games Launcher)
# ============================================================
setup_epic() {
    info "--- Instalando Heroic Games Launcher (Epic Games) ---"
    if command -v heroic &>/dev/null; then
        log "Heroic Games Launcher ya está instalado"
        return
    fi
    case "$OS" in
        arch)
            ensure_aur
            paru -S --noconfirm heroic-games-launcher-bin
            ;;
        debian)
            wget -qO- https://github.com/Heroic-Games-Launcher/HeroicGamesLauncher/releases/latest/download/heroic_2.15.2_amd64.deb \
                -O /tmp/heroic.deb 2>/dev/null || true
            # Si falla la URL exacta, usar flatpak como fallback
            if [ ! -f /tmp/heroic.deb ]; then
                warn "Usando Flatpak para Heroic..."
                install_pkgs flatpak
                flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
                flatpak install -y flathub com.heroicgameslauncher.hgl
            else
                sudo apt-get install -y /tmp/heroic.deb
                rm /tmp/heroic.deb
            fi
            ;;
        fedora)
            if ! command -v flatpak &>/dev/null; then
                install_pkgs flatpak
                flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
            fi
            flatpak install -y flathub com.heroicgameslauncher.hgl
            ;;
        macos)
            brew install --cask heroic
            ;;
    esac
    log "Heroic Games Launcher instalado"
}

# ============================================================
#  MAIN
# ============================================================
main() {
    detect_os
    check_sudo

    if [ "$OS" = "macos" ]; then
        warn "macOS no soporta juegos nativos (Steam/Epic tienen soporte limitado)."
        warn "Instalando Chrome y lo posible..."
    fi

    setup_drivers
    setup_chrome
    setup_steam
    setup_epic

    printf "\n${GREEN}========================================${NC}\n"
    printf "${GREEN}  TODO LISTO!${NC}\n"
    printf "${GREEN}========================================${NC}\n"
    info "Cierra sesión y vuelve a entrar (o reinicia) para aplicar drivers."
    info "Si instalaste Flatpak, reinicia sesión para que aparezcan los iconos."
}

main "$@"

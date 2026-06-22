#!/usr/bin/env bash
#===============================================================================
# Post-install Setup для Void Linux + Niri
# Запускается после первой загрузки в установленную систему
#===============================================================================
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${GREEN}[✓]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
error() { echo -e "${RED}[✗]${NC} $*"; }

# Авто-определение пути к репозиторию (Void-Niri или void-niri)
if [ -d "${HOME}/Void-Niri" ]; then
    CONFIG_REPO="${HOME}/Void-Niri"
elif [ -d "${HOME}/void-niri" ]; then
    CONFIG_REPO="${HOME}/void-niri"
else
    CONFIG_REPO="${HOME}/void-niri"
fi
VOID_INSTALLER="${CONFIG_REPO}"

#===============================================================================
# 1. XDG User Dirs
#===============================================================================
#===============================================================================
# 0. Установка пакетов из .list файлов (на случай если install.sh не сработал)
#===============================================================================
install_packages() {
    info "Установка пакетов..."

    # Снимаем ВСЕ локи если остались с прошлого запуска
    sudo rm -f /var/db/xbps/.xbps-pkgdb-0.plist.lock \
        /var/db/xbps/.lock \
        /var/cache/xbps/.xbps-pkgdb-0.plist.lock \
        /var/cache/xbps/.lock 2>/dev/null || true
    # Убиваем зависшие xbps процессы
    sudo pkill -9 xbps-install 2>/dev/null || true

    sudo xbps-install -S 2>/dev/null || true

    local pkgdir="${VOID_INSTALLER}/packages"
    [ -d "$pkgdir" ] || {
        warn "Папка packages не найдена, пропускаем."
        return
    }

    # Список .list файлов с приоритетом
    local lists=(
        "$pkgdir/base.list"
        "$pkgdir/desktop.list"
        "$pkgdir/gpu-amd.list"
        "$pkgdir/gpu-nvidia.list"
        "$pkgdir/gpu-intel.list"
        "$pkgdir/gpu-vm.list"
    )

    for listfile in "${lists[@]}"; do
        [ -f "$listfile" ] || continue
        local pkgs=""
        while IFS= read -r line; do
            [[ "$line" =~ ^[[:space:]]*# ]] && continue
            [[ "$line" =~ ^[[:space:]]*$ ]] && continue
            # Пропускаем пакеты с пометкой NOT IN VOID REPOS
            echo "$line" | grep -iq "NOT IN" && continue
            pkgs="$pkgs $line"
        done <"$listfile"
        [ -z "$pkgs" ] && continue
        local title
        title=$(basename "$listfile")
        info "Установка из $title..."
        sudo xbps-install -y $pkgs 2>&1 || warn "Часть пакетов из $title не установилась"
    done
    info "Пакеты установлены."
}

setup_xdg_dirs() {
    info "Создание XDG директорий..."
    xdg-user-dirs-update 2>/dev/null || true
    mkdir -p ~/Pictures/Screenshots
    mkdir -p ~/Workspace
}

#===============================================================================
# 2. Oh-My-Zsh
#===============================================================================
setup_ohmyzsh() {
    if [ -d "$HOME/.oh-my-zsh" ]; then
        info "Oh-My-Zsh уже установлен."
        return
    fi
    info "Установка Oh-My-Zsh..."
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended || true
}

#===============================================================================
# 3. Flatpak + Flathub
#===============================================================================
setup_flatpak() {
    if ! command -v flatpak &>/dev/null; then
        warn "Flatpak не установлен, пропускаем."
        return
    fi
    info "Настройка Flatpak + Flathub..."
    flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
}

#===============================================================================
# 4. GTK / Qt Themes
#===============================================================================
setup_themes() {
    info "Настройка тем..."

    # GTK
    mkdir -p ~/.config/gtk-3.0 ~/.config/gtk-4.0
    if [ -f "${VOID_INSTALLER}/configs/gtk/gtk-3.0/settings.ini" ]; then
        cp "${VOID_INSTALLER}/configs/gtk/gtk-3.0/settings.ini" ~/.config/gtk-3.0/settings.ini
    fi
    if [ -f "${VOID_INSTALLER}/configs/gtk/gtk-4.0/settings.ini" ]; then
        cp "${VOID_INSTALLER}/configs/gtk/gtk-4.0/settings.ini" ~/.config/gtk-4.0/settings.ini
    fi

    # Flatpak GTK themes override
    mkdir -p ~/.local/share/themes ~/.local/share/icons
    sudo flatpak override --filesystem=xdg-data/themes:ro 2>/dev/null || true
    sudo flatpak override --filesystem=xdg-data/icons:ro 2>/dev/null || true

    info "Не забудь установить Catppuccin тему:"
    info "  https://github.com/catppuccin/gtk"
    info "  Или через flatpak: flatpak install org.gtk.Gtk3theme.Catppuccin-Mocha-Standard-Mauve-Dark"
}

#===============================================================================
# 5. Niri окружение
#===============================================================================
setup_niri() {
    info "Настройка Niri..."
    mkdir -p ~/.config/niri
    if [ -f "${VOID_INSTALLER}/configs/niri/config.kdl" ]; then
        cp "${VOID_INSTALLER}/configs/niri/config.kdl" ~/.config/niri/config.kdl
    fi

    # Создаём niri-session.desktop для greetd/автозапуска
    sudo mkdir -p /usr/share/wayland-sessions
    sudo tee /usr/share/wayland-sessions/niri.desktop >/dev/null <<'EOF'
[Desktop Entry]
Name=Niri
Comment=Niri compositor
Exec=niri-session
Type=Application
EOF
}

#===============================================================================
# 6. Копирование всех конфигов
#===============================================================================
copy_configs() {
    info "Копирование конфигов..."

    # rofi
    mkdir -p ~/.config/rofi
    [ -d "${VOID_INSTALLER}/configs/rofi" ] && cp -r "${VOID_INSTALLER}/configs/rofi/"* ~/.config/rofi/

    # wezterm
    mkdir -p ~/.config/wezterm
    [ -f "${VOID_INSTALLER}/configs/wezterm/wezterm.lua" ] && cp "${VOID_INSTALLER}/configs/wezterm/wezterm.lua" ~/.config/wezterm/

    # walker
    mkdir -p ~/.config/walker
    [ -d "${VOID_INSTALLER}/configs/walker" ] && cp -r "${VOID_INSTALLER}/configs/walker/"* ~/.config/walker/

    # yazi
    mkdir -p ~/.config/yazi
    [ -d "${VOID_INSTALLER}/configs/yazi" ] && cp -r "${VOID_INSTALLER}/configs/yazi/"* ~/.config/yazi/

    # fastfetch
    mkdir -p ~/.config/fastfetch
    [ -f "${VOID_INSTALLER}/configs/fastfetch/config.jsonc" ] && cp "${VOID_INSTALLER}/configs/fastfetch/config.jsonc" ~/.config/fastfetch/

    # btop
    mkdir -p ~/.config/btop
    [ -f "${VOID_INSTALLER}/configs/btop/btop.conf" ] && cp "${VOID_INSTALLER}/configs/btop/btop.conf" ~/.config/btop/

    # cava
    mkdir -p ~/.config/cava
    [ -f "${VOID_INSTALLER}/configs/cava/config" ] && cp "${VOID_INSTALLER}/configs/cava/config" ~/.config/cava/

    # zed
    mkdir -p ~/.config/zed
    [ -f "${VOID_INSTALLER}/configs/zed/settings.json" ] && cp "${VOID_INSTALLER}/configs/zed/settings.json" ~/.config/zed/

    # noctalia
    mkdir -p ~/.config/noctalia
    [ -f "${VOID_INSTALLER}/configs/noctalia/settings.json" ] && cp "${VOID_INSTALLER}/configs/noctalia/settings.json" ~/.config/noctalia/

    # zsh
    [ -f "${VOID_INSTALLER}/configs/zsh/.zshrc" ] && cp "${VOID_INSTALLER}/configs/zsh/.zshrc" ~/.zshrc

    # avatar
    if [ -f "${VOID_INSTALLER}/assets/profile.png" ]; then
        cp "${VOID_INSTALLER}/assets/profile.png" ~/.face
    fi

    info "Конфиги скопированы."
}

#===============================================================================
# 7. Настройка greetd (для авто-входа в niri)
#===============================================================================
setup_greetd() {
    if ! command -v greetd &>/dev/null; then
        warn "greetd не установлен, пропускаем."
        return
    fi
    info "Настройка greetd..."

    sudo tee /etc/greetd/config.toml >/dev/null <<EOF
[terminal]
vt = 1

[default_session]
command = "tuigreet --time --remember --cmd niri-session"
user = "greeter"

[initial_session]
command = "niri-session"
user = "${USER}"
EOF

    sudo ln -sf /etc/sv/greetd /var/service/ 2>/dev/null || true
    info "greetd настроен. Авто-вход: пользователь ${USER} в niri."
}

#===============================================================================
#===============================================================================
# 8. Патчи Noctalia (убираем блюр на панели)
#===============================================================================
patch_noctalia() {
    local patcher="${VOID_INSTALLER}/patches/patch-noctalia.sh"
    if [ -f "$patcher" ]; then
        info "Применяем патчи Noctalia (убираем блюр панели)..."
        bash "$patcher" 2>&1 || warn "Патчи Noctalia пропущены (не критично)"
    fi
}

#===============================================================================
# 9. Системные конфиги (TLP, GameMode, NBFC, Udev, XDG)
#===============================================================================
setup_system_configs() {
    info "Копирование системных конфигов..."

    [ -f "${VOID_INSTALLER}/configs/system/tlp.conf" ] && sudo cp "${VOID_INSTALLER}/configs/system/tlp.conf" /etc/tlp.conf && info "  tlp.conf"
    [ -f "${VOID_INSTALLER}/configs/system/gamemode.ini" ] && sudo cp "${VOID_INSTALLER}/configs/system/gamemode.ini" /etc/gamemode.ini && info "  gamemode.ini"
    [ -f "${VOID_INSTALLER}/configs/system/nbfc.json" ] && sudo mkdir -p /etc/nbfc && sudo cp "${VOID_INSTALLER}/configs/system/nbfc.json" /etc/nbfc/nbfc.json && info "  nbfc.json"
    [ -f "${VOID_INSTALLER}/configs/system/60-scheduler.rules" ] && sudo mkdir -p /etc/udev/rules.d && sudo cp "${VOID_INSTALLER}/configs/system/60-scheduler.rules" /etc/udev/rules.d/60-scheduler.rules && sudo udevadm control --reload && info "  udev rules"
    [ -f "${VOID_INSTALLER}/configs/system/mimeapps.list" ] && cp "${VOID_INSTALLER}/configs/system/mimeapps.list" ~/.config/mimeapps.list && info "  mimeapps.list"
}

#===============================================================================
# 10. Автозапуск niri при логине в tty1
#===============================================================================
setup_autolaunch() {
    info "Настройка автозапуска niri..."

    if command -v greetd &>/dev/null; then
        info "greetd уже настроен — авто-запуск через него."
        return
    fi

    # Через .zprofile — запуск niri при логине на tty1
    if [ -f ~/.zprofile ]; then
        grep -q "niri-session" ~/.zprofile 2>/dev/null && return
    fi

    cat >>~/.zprofile <<'ZPROFILE'
# Автозапуск niri при логине на tty1
if [ "$(tty)" = "/dev/tty1" ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then
    exec dbus-run-session niri-session
fi
ZPROFILE
    info "Добавлен автозапуск niri в ~/.zprofile (tty1)"
}

#===============================================================================
# Главная функция
#===============================================================================
main() {
    echo
    echo -e "${BLUE}============================================================${NC}"
    echo -e "${BLUE}  Void Linux + Niri — Post-Install Setup${NC}"
    echo -e "${BLUE}============================================================${NC}"
    echo

    if [ ! -d "$CONFIG_REPO" ]; then
        error "Репозиторий конфигов не найден: $CONFIG_REPO"
        exit 1
    fi

    setup_xdg_dirs
    install_packages
    setup_ohmyzsh
    setup_flatpak
    copy_configs
    setup_niri
    setup_themes
    setup_greetd
    patch_noctalia
    setup_system_configs
    setup_autolaunch

    echo
    info "==========================================="
    info "  Пост-установка завершена!"
    info "==========================================="
    echo

    # Авто-запуск niri если пакет установлен и мы на tty
    if command -v niri &>/dev/null; then
        info "Niri установлен. Запускаю..."
        echo
        echo -e "${YELLOW}  Входи в систему как ${USER} на tty1 (Ctrl+Alt+F1)${NC}"
        echo -e "${YELLOW}  Niri запустится автоматически!${NC}"
        echo

        # Если скрипт запущен из tty — предлагаем запустить прямо сейчас
        local current_tty
        current_tty=$(tty 2>/dev/null || echo "")
        if [ "$current_tty" = "/dev/tty1" ]; then
            echo -e "${GREEN}  Запускаю niri-session...${NC}"
            sleep 2
            exec dbus-run-session niri-session
        fi
    else
        warn "Niri не установлен. Запусти скрипт ещё раз после: sudo xbps-install niri"
    fi
}

main "$@"

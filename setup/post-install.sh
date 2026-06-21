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

info()  { echo -e "${GREEN}[✓]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
error() { echo -e "${RED}[✗]${NC} $*"; }

CONFIG_REPO="${HOME}/void-niri"
VOID_INSTALLER="${CONFIG_REPO}"

#===============================================================================
# 1. XDG User Dirs
#===============================================================================
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
    sudo tee /usr/share/wayland-sessions/niri.desktop > /dev/null << 'EOF'
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

    sudo tee /etc/greetd/config.toml > /dev/null << EOF
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
        bash "$patcher" || warn "Патчи Noctalia не удалось применить (возможно, она ещё не установлена)"
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
    [ -f "${VOID_INSTALLER}/configs/system/60-scheduler.rules" ] && sudo cp "${VOID_INSTALLER}/configs/system/60-scheduler.rules" /etc/udev/rules.d/60-scheduler.rules && sudo udevadm control --reload && info "  udev rules"
    [ -f "${VOID_INSTALLER}/configs/system/mimeapps.list" ] && cp "${VOID_INSTALLER}/configs/system/mimeapps.list" ~/.config/mimeapps.list && info "  mimeapps.list"
}

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
    setup_ohmyzsh
    setup_flatpak
    copy_configs
    setup_niri
    setup_themes
    setup_greetd
    patch_noctalia
    setup_system_configs

    echo
    info "==========================================="
    info "  Пост-установка завершена!"
    info "==========================================="
    echo
    info "Далее:"
    info "  1. Перезайди в систему или перезагрузись: reboot"
    info "  2. Niri запустится автоматически через greetd"
    info "  3. Если нет greetd — запусти niri-session вручную"
    info "  4. Установи Catppuccin тему для GTK/Qt"
    info "  5. Настрой ZSH: chsh -s /bin/zsh"
    echo
}

main "$@"

#!/usr/bin/env bash
#===============================================================================
# Void-Niri — Noctalia Shell Patcher
# Применяет патчи из NixOS-Niri для:
#   - убирания блюра на панели (bar blur removal)
#   - убирания highlight-эффектов в лаунчере
#   - единой системы теней (unified shadow system)
#===============================================================================
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'
info() { echo -e "${GREEN}[+]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
error() { echo -e "${RED}[✗]${NC} $*"; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PATCH_DIR="$SCRIPT_DIR/noctalia"

#===============================================================================
# Поиск установленной noctalia-shell
#===============================================================================
find_noctalia() {
    local candidates=(
        "/usr/lib/noctalia-shell"
        "/usr/share/noctalia-shell"
        "/opt/noctalia-shell"
        "$HOME/.local/share/noctalia-shell"
        "$HOME/.local/lib/noctalia-shell"
    )

    for dir in "${candidates[@]}"; do
        if [ -f "$dir/Modules/Bar/Bar.qml" ]; then
            echo "$dir"
            return
        fi
    done

    # Noctalia не установлена — просто пропускаем патчи
    warn "Noctalia-shell не установлена. Пропускаем патчи."
    warn "Для установки: sudo xbps-install noctalia"
    return 1
}

#===============================================================================
# Применение патчей
#===============================================================================
apply_patches() {
    local target="$1"

    info "Цель: $target"

    # 1. substituteInPlace: убираем hover highlight в LauncherCore
    local launcher="$target/Modules/Panels/Launcher/LauncherCore.qml"
    if [ -f "$launcher" ]; then
        info "Патч LauncherCore.qml (убираем hover blur)..."

        # Создаём бэкап
        cp "$launcher" "$launcher.bak"

        # Убираем условную смену цвета при hover (оставляем статичный цвет)
        sed -i \
            -e "s/color: entry.isSelected ? Color.mOnHover : Color.mOnSurfaceVariant/color: Color.mOnSurfaceVariant/g" \
            -e "s/color: entry.isSelected ? Color.mOnHover : Color.mOnSurface/color: Color.mOnSurface/g" \
            -e "s/color: gridEntryContainer.isSelected ? Color.mOnHover : Color.mOnSurface/color: Color.mOnSurface/g" \
            -e "s/color: (entry.isSelected && !Settings.data.appLauncher.showIconBackground) ? Color.mOnHover : Color.mOnSurface/color: Color.mOnSurface/g" \
            -e "s/color: (gridEntryContainer.isSelected && !Settings.data.appLauncher.showIconBackground) ? Color.mOnHover : Color.mOnSurface/color: Color.mOnSurface/g" \
            "$launcher"

        # Поверх заменяем полным патченным QML
        if [ -f "$PATCH_DIR/LauncherCore.qml" ]; then
            cp "$PATCH_DIR/LauncherCore.qml" "$launcher"
            info "  LauncherCore.qml ✓"
        fi
    else
        warn "LauncherCore.qml не найден: $launcher"
    fi

    # 2. AllBackgrounds.qml
    if [ -f "$PATCH_DIR/AllBackgrounds.qml" ]; then
        local dest="$target/Modules/MainScreen/Backgrounds/AllBackgrounds.qml"
        if [ -f "$dest" ]; then
            cp "$dest" "$dest.bak"
        fi
        mkdir -p "$(dirname "$dest")"
        cp "$PATCH_DIR/AllBackgrounds.qml" "$dest"
        info "  AllBackgrounds.qml ✓"
    fi

    # 3. MainScreen.qml
    if [ -f "$PATCH_DIR/MainScreen.qml" ]; then
        local dest="$target/Modules/MainScreen/MainScreen.qml"
        if [ -f "$dest" ]; then cp "$dest" "$dest.bak"; fi
        cp "$PATCH_DIR/MainScreen.qml" "$dest"
        info "  MainScreen.qml ✓"
    fi

    # 4. BarContentWindow.qml
    if [ -f "$PATCH_DIR/BarContentWindow.qml" ]; then
        local dest="$target/Modules/MainScreen/BarContentWindow.qml"
        if [ -f "$dest" ]; then cp "$dest" "$dest.bak"; fi
        cp "$PATCH_DIR/BarContentWindow.qml" "$dest"
        info "  BarContentWindow.qml ✓"
    fi

    # 5. Bar.qml
    if [ -f "$PATCH_DIR/Bar.qml" ]; then
        local dest="$target/Modules/Bar/Bar.qml"
        if [ -f "$dest" ]; then cp "$dest" "$dest.bak"; fi
        cp "$PATCH_DIR/Bar.qml" "$dest"
        info "  Bar.qml ✓"
    fi

    # 6. Копируем локальные плагины если есть
    local local_plugins="$SCRIPT_DIR/../configs/noctalia"
    if [ -d "$local_plugins" ]; then
        info "Копирование локальных плагинов..."
        mkdir -p "$target/Plugins"
        cp -r "$local_plugins/"* "$target/Plugins/" 2>/dev/null || true
    fi
}

#===============================================================================
# MAIN
#===============================================================================
main() {
    echo
    echo -e "${GREEN}=== Noctalia Shell Patcher ===${NC}"
    echo

    if [ ! -d "$PATCH_DIR" ]; then
        error "Директория с патчами не найдена: $PATCH_DIR"
        exit 1
    fi

    local noctalia_dir
    noctalia_dir=$(find_noctalia)

    apply_patches "$noctalia_dir"

    echo
    info "Патчи применены."
    info ""
    info "Чтобы изменения вступили в силу:"
    info "  1. Перезапусти noctalia-shell"
    info "  2. Или перезайди в сессию (logout/login)"
    info ""
    info "Бэкапы оригинальных файлов лежат рядом с *.bak"
    echo
}

main "$@"

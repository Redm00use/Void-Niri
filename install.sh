#!/usr/bin/env bash
#===============================================================================
# Void-Niri Installer
# Полная копия NixOS-Niri, портированная на Void Linux (glibc)
#
# Использование:
#   Загрузись в Void Linux Live ISO (glibc!)
#   Подключи интернет
#   Клонируй репозиторий: git clone <repo> /tmp/void-niri
#   Запусти:    cd /tmp/void-niri && sudo bash install.sh --mode live
#===============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/configs"
PACKAGES_DIR="$SCRIPT_DIR/packages"
SETUP_DIR="$SCRIPT_DIR/setup"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

info()  { echo -e "${GREEN}[+]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
error() { echo -e "${RED}[✗]${NC} $*"; }

print_header() {
    echo; echo -e "${BLUE}===${NC} $* ${BLUE}===${NC}"; echo
}

prompt()       { read -r -p "$1 [$2]: "; echo "${REPLY:-$2}"; }
prompt_int()   { read -r -p "$1 [$2]: "; echo "${REPLY:-$2}"; }
prompt_yn()    { read -r -p "$1 [y/N]: "; [[ "${REPLY:-n}" =~ ^[yYдД] ]]; }
prompt_erase() {
    echo -e "${RED}ВНИМАНИЕ: диск $1 будет ПОЛНОСТЬЮ СТЁРТ!${NC}"
    read -r -p "Напиши ERASE для подтверждения: "
    [[ "$REPLY" == "ERASE" ]] || { error "Отмена."; exit 1; }
}

#===============================================================================
# Live-окружение: проверка и установка инструментов
#===============================================================================
require_root() {
    [ "$(id -u)" -eq 0 ] || { error "Запусти от root: sudo bash install.sh --mode live"; exit 1; }
}

prepare_live() {
    print_header "Подготовка Void Linux Live-окружения"

    if ! command -v xbps-install &>/dev/null; then
        error "Run from Void Linux Live ISO (glibc!)"
        error "Download: https://voidlinux.org/download/"
        exit 1
    fi

    local missing=""
    for cmd in parted mkfs.fat mkfs.btrfs mkfs.ext4 mkswap cryptsetup rsync blkid lsblk; do
        command -v "$cmd" &>/dev/null || missing="$missing $cmd"
    done

    if [ -n "$missing" ]; then
        warn "Installing missing tools:$missing"
        xbps-install -Sy parted btrfs-progs cryptsetup rsync util-linux e2fsprogs dosfstools
    fi

    # Fix Cyrillic console font (Void live ISO lacks Cyrillic glyphs by default)
    # Strategy: try built-in kbd fonts first, then terminus-font
    local font_set=false

    # Try built-in kbd fonts first (kbd is always present on Void)
    for f in \
        /usr/share/kbd/consolefonts/UniCyr_8x16.psf.gz \
        /usr/share/kbd/consolefonts/cyr-sun16.psf.gz \
        /usr/share/kbd/consolefonts/Cyr_a8x16.psf.gz; do
        if [ -f "$f" ]; then
            setfont "$f" 2>/dev/null && { font_set=true; break; }
        fi
    done

    # If no built-in Cyrillic font found, try installing terminus-font
    if ! $font_set && (xbps-query terminus-font &>/dev/null || xbps-install -Sy terminus-font 2>/dev/null); then
        for f in \
            /usr/share/kbd/consolefonts/ter-cyr16b.psf.gz \
            /usr/share/kbd/consolefonts/ter-cyr14b.psf.gz; do
            if [ -f "$f" ]; then
                setfont "$f" 2>/dev/null && { font_set=true; break; }
            fi
        done
    fi

    if $font_set; then
        info "Ready. Console font set for Cyrillic support."
    else
        warn "Could not set Cyrillic console font - Russian text may display as squares."
    fi
}

#===============================================================================
# Меню
#===============================================================================
choose_gpu() {
    echo "  1) AMD    2) NVIDIA    3) Intel    4) VM"
    read -r -p "Видеокарта [1]: "
    case "${REPLY:-1}" in 1|amd) echo "amd";; 2|nvidia) echo "nvidia";; 3|intel) echo "intel";; 4|vm) echo "vm";; *) echo "amd";; esac
}
choose_role()    { read -r -p "Роль (desktop/server) [desktop]: "; echo "${REPLY:-desktop}"; }
choose_fs()      { read -r -p "ФС root (btrfs/ext4) [btrfs]: "; echo "${REPLY:-btrfs}"; }
choose_tz()      { read -r -p "Часовой пояс [Europe/Kyiv]: "; echo "${REPLY:-Europe/Kyiv}"; }
choose_locale()  { read -r -p "Локаль [ru_RU.UTF-8]: "; echo "${REPLY:-ru_RU.UTF-8}"; }

select_disk() {
    # All UI output goes to stderr so stdout only contains the chosen disk path
    {
        echo
        echo "Available disks:"
        echo "----------------------------------------"
        lsblk -d -e 7,11 -o NAME,SIZE,TYPE,MODEL 2>/dev/null | grep -E 'disk' || lsblk -d -e 7 -o NAME,SIZE,TYPE,MODEL 2>/dev/null
        echo "----------------------------------------"
    } >&2

    local candidates
    candidates=$(lsblk -d -n -e 7,11 -o NAME,TYPE,SIZE 2>/dev/null \
        | awk '$2=="disk" {print $1}' | tr '\n' ' ' | sed 's/ *$//')

    local count
    count=$(echo "$candidates" | wc -w)
    if [ "$count" -eq 1 ]; then
        local dev="/dev/$candidates"
        info "Auto-selected disk: $dev" >&2
        echo "$dev"
        return
    fi

    {
        echo
        echo "Detected disks: $candidates"
        echo "(Examples: sda, nvme0n1, vda — the NAME column above)"
    } >&2

    while :; do
        read -r -p "Disk (e.g. vda, sda, nvme0n1): "
        [ -b "/dev/$REPLY" ] && { echo "/dev/$REPLY"; return; }
        error "Not found: /dev/$REPLY" >&2
    done
}

#===============================================================================
# Разметка GPT + EFI + root (± swap, ± home, ± LUKS)
#===============================================================================
partition_and_mount() {
    local disk="$1" fs="$2" separate_home="$3" home_gib="$4" swap_gib="$5" luks="$6"

    # Suffix for partition numbers: nvme0n1p1, mmcblk0p1 vs sda1, vda1
    local pfx=""
    [[ "$disk" =~ (nvme|mmcblk) ]] && pfx="p"

    local efi="${disk}${pfx}1"
    local n=2 sw="" hm="" root=""

    [ "$swap_gib" -gt 0 ] && sw="${disk}${pfx}${n}" && n=$((n+1))
    [ "$separate_home" = true ] && hm="${disk}${pfx}${n}" && n=$((n+1))
    root="${disk}${pfx}${n}"

    # Wait for device node (udev may be slow in live ISO)
    if [ ! -b "$disk" ]; then
        warn "Waiting for $disk device node..."
        for _ in $(seq 1 20); do
            [ -b "$disk" ] && break
            sleep 0.5
        done
        if [ ! -b "$disk" ]; then
            # Fallback: try mknod if major:minor available from sysfs
            local devname maj min
            devname=$(basename "$disk")
            if [ -f "/sys/block/$devname/dev" ]; then
                maj=$(awk '{print $1}' "/sys/block/$devname/dev" 2>/dev/null)
                min=$(awk '{print $2}' "/sys/block/$devname/dev" 2>/dev/null)
                [ -n "$maj" ] && [ -n "$min" ] && mknod "$disk" b "$maj" "$min" 2>/dev/null || true
            fi
        fi
    fi

    if [ ! -b "$disk" ]; then
        error "Device $disk not available (len=${#disk}). Check: ls -la /dev/vd* /sys/block/"
        printf 'disk=[%s]\n' "$disk" >&2
        ls -la /dev/vd* 2>/dev/null || true
        ls /sys/block/ 2>/dev/null || true
        exit 1
    fi

    info "Разметка GPT на $disk..."

    local disk_base
    disk_base=$(basename "$disk")

    # Kill any stale devices from prior failed attempts
    # 1) Unmount every mounted partition on this disk
    for part in /dev/${disk_base}[0-9]*; do
        [ -b "$part" ] || continue
        local mp
        mp=$(lsblk -n -o MOUNTPOINT "$part" 2>/dev/null || true)
        [ -n "$mp" ] && { umount "$mp" 2>/dev/null || true; }
    done

    # 2) Deactivate any swap
    for sw in /dev/${disk_base}[0-9]*; do
        [ -b "$sw" ] && swapoff "$sw" 2>/dev/null || true
    done

    # 3) Close any btrfs/mdadm/LUKS on this disk
    btrfs device scan 2>/dev/null || true

    # 4) Delete kernel partition entries (critical — kernel holds stale GPT)
    warn "Removing kernel partition entries..."
    partx -d --nr 1-64 "$disk" 2>/dev/null || true

    # 5) Wipe partition table and all signatures
    warn "Wiping partition table..."
    dd if=/dev/zero of="$disk" bs=1M count=10 2>/dev/null || true
    sync

    # 6) Force kernel to reread empty table
    blockdev --rereadpt "$disk" 2>/dev/null || udevadm settle 2>/dev/null || true

    parted -s "$disk" mklabel gpt
    parted -s "$disk" mkpart ESP fat32 1MiB 513MiB
    parted -s "$disk" set 1 esp on

    local cur=513
    if [ -n "$sw" ]; then
        parted -s "$disk" mkpart primary linux-swap "${cur}MiB" "$((cur+swap_gib*1024))MiB"
        cur=$((cur+swap_gib*1024))
    fi
    if [ -n "$hm" ]; then
        parted -s "$disk" mkpart primary "$fs" "${cur}MiB" "$((cur+home_gib*1024))MiB"
        cur=$((cur+home_gib*1024))
    fi
    local root_fs="$fs"
    [ "$luks" = true ] && root_fs="ext4"
    parted -s "$disk" mkpart primary "$root_fs" "${cur}MiB" 100%

    # Форматирование
    info "mkfs.fat $efi..."
    mkfs.fat -F32 "$efi"
    [ -n "$sw" ] && { mkswap "$sw"; swapon "$sw"; }
    [ -n "$hm" ] && { [ "$fs" = btrfs ] && mkfs.btrfs -f "$hm" || mkfs.ext4 -F "$hm"; }

    local rootdev="$root"
    if [ "$luks" = true ]; then
        local pass
        read -r -s -p "LUKS пароль: " pass; echo
        echo -n "$pass" | cryptsetup luksFormat --batch-mode "$root" -
        echo -n "$pass" | cryptsetup open "$root" cryptroot -
        rootdev="/dev/mapper/cryptroot"
    fi

    if [ "$fs" = btrfs ]; then
        mkfs.btrfs -f "$rootdev"
        mount "$rootdev" /mnt
        btrfs sub create /mnt/@
        [ -z "$hm" ] && btrfs sub create /mnt/@home
        umount /mnt
        mount -o subvol=@,compress=zstd,noatime "$rootdev" /mnt
    else
        mkfs.ext4 -F "$rootdev"
        mount "$rootdev" /mnt
    fi

    mkdir -p /mnt/boot && mount "$efi" /mnt/boot
    if [ -n "$hm" ]; then
        mkdir -p /mnt/home && mount "$hm" /mnt/home
    elif [ "$fs" = btrfs ]; then
        mkdir -p /mnt/home && mount -o subvol=@home,compress=zstd,noatime "$rootdev" /mnt/home
    fi

    info "Диск размечен и примонтирован в /mnt."
}

#===============================================================================
# Установка Void на /mnt
#===============================================================================
install_void_base() {
    print_header "Установка Void Linux (базовая система)"
    local mirror="${1:-https://repo-default.voidlinux.org/current}"

    XBPS_ARCH=x86_64 xbps-install -Sy -r /mnt -R "$mirror" \
        base-system grub-x86_64-efi \
        bash curl wget git \
        NetworkManager bluez \
        pipewire wireplumber alsa-pipewire \
        elogind dbus polkit \
        acpid chrony \
        neovim zsh eza tree fzf ripgrep fd \
        void-repo-nonfree

    info "Базовая система установлена."
}

#===============================================================================
# Настройка внутри chroot
#===============================================================================
run_chroot_setup() {
    local hostname="$1" tz="$2" locale="$3" user="$4" gpu="$5" role="$6" fs="$7"

    mount --rbind /sys /mnt/sys
    mount --rbind /dev /mnt/dev
    mount --rbind /proc /mnt/proc
    mount --rbind /run /mnt/run
    cp /etc/resolv.conf /mnt/etc/resolv.conf

    # Копируем списки пакетов
    cp "$PACKAGES_DIR/base.list" /mnt/tmp/pkgs-base.list
    cp "$PACKAGES_DIR/desktop.list" /mnt/tmp/pkgs-desktop.list 2>/dev/null || true
    [ -f "$PACKAGES_DIR/gpu-${gpu}.list" ] && cp "$PACKAGES_DIR/gpu-${gpu}.list" "/mnt/tmp/pkgs-gpu.list"

    # Копируем runit-сервисы
    cp -r "$SCRIPT_DIR/services" /mnt/tmp/services 2>/dev/null || true

    # chroot-скрипт
    cat > /mnt/tmp/setup.sh << 'INNER'
#!/bin/bash
set -eu
H="$1" TZ="$2" L="$3" U="$4" G="$5" R="$6" FS="$7"

echo "=== Void Linux — chroot setup ==="

echo "$H" > /etc/hostname
cat > /etc/hosts << EOF
127.0.0.1 localhost
::1       localhost
127.0.1.1 ${H}.localdomain $H
EOF

ln -sf "/usr/share/zoneinfo/$TZ" /etc/localtime
echo "$L" >> /etc/default/libc-locales 2>/dev/null || true
xbps-reconfigure -f glibc-locales

# Репозитории
xbps-install -Sy xbps 2>/dev/null || true
xbps-install -Sy void-repo-nonfree void-repo-multilib void-repo-multilib-nonfree 2>/dev/null || true
xbps-install -S 2>/dev/null || true

# Функция установки списка пакетов (пропускает отсутствующие)
install_list() {
    local f="$1" title="$2"
    [ -f "$f" ] || return
    echo "--- $title ---"
    local pkgs=""
    while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [ -z "$line" ] && continue
        pkgs="$pkgs $line"
    done < "$f"
    [ -n "$pkgs" ] && xbps-install -y $pkgs 2>&1 | tail -3 || echo "  (ok)"
}

install_list /tmp/pkgs-base.list "Системные пакеты"
[ "$R" = desktop ] && install_list /tmp/pkgs-desktop.list "Desktop пакеты"
[ "$R" = desktop ] && install_list /tmp/pkgs-gpu.list "GPU драйверы ($G)"

# Пользователь
useradd -m -G wheel,network,audio,video,input,bluetooth,kvm,libvirt,plugdev \
    -s /bin/zsh "$U"
echo "${U}:1408" | chpasswd
echo "root:1408" | chpasswd

# GRUB
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id="Void Linux"
xbps-reconfigure -f linux

# Службы runit
for s in dbus elogind polkitd NetworkManager bluetoothd acpid chronyd cupsd; do
    [ -d "/etc/sv/$s" ] && ln -sf "/etc/sv/$s" /var/service/
done
if [ "$R" = desktop ]; then
    for s in libvirtd virtlockd virtlogd; do
        [ -d "/etc/sv/$s" ] && ln -sf "/etc/sv/$s" /var/service/
    done

    # Дополнительные runit-сервисы
    for svc_dir in /tmp/services/*; do
        [ -d "$svc_dir" ] || continue
        svc_name=$(basename "$svc_dir")
        [ -d "/etc/sv/$svc_name" ] && continue
        cp -r "$svc_dir" "/etc/sv/$svc_name"
        chmod +x "/etc/sv/$svc_name/run"
        ln -sf "/etc/sv/$svc_name" /var/service/
        echo "  runit: $svc_name enabled"
    done
fi

# sudo
echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/wheel

# tmpfs /tmp
echo "tmpfs /tmp tmpfs defaults,noatime,mode=1777 0 0" >> /etc/fstab

# ZRAM (desktop)
if [ "$R" = desktop ]; then
    mkdir -p /etc/sv/zramen
    printf '#!/bin/sh\n[ -x /usr/bin/zramen ] || exit 0\nexec zramen\n' > /etc/sv/zramen/run
    chmod +x /etc/sv/zramen/run
    ln -sf /etc/sv/zramen /var/service/
fi

# Udev
if [ "$R" = desktop ]; then
    cat > /etc/udev/rules.d/60-scheduler.rules << 'UDEV'
ACTION=="add", SUBSYSTEM=="block", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="kyber"
ACTION=="add", SUBSYSTEM=="leds", KERNEL=="*::scrolllock", RUN+="/bin/sh -c 'chmod 666 /sys/class/leds/%k/brightness /sys/class/leds/%k/trigger'"
UDEV
fi


# Firewall (KDE Connect ports 1714-1764)
if [ -x /usr/bin/iptables ]; then
    iptables -A INPUT -p tcp --dport 1714:1764 -j ACCEPT 2>/dev/null || true
    iptables -A INPUT -p udp --dport 1714:1764 -j ACCEPT 2>/dev/null || true
fi

# DNS nameservers
echo "nameserver 1.1.1.2" > /etc/resolv.conf
echo "nameserver 8.8.8.8" >> /etc/resolv.conf

# Locale extras (из NixOS)
cat >> /etc/locale.conf << LOCEOF
LC_ADDRESS=uk_UA.UTF-8
LC_IDENTIFICATION=uk_UA.UTF-8
LC_MEASUREMENT=uk_UA.UTF-8
LC_MONETARY=uk_UA.UTF-8
LC_NAME=uk_UA.UTF-8
LC_NUMERIC=uk_UA.UTF-8
LC_PAPER=uk_UA.UTF-8
LC_TELEPHONE=uk_UA.UTF-8
LC_TIME=uk_UA.UTF-8
LOCEOF

echo "KEYMAP=ru" > /etc/vconsole.conf
echo "=== chroot setup done ==="
INNER

    chmod +x /mnt/tmp/setup.sh
    chroot /mnt /tmp/setup.sh "$hostname" "$tz" "$locale" "$user" "$gpu" "$role" "$fs"
    rm -rf /mnt/tmp/setup.sh /mnt/tmp/pkgs-*.list /mnt/tmp/services
    info "Система настроена."
}

#===============================================================================
# Конфиги пользователя
#===============================================================================
install_configs() {
    local user="$1" role="$2"
    local home="/mnt/home/$user"

    print_header "Копирование конфигов"

    mkdir -p "$home/.config" "$home/.local/share" \
        "$home/Pictures/Screenshots" "$home/Documents" \
        "$home/Downloads" "$home/Videos" "$home/Music" "$home/Workspace"

    # niri
    mkdir -p "$home/.config/niri"
    [ -f "$CONFIG_DIR/niri/config.kdl" ] && cp "$CONFIG_DIR/niri/config.kdl" "$home/.config/niri/"

    # rofi
    mkdir -p "$home/.config/rofi"
    [ -d "$CONFIG_DIR/rofi" ] && cp -r "$CONFIG_DIR/rofi/"* "$home/.config/rofi/"

    # wezterm
    mkdir -p "$home/.config/wezterm"
    [ -f "$CONFIG_DIR/wezterm/wezterm.lua" ] && cp "$CONFIG_DIR/wezterm/wezterm.lua" "$home/.config/wezterm/"

    # walker
    mkdir -p "$home/.config/walker"
    [ -d "$CONFIG_DIR/walker" ] && cp -r "$CONFIG_DIR/walker/"* "$home/.config/walker/"

    # yazi
    mkdir -p "$home/.config/yazi"
    [ -d "$CONFIG_DIR/yazi" ] && cp -r "$CONFIG_DIR/yazi/"* "$home/.config/yazi/"

    # fastfetch
    mkdir -p "$home/.config/fastfetch"
    [ -f "$CONFIG_DIR/fastfetch/config.jsonc" ] && cp "$CONFIG_DIR/fastfetch/config.jsonc" "$home/.config/fastfetch/"

    # btop
    mkdir -p "$home/.config/btop"
    [ -f "$CONFIG_DIR/btop/btop.conf" ] && cp "$CONFIG_DIR/btop/btop.conf" "$home/.config/btop/"

    # cava
    mkdir -p "$home/.config/cava"
    [ -f "$CONFIG_DIR/cava/config" ] && cp "$CONFIG_DIR/cava/config" "$home/.config/cava/"

    # zed
    mkdir -p "$home/.config/zed"
    [ -f "$CONFIG_DIR/zed/settings.json" ] && cp "$CONFIG_DIR/zed/settings.json" "$home/.config/zed/"

    # zsh
    [ -f "$CONFIG_DIR/zsh/.zshrc" ] && cp "$CONFIG_DIR/zsh/.zshrc" "$home/.zshrc"

    # gtk
    [ -d "$CONFIG_DIR/gtk/gtk-3.0" ] && mkdir -p "$home/.config/gtk-3.0" && cp -r "$CONFIG_DIR/gtk/gtk-3.0/"* "$home/.config/gtk-3.0/"
    [ -d "$CONFIG_DIR/gtk/gtk-4.0" ] && mkdir -p "$home/.config/gtk-4.0" && cp -r "$CONFIG_DIR/gtk/gtk-4.0/"* "$home/.config/gtk-4.0/"

    # noctalia (desktop)
    if [ "$role" = desktop ]; then
        mkdir -p "$home/.config/noctalia"
        [ -f "$CONFIG_DIR/noctalia/settings.json" ] && cp "$CONFIG_DIR/noctalia/settings.json" "$home/.config/noctalia/"
    fi

    # laz ygit
    mkdir -p "$home/.config/lazygit"
    [ -f "$CONFIG_DIR/lazygit/config.yml" ] && cp "$CONFIG_DIR/lazygit/config.yml" "$home/.config/lazygit/"

    # Аватар
    if [ -f "$SCRIPT_DIR/assets/profile.png" ]; then
        cp "$SCRIPT_DIR/assets/profile.png" "$home/.face"
    fi

    # .profile
    cat >> "$home/.profile" << 'EOF'
export XDG_SESSION_TYPE=wayland
export QT_QPA_PLATFORM="wayland;xcb"
export XKB_DEFAULT_OPTIONS="led:scroll"
export TERMINAL="wezterm"
export EDITOR="nvim"
EOF

    # niri desktop entry

    # --- System configs ---
    [ -f "$CONFIG_DIR/system/tlp.conf" ] && cp "$CONFIG_DIR/system/tlp.conf" /mnt/etc/tlp.conf
    [ -f "$CONFIG_DIR/system/gamemode.ini" ] && mkdir -p /mnt/etc && cp "$CONFIG_DIR/system/gamemode.ini" /mnt/etc/gamemode.ini
    [ -f "$CONFIG_DIR/system/nbfc.json" ] && mkdir -p /mnt/etc/nbfc && cp "$CONFIG_DIR/system/nbfc.json" /mnt/etc/nbfc/nbfc.json
    [ -f "$CONFIG_DIR/system/60-scheduler.rules" ] && mkdir -p /mnt/etc/udev/rules.d && cp "$CONFIG_DIR/system/60-scheduler.rules" /mnt/etc/udev/rules.d/60-scheduler.rules
    [ -f "$CONFIG_DIR/system/mimeapps.list" ] && mkdir -p "$home/.config" && cp "$CONFIG_DIR/system/mimeapps.list" "$home/.config/mimeapps.list"

    # --- User scripts ---
    mkdir -p "$home/.local/bin"
    [ -f "$SCRIPT_DIR/scripts/scrolllock_keyboard" ] && cp "$SCRIPT_DIR/scripts/scrolllock_keyboard" "$home/.local/bin/" && chmod +x "$home/.local/bin/scrolllock_keyboard"

    # --- Bluetooth scripts ---
    [ -f "$SCRIPT_DIR/scripts/bluetooth-reconnect" ] && cp "$SCRIPT_DIR/scripts/bluetooth-reconnect" /mnt/usr/local/bin/bluetooth-device-reconnect && chmod +x /mnt/usr/local/bin/bluetooth-device-reconnect
    [ -f "$SCRIPT_DIR/scripts/bluetooth-watch" ] && cp "$SCRIPT_DIR/scripts/bluetooth-watch" /mnt/usr/local/bin/bluetooth-devices-watch && chmod +x /mnt/usr/local/bin/bluetooth-devices-watch
    mkdir -p /mnt/usr/share/wayland-sessions
    cat > /mnt/usr/share/wayland-sessions/niri.desktop << 'EOF'
[Desktop Entry]
Name=Niri
Comment=Niri compositor
Exec=niri-session
Type=Application
EOF

    chown -R 1000:1000 "$home"
    info "Конфиги скопированы."
}

#===============================================================================
# MAIN
#===============================================================================
main() {
    local mode="live"
    local hostname="kotlin" user_name="kotlin" role="desktop" gpu="amd"
    local tz="Europe/Kyiv" locale="ru_RU.UTF-8" fs="btrfs"
    local disk="" separate_home="false" home_gib=0 swap_gib=8
    local luks="false" yes_mode="false" dry_run="false"

    # Аргументы
    while [ $# -gt 0 ]; do
        case "$1" in
            --mode) mode="$2"; shift 2;;
            --host) hostname="$2"; shift 2;;
            --user) user_name="$2"; shift 2;;
            --role) role="$2"; shift 2;;
            --gpu)  gpu="$2"; shift 2;;
            --timezone) tz="$2"; shift 2;;
            --locale) locale="$2"; shift 2;;
            --fs) fs="$2"; shift 2;;
            --disk) disk="$2"; shift 2;;
            --separate-home) separate_home="true"; shift;;
            --home-gib) home_gib="$2"; shift 2;;
            --swap-gib) swap_gib="$2"; shift 2;;
            --luks) luks="true"; shift;;
            --yes) yes_mode="true"; shift;;
            --dry-run) dry_run="true"; shift;;
            *) error "?: $1"; exit 1;;
        esac
    done

    print_header "Void-Niri Installer"

    # --- CONFIG MODE ---
    if [ "$mode" = config ]; then
        hostname=$(prompt       "Имя хоста" "$hostname")
        user_name=$(prompt      "Пользователь" "$user_name")
        role=$(choose_role)
        gpu=$(choose_gpu)
        tz=$(choose_tz)
        locale=$(choose_locale)
        echo
        echo "  Хост:        $hostname"
        echo "  Пользователь: $user_name"
        echo "  Роль:         $role"
        echo "  GPU:          $gpu"
        echo "  Timezone:     $tz"
        echo "  Locale:       $locale"
        $yes_mode || { prompt_yn "Подтвердить?" || exit 0; }
        mkdir -p "$SCRIPT_DIR/generated"
        cat > "$SCRIPT_DIR/generated/$hostname.conf" << EOF
HOSTNAME="$hostname"
USER="$user_name"
ROLE="$role"
GPU="$gpu"
TZ="$tz"
LOCALE="$locale"
EOF
        info "Конфиг сохранён: generated/$hostname.conf"
        info "Установка: sudo bash install.sh --mode live --host $hostname"
        exit 0
    fi

    # --- LIVE MODE ---
    require_root
    prepare_live

    # Интерактивные вопросы
    hostname=$(prompt       "Имя хоста" "$hostname")
    user_name=$(prompt      "Пользователь" "$user_name")
    role=$(choose_role)
    gpu=$(choose_gpu)
    tz=$(choose_tz)
    locale=$(choose_locale)
    fs=$(choose_fs)
    disk="${disk:-$(select_disk)}"
    separate_home=$(prompt_yn "Отдельный /home?" && echo true || echo false)
    [ "$separate_home" = true ] && home_gib=$(prompt_int "Размер /home GiB" 200)
    swap_gib=$(prompt_int "Размер swap GiB (0=без swap)" "$swap_gib")
    luks=$(prompt_yn "Шифровать root (LUKS)?" && echo true || echo false)

    # План
    print_header "План установки"
    echo "  Диск:        $disk"
    echo "  FS root:     $fs"
    echo "  Отд /home:   $separate_home"
    [ "$separate_home" = true ] && echo "  /home GiB:   $home_gib"
    echo "  Swap GiB:    $swap_gib"
    echo "  LUKS:        $luks"
    $yes_mode || prompt_erase "$disk"
    [ "$dry_run" = true ] && { info "Dry-run — выход."; exit 0; }

    # === УСТАНОВКА ===
    # 1. Разметка
    partition_and_mount "$disk" "$fs" "$separate_home" "$home_gib" "$swap_gib" "$luks"

    # 2. Базовая система
    install_void_base

    # 3. Chroot-настройка
    run_chroot_setup "$hostname" "$tz" "$locale" "$user_name" "$gpu" "$role" "$fs"

    # 4. Конфиги
    install_configs "$user_name" "$role"

    # 5. Копирование репозитория
    local repodst="/mnt/home/$user_name/void-niri"
    info "Копирование репозитория в $repodst..."
    mkdir -p "$repodst"
    rsync -a --exclude='.git' --exclude='result' --exclude='.installer-logs' --exclude='generated' \
        "$SCRIPT_DIR/" "$repodst/" 2>/dev/null || \
        cp -r "$SCRIPT_DIR"/* "$repodst/" 2>/dev/null || true
    chown -R 1000:1000 "/mnt/home/$user_name"

    # 6. Размонтирование
    info "Размонтирование..."
    umount -R /mnt 2>/dev/null || true
    [ "$luks" = true ] && cryptsetup close cryptroot 2>/dev/null || true

    # 7. Готово
    echo
    echo -e "${GREEN}=============================================${NC}"
    echo -e "${GREEN}  Void-Niri установлен!${NC}"
    echo -e "${GREEN}=============================================${NC}"
    echo
    echo "  Хост:        $hostname"
    echo "  Пользователь: $user_name"
    echo "  Пароль:      1408"
    echo
    echo "  Перезагрузка: reboot"
    echo "  После входа:  bash ~/void-niri/setup/post-install.sh"
    echo
}

main "$@"

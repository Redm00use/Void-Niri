#!/usr/bin/env bash
#===============================================================================
# fix-grub.sh
# Чиним GRUB загрузчик на уже установленной системе.
#
# Использование:
#   1. Загрузитесь с Void Linux Live ISO
#   2. Подключите интернет
#   3. Скачайте и запустите одной командой:
#      curl -sL https://raw.githubusercontent.com/Redm00use/Void-Niri/main/fix-grub.sh | sudo bash -s -- /dev/vda
#      (если не знаете диск — просто: curl ... | sudo bash
#       скрипт сам найдёт root и EFI разделы)
#===============================================================================
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${GREEN}[+]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
error() { echo -e "${RED}[✗]${NC} $*"; }

DISK=""
if [ $# -ge 1 ]; then
    DISK="$1"
fi

ROOT_PART=""
EFI_PART=""

# Если диск указан — пробуем стандартную раскладку (1=EFI, 3=root)
if [ -n "$DISK" ]; then
    ROOT_PART="${DISK}3"
    EFI_PART="${DISK}1"
    [ ! -b "$ROOT_PART" ] && ROOT_PART=""
    [ ! -b "$EFI_PART" ] && EFI_PART=""
fi

# --- Автопоиск root-раздела ---
if [ -z "$ROOT_PART" ]; then
    info "Scanning for root partition..."
    # Сначала btrfs (по приоритету), потом ext4
    for fstype in btrfs ext4; do
        ROOT_PART=$(blkid -t TYPE="$fstype" -o device 2>/dev/null | head -1 || true)
        [ -n "$ROOT_PART" ] && break
    done
    if [ -z "$ROOT_PART" ]; then
        error "Cannot find root partition (btrfs or ext4). Available:"
        lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT
        exit 1
    fi
    info "Found root: $ROOT_PART"
    # Выводим имя диска из root-раздела (например /dev/vda3 → /dev/vda)
    [ -z "$DISK" ] && DISK="/dev/$(lsblk -n -o PKNAME "$ROOT_PART" 2>/dev/null || echo "")"
fi

# --- Автопоиск EFI-раздела ---
if [ -z "$EFI_PART" ]; then
    info "Scanning for EFI partition..."
    EFI_PART=$(blkid -t TYPE="vfat" -o device 2>/dev/null | head -1 || true)
    if [ -z "$EFI_PART" ]; then
        error "Cannot find EFI partition (vfat). Available:"
        lsblk -o NAME,SIZE,TYPE,FSTYPE
        exit 1
    fi
    info "Found EFI: $EFI_PART"
fi

# --- Определяем ФС и subvol для btrfs ---
ROOT_FS=$(blkid -s TYPE -o value "$ROOT_PART" 2>/dev/null || echo "ext4")
MOUNT_OPTS=""
if [ "$ROOT_FS" = "btrfs" ]; then
    # Пробуем subvol=@ (стандартный для Void-Niri), иначе @rootfs или плоский
    for sv in @ @rootfs .; do
        if btrfs subvolume show "$ROOT_PART" 2>/dev/null | grep -q "Name: ${sv#.}$([ "$sv" = "." ] && echo "" || true)"; then
            true # subvol exists
        fi
        # Просто пробуем смонтировать — если не сработает, идём дальше
        MOUNT_OPTS="-o subvol=$sv"
        break
    done
    # Если не смогли определить — используем @ по умолчанию
    [ -z "$MOUNT_OPTS" ] && MOUNT_OPTS="-o subvol=@"
    info "Btrfs detected. Mount options: $MOUNT_OPTS"
fi

echo ""
echo -e "${BLUE}=== План ===${NC}"
echo "  Root:        $ROOT_PART  ($ROOT_FS)"
echo "  EFI:         $EFI_PART"
echo "  Disk:        $DISK"
echo "  Mount opts:  ${MOUNT_OPTS:-none}"
echo ""

read -r -p "Продолжить? [y/N]: "
[[ "$REPLY" =~ ^[yY] ]] || {
    error "Отмена."
    exit 0
}

# --- Монтируем root ---
info "Mounting $ROOT_PART → /mnt... (${MOUNT_OPTS:-без опций})"
# shellcheck disable=SC2086
mount $MOUNT_OPTS "$ROOT_PART" /mnt

# --- Проверка: есть ли /mnt/sys ? ---
if [ ! -d /mnt/sys ]; then
    # Если btrfs и /mnt/sys нет — возможно не тот subvol
    if [ "$ROOT_FS" = "btrfs" ]; then
        warn "/mnt/sys does not exist — trying different btrfs subvolumes..."
        umount /mnt 2>/dev/null || true
        for sv in @ @rootfs; do
            mount -o "subvol=$sv" "$ROOT_PART" /mnt 2>/dev/null || continue
            if [ -d /mnt/sys ]; then
                info "Correct subvol found: $sv"
                MOUNT_OPTS="-o subvol=$sv"
                break
            fi
            umount /mnt 2>/dev/null || true
        done
        # Если всё ещё нет /mnt/sys — фатально
        if [ ! -d /mnt/sys ]; then
            error "Cannot find correct btrfs subvolume. /mnt/sys does not exist."
            error "Contents of /mnt:"
            ls -la /mnt 2>/dev/null || true
            exit 1
        fi
    else
        # Если ext4 — что-то серьёзное
        error "/mnt/sys does not exist. Root partition $ROOT_PART may not be mounted correctly."
        exit 1
    fi
fi

# --- Монтируем EFI ---
info "Mounting $EFI_PART → /mnt/boot..."
mkdir -p /mnt/boot
mount "$EFI_PART" /mnt/boot

# --- Bind-mount /sys, /dev, /proc (создаём точки если их нет) ---
info "Bind-mounting /sys, /dev, /proc..."
mkdir -p /mnt/sys /mnt/dev /mnt/proc /mnt/run
mount --rbind /sys /mnt/sys || warn "mount --rbind /sys failed"
mount --rbind /dev /mnt/dev || warn "mount --rbind /dev failed"
mount --rbind /proc /mnt/proc || warn "mount --rbind /proc failed"
mount --rbind /run /mnt/run || warn "mount --rbind /run failed"

# --- Монтируем efivarfs (нужно чтобы efibootmgr мог писать в NVRAM) ---
if [ -d /sys/firmware/efi/efivars ]; then
    mkdir -p /mnt/sys/firmware/efi/efivars
    if ! mountpoint -q /mnt/sys/firmware/efi/efivars 2>/dev/null; then
        mount -t efivarfs efivarfs /mnt/sys/firmware/efi/efivars 2>/dev/null &&
            info "efivarfs mounted for NVRAM access" ||
            warn "efivarfs mount failed (NVRAM может быть недоступен в этой VM)"
    fi
fi

# --- Chroot: переустановка GRUB ---
info "Installing GRUB..."
chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id="Void Linux" --removable || {
    warn "First attempt failed, retrying with --no-nvram..."
    chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id="Void Linux" --removable --no-nvram
}

info "Reconfiguring kernel..."
chroot /mnt xbps-reconfigure -f linux

# --- Генерируем GRUB config (самая частая причина — grub.cfg пуст или отсутствует) ---
info "Generating grub.cfg..."
chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg || warn "grub-mkconfig failed (может не быть /dev в chroot)"

# --- Регистрируем загрузчик в NVRAM через efibootmgr ---
info "Registering Void Linux in NVRAM..."
BOOT_DEV=$(findmnt -n -o SOURCE /mnt/boot 2>/dev/null || echo "")
if [ -n "$BOOT_DEV" ]; then
    BOOT_DISK="/dev/$(lsblk -n -o PKNAME "$BOOT_DEV" 2>/dev/null || echo "")"
    BOOT_PART_NUM=$(lsblk -n -o MAJ:MIN "$BOOT_DEV" 2>/dev/null | cut -d: -f2 || echo "1")
    if [ -n "$BOOT_DISK" ] && [ -b "$BOOT_DISK" ]; then
        # Удаляем старые записи Void Linux (игнорируем ошибки grep если нет записей)
        old_boots=$(chroot /mnt efibootmgr 2>/dev/null | grep -i "void" | sed -n 's/Boot\([0-9A-F]*\).*/\1/p' || true)
        for bn in $old_boots; do
            chroot /mnt efibootmgr -b "$bn" -B 2>/dev/null || true
        done
        # Создаём новую
        chroot /mnt efibootmgr --create --disk "$BOOT_DISK" --part "$BOOT_PART_NUM" \
            --label "Void Linux" --loader '\EFI\BOOT\BOOTX64.EFI' 2>/dev/null ||
            chroot /mnt efibootmgr --create --disk "$BOOT_DISK" --part "$BOOT_PART_NUM" \
                --label "Void Linux" --loader '/EFI/BOOT/BOOTX64.EFI' 2>/dev/null ||
            warn "efibootmgr не смог создать запись — не страшно, BOOTX64.EFI fallback сработает"
    fi
fi

# Показываем что получилось в NVRAM
echo ""
info "Текущие записи UEFI (efibootmgr):"
chroot /mnt efibootmgr 2>/dev/null | head -15 || warn "efibootmgr недоступен"

# --- Проверка ---
echo ""
info "Проверка:"
if [ -f /mnt/boot/EFI/BOOT/BOOTX64.EFI ]; then
    echo -e "${GREEN}  ✅ /EFI/BOOT/BOOTX64.EFI — OK${NC}"
else
    echo -e "${RED}  ❌ /EFI/BOOT/BOOTX64.EFI — NOT FOUND${NC}"
fi
if [ -f "/mnt/boot/EFI/Void Linux/grubx64.efi" ]; then
    echo -e "${GREEN}  ✅ /EFI/Void Linux/grubx64.efi — OK${NC}"
else
    echo -e "${RED}  ❌ /EFI/Void Linux/grubx64.efi — NOT FOUND${NC}"
fi
if [ -f /mnt/boot/grub/grub.cfg ]; then
    echo -e "${GREEN}  ✅ /boot/grub/grub.cfg — OK ($(wc -l </mnt/boot/grub/grub.cfg) строк)${NC}"
else
    echo -e "${RED}  ❌ /boot/grub/grub.cfg — ОТСУТСТВУЕТ!${NC}"
fi

# --- Размонтируем ---
info "Unmounting..."
umount -R /mnt 2>/dev/null || true

echo ""
echo -e "${GREEN}Готово! Можно перезагружаться:${NC}"
echo "  sudo reboot"

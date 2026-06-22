#!/usr/bin/env bash
#===============================================================================
# fix-grub.sh
# Чиним GRUB загрузчик на уже установленной системе.
#
# Использование:
#   1. Загрузитесь с Void Linux Live ISO
#   2. Подключите интернет
#   3. Скачайте скрипт:
#      curl -O https://raw.githubusercontent.com/Redm00use/Void-Niri/main/fix-grub.sh
#   4. Запустите:
#      sudo bash fix-grub.sh /dev/sda
#      (замените /dev/sda на ваш диск, как lsblk показывает)
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

if [ $# -lt 1 ]; then
    echo "Usage: sudo bash fix-grub.sh /dev/sdX"
    echo ""
    echo "Доступные диски:"
    lsblk -d -e 7,11 -o NAME,SIZE,TYPE,MODEL 2>/dev/null | grep -E 'disk' || true
    echo ""
    echo "Пример: sudo bash fix-grub.sh /dev/sda"
    exit 1
fi

DISK="$1"
ROOT_PART="${DISK}3" # третья партиция — root (если layout стандартный)
EFI_PART="${DISK}1"  # первая — EFI

# Пытаемся найти root по метке или типу ФС
# Сначала пробуем третий раздел, если он не существует или не подходит — ищем вручную
if [ ! -b "$ROOT_PART" ]; then
    warn "$ROOT_PART not found. Scanning for root partition..."
    ROOT_PART=$(blkid -t TYPE="btrfs" -o device 2>/dev/null | head -1 || true)
    if [ -z "$ROOT_PART" ]; then
        ROOT_PART=$(blkid -t TYPE="ext4" -o device 2>/dev/null | head -1 || true)
    fi
    if [ -z "$ROOT_PART" ]; then
        error "Cannot find root partition. Available partitions:"
        lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT
        exit 1
    fi
    info "Found root: $ROOT_PART"
fi

if [ ! -b "$EFI_PART" ]; then
    warn "$EFI_PART not found. Scanning for EFI partition..."
    EFI_PART=$(blkid -t TYPE="vfat" -o device 2>/dev/null | head -1 || true)
    if [ -z "$EFI_PART" ]; then
        error "Cannot find EFI partition (vfat). Available partitions:"
        lsblk -o NAME,SIZE,TYPE,FSTYPE
        exit 1
    fi
    info "Found EFI: $EFI_PART"
fi

echo ""
echo -e "${BLUE}=== План ===${NC}"
echo "  Root:  $ROOT_PART"
echo "  EFI:   $EFI_PART"
echo "  Disk:  $DISK"
echo ""

read -r -p "Продолжить? [y/N]: "
[[ "$REPLY" =~ ^[yY] ]] || {
    error "Отмена."
    exit 0
}

# Монтируем
info "Mounting $ROOT_PART → /mnt..."
mount "$ROOT_PART" /mnt

info "Mounting $EFI_PART → /mnt/boot..."
mkdir -p /mnt/boot
mount "$EFI_PART" /mnt/boot

info "Bind-mounting /sys, /dev, /proc..."
mount --rbind /sys /mnt/sys
mount --rbind /dev /mnt/dev
mount --rbind /proc /mnt/proc
mount --rbind /run /mnt/run 2>/dev/null || true

# Chroot установка GRUB
info "Installing GRUB..."
chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id="Void Linux" --removable

info "Reconfiguring kernel..."
chroot /mnt xbps-reconfigure -f linux

# Проверка
echo ""
info "Проверка:"
if [ -f /mnt/boot/EFI/BOOT/BOOTX64.EFI ]; then
    echo -e "${GREEN}  ✅ /EFI/BOOT/BOOTX64.EFI — OK${NC}"
else
    echo -e "${RED}  ❌ /EFI/BOOT/BOOTX64.EFI — NOT FOUND${NC}"
fi
if [ -f /mnt/boot/EFI/Void\ Linux/grubx64.efi ]; then
    echo -e "${GREEN}  ✅ /EFI/Void Linux/grubx64.efi — OK${NC}"
else
    echo -e "${RED}  ❌ /EFI/Void Linux/grubx64.efi — NOT FOUND${NC}"
fi

# Размонтируем
info "Unmounting..."
umount -R /mnt 2>/dev/null || true

echo ""
echo -e "${GREEN}Готово! Можно перезагружаться:${NC}"
echo "  sudo reboot"

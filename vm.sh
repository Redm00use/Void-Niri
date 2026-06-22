#!/usr/bin/env bash
#===============================================================================
# vm.sh — запуск VM Void-Niri (QEMU + UEFI)
# Использование: sudo bash vm.sh
#===============================================================================
set -eu

DISK="${1:-}"
RAM="${RAM:-4096}"
CORES="${CORES:-4}"

# Ищем образ диска
if [ -z "$DISK" ]; then
    for try in disk.qcow2 disk.img void-niri.qcow2 void-niri.img void-disk.qcow2 void-disk.img; do
        [ -f "$try" ] && {
            DISK="$try"
            break
        }
    done
    [ -z "$DISK" ] && {
        echo "Не найден образ диска. Укажи вручную:"
        echo "  sudo bash vm.sh /путь/к/disk.img"
        exit 1
    }
fi

# Ищем OVMF (UEFI firmware)
OVMF=""
for try in \
    /usr/share/edk2/x64/OVMF_CODE.fd \
    /usr/share/edk2-ovmf/x64/OVMF_CODE.fd \
    /usr/share/OVMF/OVMF_CODE.fd \
    /usr/share/qemu/ovmf-x86_64.bin; do
    [ -f "$try" ] && {
        OVMF="$try"
        break
    }
done
[ -z "$OVMF" ] && {
    echo "OVMF не найден. Установи: sudo apt install ovmf (или equery install edk2-ovmf)"
    exit 1
}

echo "=== Запуск Void-Niri ==="
echo "  Диск:   $DISK"
echo "  RAM:    ${RAM}M"
echo "  Ядра:   $CORES"
echo "  UEFI:   $OVMF"
echo "  ISO:    НЕ ПОДКЛЮЧЁН"
echo ""

# Определяем формат образа
EXT="${DISK##*.}"
case "$EXT" in
qcow2) FMT=qcow2 ;;
img | raw) FMT=raw ;;
*) FMT=$(qemu-img info "$DISK" 2>/dev/null | grep -i 'file format' | awk '{print $3}' || echo "raw") ;;
esac

exec qemu-system-x86_64 \
    -enable-kvm \
    -m "$RAM" \
    -smp "$CORES" \
    -bios "$OVMF" \
    -drive file="$DISK",format="$FMT",if=virtio \
    -boot order=c \
    -vga virtio \
    -display gtk \
    -device virtio-net,netdev=net0 \
    -netdev user,id=net0 \
    -audiodev pa,id=audio0 \
    -device intel-hda -device hda-output,audiodev=audio0 \
    "$@" 2>&1

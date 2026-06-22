#!/usr/bin/env bash
#===============================================================================
# diagnose.sh — Диагностика загрузчика Void-Niri
# Запускать из Live ISO (после установки)
#
# Использование:
#   curl -sL https://raw.githubusercontent.com/Redm00use/Void-Niri/main/diagnose.sh | sudo bash
#===============================================================================
set -u
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'
OK="${GREEN}✓${NC}"
NO="${RED}✗${NC}"
WA="${YELLOW}⚠${NC}"

# Монтируем
mount -o subvol=@ /dev/vda3 /mnt 2>/dev/null ||
    mount -o subvol=@ /dev/sda3 /mnt 2>/dev/null || {
    echo -e "${RED}Не могу примонтировать /dev/vda3 или /dev/sda3${NC}"
    echo "Доступные разделы:"
    lsblk -o NAME,SIZE,FSTYPE,LABEL
    exit 1
}
mount /dev/vda1 /mnt/boot 2>/dev/null || mount /dev/sda1 /mnt/boot 2>/dev/null

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}  Диагностика загрузчика Void-Niri${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""

# 1. EFI файлы
echo -e "${YELLOW}[1/7] EFI загрузчик${NC}"
if [ -f /mnt/boot/EFI/BOOT/BOOTX64.EFI ]; then
    echo -e "  ${OK} /EFI/BOOT/BOOTX64.EFI — найден"
    ls -lh /mnt/boot/EFI/BOOT/BOOTX64.EFI
else
    echo -e "  ${NO} /EFI/BOOT/BOOTX64.EFI — ОТСУТСТВУЕТ"
fi
if [ -f "/mnt/boot/EFI/Void Linux/grubx64.efi" ]; then
    echo -e "  ${OK} /EFI/Void Linux/grubx64.efi — найден"
else
    echo -e "  ${WA} /EFI/Void Linux/grubx64.efi — нет (не критично)"
fi

# 2. Ядро и initramfs
echo ""
echo -e "${YELLOW}[2/7] Ядро и initramfs${NC}"
KERNEL=$(ls /mnt/boot/vmlinuz-* 2>/dev/null | head -1 || echo "")
INITRD=$(ls /mnt/boot/initrd-* /mnt/boot/initramfs-* 2>/dev/null | head -1 || echo "")
if [ -n "$KERNEL" ]; then
    echo -e "  ${OK} Ядро: $(basename $KERNEL)"
else
    echo -e "  ${NO} Ядро не найдено в /boot!"
    ls -la /mnt/boot/ 2>/dev/null | head -10
fi
if [ -n "$INITRD" ]; then
    echo -e "  ${OK} Initrd: $(basename $INITRD)"
else
    echo -e "  ${NO} Initramfs не найден!"
fi

# 3. GRUB конфиг
echo ""
echo -e "${YELLOW}[3/7] GRUB конфиг${NC}"
if [ -f /mnt/boot/grub/grub.cfg ]; then
    echo -e "  ${OK} /boot/grub/grub.cfg — найден ($(wc -l </mnt/boot/grub/grub.cfg) строк)"
    # Проверяем есть ли в конфиге запись о корне
    grep -q "linux.*/boot/vmlinuz" /mnt/boot/grub/grub.cfg 2>/dev/null &&
        echo -e "  ${OK} Есть запись linux с ядром" ||
        echo -e "  ${NO} В grub.cfg нет записи linux!"
    grep -q "root=" /mnt/boot/grub/grub.cfg 2>/dev/null &&
        echo -e "  ${OK} Есть root= параметр" ||
        echo -e "  ${NO} Нет root= параметра в grub.cfg!"
    grep -q "subvol=@" /mnt/boot/grub/grub.cfg 2>/dev/null &&
        echo -e "  ${OK} Есть subvol=@ (btrfs)" ||
        echo -e "  ${WA} Нет subvol=@ (возможно ext4 или проблема)"
else
    echo -e "  ${NO} /boot/grub/grub.cfg — ОТСУТСТВУЕТ!"
    echo "  Содержимое /boot/grub/:"
    ls -la /mnt/boot/grub/ 2>/dev/null || echo "  /boot/grub/ не существует"
fi

# 4. fstab
echo ""
echo -e "${YELLOW}[4/7] /etc/fstab${NC}"
if [ -f /mnt/etc/fstab ]; then
    echo -e "  ${OK} fstab найден:"
    cat /mnt/etc/fstab | while IFS= read -r line; do
        echo "    $line"
    done
else
    echo -e "  ${NO} /etc/fstab — ОТСУТСТВУЕТ!"
fi

# 5. efibootmgr (регистрация в NVRAM)
echo ""
echo -e "${YELLOW}[5/7] NVRAM (efibootmgr)${NC}"
mount --rbind /sys /mnt/sys 2>/dev/null
mount --rbind /dev /mnt/dev 2>/dev/null
mount --rbind /proc /mnt/proc 2>/dev/null
if chroot /mnt efibootmgr 2>/dev/null; then
    :
else
    echo -e "  ${WA} efibootmgr не может прочитать NVRAM (в VM нормально)"
    echo -e "  ${WA} Но это значит что нужен fallback /EFI/BOOT/BOOTX64.EFI"
fi

# 6. Тип загрузки (UEFI или BIOS)
echo ""
echo -e "${YELLOW}[6/7] Режим загрузки Live ISO${NC}"
if [ -d /sys/firmware/efi ]; then
    echo -e "  ${OK} Live ISO загружен в режиме UEFI"
else
    echo -e "  ${NO} Live ISO загружен в режиме BIOS/Legacy!"
    echo "  Установка не сможет работать! Включи UEFI в настройках QEMU."
    echo "  QEMU: добавь в команду -bios /usr/share/edk2/x64/OVMF_CODE.fd"
fi

# 7. Итог
echo ""
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}  Итог${NC}"
echo -e "${CYAN}========================================${NC}"
if [ -f /mnt/boot/EFI/BOOT/BOOTX64.EFI ] && [ -n "$KERNEL" ] && [ -f /mnt/boot/grub/grub.cfg ]; then
    echo -e "  ${GREEN}ВСЁ НА МЕСТЕ. Загрузчик + ядро + grub.cfg — есть.${NC}"
    echo -e "  ${GREEN}Проблема ВНЕ системы: ISO диск всё ещё в приводе.${NC}"
    echo ""
    echo -e "  Чтобы починить:"
    echo -e "  1. Выключи VM: ${YELLOW}poweroff${NC}"
    echo -e "  2. Отключи ISO образ в QEMU (убери -cdrom)"
    echo -e "  3. Запусти снова — должно загрузиться"
    echo ""
    echo -e "  Если не поможет — попробуй:"
    echo -e "  ${YELLOW}  qemu-system-x86_64 -drive file=disk.img -boot order=c -bios /usr/share/edk2/x64/OVMF_CODE.fd${NC}"
elif [ ! -f /mnt/boot/EFI/BOOT/BOOTX64.EFI ]; then
    echo -e "  ${RED}НЕТ BOOTX64.EFI — загрузчик не установлен!${NC}"
    echo -e "  Запусти: ${YELLOW}sudo bash fix-grub.sh /dev/vda${NC}"
else
    echo -e "  ${RED}Что-то не так. Смотри вывод выше.${NC}"
fi

# Размонтируем
umount -R /mnt 2>/dev/null

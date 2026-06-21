# Void-Niri

Полная копия [NixOS-Niri](https://github.com/viitorags/NixOS-Niri) на Void Linux (glibc).

Один скрипт — полная установка из Void Live ISO.

## Быстрый старт

### 1. Загрузись в Void Linux Live ISO (glibc)

ISO: https://voidlinux.org/download/ → **glibc** (не musl)

```bash
sudo dd if=void-live-x86_64-*.iso of=/dev/sdX bs=4M status=progress
```

### 2. Интернет

```bash
# WiFi
wpa_passphrase "SSID" "pass" >> /etc/wpa_supplicant/wpa_supplicant.conf
wpa_supplicant -B -i wlan0 -c /etc/wpa_supplicant/wpa_supplicant.conf
dhcpcd wlan0

# Провод
dhcpcd eth0
```

### 3. Запуск установщика

```bash
xbps-install -Sy git
git clone https://github.com/viitorags/Void-Niri /tmp/void-niri
cd /tmp/void-niri
sudo bash install.sh --mode live
```

### 4. Вопросы

- Имя хоста / пользователя (по умолчанию: `kotlin`)
- Роль: `desktop` / `server`
- GPU: `amd` / `nvidia` / `intel` / `vm`
- ФС root: `btrfs` / `ext4`
- Диск, отдельный /home, swap, LUKS

### 5. Подтверждение

Напиши `ERASE` для стирания диска.

### 6. Перезагрузка

```bash
reboot
# Логин: kotlin / 1408
bash ~/void-niri/setup/post-install.sh
```

## Неинтерактивный режим

```bash
sudo bash install.sh --mode live \
  --host kotlin --user kotlin --role desktop --gpu amd \
  --timezone Europe/Kyiv --locale ru_RU.UTF-8 \
  --fs btrfs --disk /dev/nvme0n1 --swap-gib 8 --yes
```

| Флаг | Значения | По умолчанию |
|------|----------|-------------|
| `--mode` | `config`, `live` | `live` |
| `--host` | имя | `kotlin` |
| `--user` | имя | `kotlin` |
| `--role` | `desktop`, `server` | `desktop` |
| `--gpu` | `amd`, `nvidia`, `intel`, `vm` | `amd` |
| `--timezone` | Europe/Kyiv | Europe/Kyiv |
| `--locale` | ru_RU.UTF-8 | ru_RU.UTF-8 |
| `--fs` | `btrfs`, `ext4` | `btrfs` |
| `--disk` | /dev/nvme0n1 | выбор |
| `--swap-gib` | размер | 8 |
| `--luks` | флаг | false |
| `--yes` | пропуск подтверждения | false |

## Что внутри

```
Void-Niri/
├── install.sh              # установщик (518 строк)
├── configs/                # все dotfiles из NixOS
│   ├── niri/config.kdl     #   бинды, window-rules, анимации
│   ├── rofi/               #   meowrch, launchpad, emoji
│   ├── wezterm/            #   полный lua-конфиг
│   ├── walker/             #   catppuccin-mocha темы
│   ├── yazi/               #   плагины (git, yatline, kdeconnect)
│   ├── fastfetch/          #   neofetch-стиль
│   ├── btop/ cava/         #   мониторинг / визуализатор
│   ├── zed/                #   редактор
│   ├── zsh/                #   Oh-My-Zsh + алиасы
│   ├── gtk/                #   Catppuccin Mocha Dark
│   ├── noctalia/           #   шелл
│   └── lazygit/
├── packages/               # списки xbps
│   ├── base.list           #   72 пакета (система)
│   ├── desktop.list        #   106 пакетов (niri, steam, ...)
│   ├── dev.list            #   инструменты разработки
│   └── gpu-*.list          #   AMD / NVIDIA / Intel
└── setup/
    └── post-install.sh     #   Oh-My-Zsh, flatpak, темы
```

## NixOS → Void Linux

| Компонент | NixOS | Void |
|-----------|-------|------|
| Пакеты | nix flakes | xbps |
| Инит | systemd | runit |
| Теминг | Stylix (авто) | dotfiles |
| Обновление | `nixos-rebuild switch` | `xbps-install -Su` |
| niri | niri-blur форк | vanilla niri |

## Ручная доустановка

```bash
# Catppuccin GTK тема
flatpak install org.gtk.Gtk3theme.Catppuccin-Mocha-Standard-Mauve-Dark

# Neovim
git clone https://github.com/viitorags/nvim ~/.config/nvim

# Google Chrome Canary
flatpak install flathub com.google.Chrome
```

### Патчи Noctalia

Убирают эффекты которые были в NixOS-Niri:
- **Блюр на панели** — панель прозрачная без размытия
- **Hover highlight в лаунчере** — статичный цвет без подсветки
- **Unified shadow system** — единая система теней

Применяются: `bash patches/patch-noctalia.sh`
(автоматически из `setup/post-install.sh`)

Файлы патчей: `patches/noctalia/*.qml` (5 QML файлов)

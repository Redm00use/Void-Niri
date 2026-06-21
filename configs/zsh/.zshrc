# ZSH Configuration — адаптировано из NixOS home-manager конфига

# Path
export PATH="$HOME/.local/bin:$HOME/.cache/npm/global/bin:$PATH"

# Key timeout for vi mode
KEYTIMEOUT=1

# Oh-My-Zsh
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="kphoen"

# Plugins (установлены системно через xbps)
plugins=(git zsh-syntax-highlighting zsh-autosuggestions)

# Source Oh-My-Zsh (если установлен)
if [ -f "$ZSH/oh-my-zsh.sh" ]; then
    source "$ZSH/oh-my-zsh.sh"
fi

# Aliases
alias rb="echo 'Для Void используй: sudo xbps-install -Su'"
alias upd="sudo xbps-install -Su"
alias upg="sudo xbps-install -Suy"
alias conf="nvim ~/void-niri"
alias pkgs="nvim ~/void-niri/packages/base.list"
alias ls="eza -ha --icons=auto --sort=name --group-directories-first"
alias ll="eza -lh --icons=auto"
alias ff="fastfetch"
alias clear="clear && printf '\033c'"

# Fastfetch при первом входе
if [[ -o interactive ]] && [[ -z "$FASTFETCH_SHOWN" ]] && [[ "$TERM" != "dumb" ]] && command -v fastfetch >/dev/null 2>&1; then
    export FASTFETCH_SHOWN=1
    fastfetch
fi

# Wayland
export XDG_SESSION_TYPE=wayland
export QT_QPA_PLATFORM="wayland;xcb"
export XKB_DEFAULT_OPTIONS="led:scroll"
export TERMINAL="wezterm"
export EDITOR="nvim"

# Direnv
eval "$(direnv hook zsh)" 2>/dev/null || true

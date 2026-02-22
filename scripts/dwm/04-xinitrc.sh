#!/usr/bin/env bash
# =============================================================================
# scripts/dwm/04-xinitrc.sh
# Description: Create ~/.xinitrc for dwm and add auto-startx to ~/.bash_profile
# Usage:       bash scripts/dwm/04-xinitrc.sh
#              (runs as your normal user — no root required)
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
ok()    { echo -e "${GREEN}[ OK ]${NC}  $*"; }
error() { echo -e "${RED}[ERR ]${NC}  $*" >&2; }

if [[ "${EUID}" -eq 0 ]]; then
    error "Do not run this script as root. It writes to your home directory."
    exit 1
fi

XINITRC="${HOME}/.xinitrc"
BASH_PROFILE="${HOME}/.bash_profile"

# ── Backup helpers ────────────────────────────────────────────────────────────
backup_if_exists() {
    local file="$1"
    if [[ -f "${file}" ]]; then
        local bak="${file}.bak.$(date +%Y%m%d_%H%M%S)"
        warn "Backing up existing ${file} → ${bak}"
        cp "${file}" "${bak}"
    fi
}

# ── 1. Create ~/.xinitrc ──────────────────────────────────────────────────────
backup_if_exists "${XINITRC}"

info "Writing ${XINITRC}…"
cat > "${XINITRC}" <<'EOF'
#!/bin/sh
# ~/.xinitrc — started by startx/xinit
# Edit to match your hardware and preferences.

# ── Monitor layout ──────────────────────────────────────────────────────────
# Uncomment and adjust for your setup (run `xrandr` to discover output names):
# xrandr --output HDMI-1 --mode 1920x1080 --rate 60 --primary &

# ── Keyboard ────────────────────────────────────────────────────────────────
# setxkbmap -layout us &

# ── Wallpaper ───────────────────────────────────────────────────────────────
# feh --bg-fill ~/Pictures/wallpaper.jpg &
# xwallpaper --zoom ~/Pictures/wallpaper.png &

# ── Compositor ──────────────────────────────────────────────────────────────
# picom --backend glx --vsync &

# ── Notification daemon ──────────────────────────────────────────────────────
# dunst &

# ── Status bar (date/time in dwm bar via xsetroot) ───────────────────────────
while true; do
    xsetroot -name "$(date '+%a %d %b  %H:%M:%S')"
    sleep 1
done &

# ── Launch dwm ───────────────────────────────────────────────────────────────
exec dwm
EOF
chmod +x "${XINITRC}"
ok "${XINITRC} created"

# ── 2. Auto-startx snippet for ~/.bash_profile ────────────────────────────────
AUTOSTARTX_MARKER="# auto-startx on TTY1"

if [[ -f "${BASH_PROFILE}" ]] && grep -qF "${AUTOSTARTX_MARKER}" "${BASH_PROFILE}"; then
    ok "auto-startx snippet already present in ${BASH_PROFILE}"
else
    backup_if_exists "${BASH_PROFILE}"
    info "Appending auto-startx snippet to ${BASH_PROFILE}…"
    cat >> "${BASH_PROFILE}" <<'EOF'

# auto-startx on TTY1
if [ -z "${DISPLAY}" ] && [ "${XDG_VTNR:-0}" -eq 1 ]; then
    exec startx
fi
EOF
    ok "auto-startx snippet added to ${BASH_PROFILE}"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
ok "xinitrc and bash_profile configured."
echo ""
echo "  Files written:"
echo "    • ${XINITRC}"
echo "    • ${BASH_PROFILE}"
echo ""
info "Log out and back in on TTY1 — X will start automatically and launch dwm."
info "To customise the status bar, compositor, or wallpaper, edit ${XINITRC}."

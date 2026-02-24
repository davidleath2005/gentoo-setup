#!/usr/bin/env bash
# =============================================================================
# scripts/dwm/04-xinitrc.sh
# Description: Create ~/.xinitrc for dwm with picom, xwallpaper, dunst, and
#              a status bar.  Add auto-startx to ~/.bash_profile.
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
cat > "${XINITRC}" << 'EOF'
#!/bin/sh
# ~/.xinitrc — started by startx/xinit
# Configured for: dwm + picom + dunst + status bar
# Edit to match your hardware and preferences.

# ── D-Bus session (required for elogind, polkit, notifications) ─────────────
if command -v dbus-launch >/dev/null 2>&1 && [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
    eval "$(dbus-launch --sh-syntax --exit-with-x11)"
fi

# ── Monitor layout ──────────────────────────────────────────────────────────
# Run `xrandr` to discover your output names, then uncomment and adjust:
# xrandr --output DP-1 --mode 2560x1440 --rate 144 --primary &
# xrandr --output HDMI-1 --mode 1920x1080 --rate 60 --right-of DP-1 &

# ── Keyboard ────────────────────────────────────────────────────────────────
# setxkbmap -layout us &

# ── Cursor ──────────────────────────────────────────────────────────────────
xsetroot -cursor_name left_ptr &

# ── Wallpaper ───────────────────────────────────────────────────────────────
# Create ~/Pictures/ and place a wallpaper there, then uncomment:
if command -v xwallpaper >/dev/null 2>&1; then
    if [ -f ~/Pictures/wallpaper.png ]; then
        xwallpaper --zoom ~/Pictures/wallpaper.png &
    elif [ -f ~/Pictures/wallpaper.jpg ]; then
        xwallpaper --zoom ~/Pictures/wallpaper.jpg &
    else
        # Solid dark background as fallback
        xsetroot -solid '#1d2021' &
    fi
else
    xsetroot -solid '#1d2021' &
fi

# ── Audio — PipeWire + WirePlumber ──────────────────────────────────────────
# PipeWire replaces PulseAudio as the modern audio/video server.
# WirePlumber is its session manager. Both run in user-space.
if command -v pipewire >/dev/null 2>&1; then
    pipewire &
    sleep 0.2
    # PipeWire-pulse: compatibility layer for PulseAudio clients
    if command -v pipewire-pulse >/dev/null 2>&1; then
        pipewire-pulse &
    fi
    # WirePlumber: session / policy manager
    if command -v wireplumber >/dev/null 2>&1; then
        wireplumber &
    fi
fi

# ── Compositor (picom) ──────────────────────────────────────────────────────
# Enables transparency, rounded corners, vsync.  Remove --vsync if tearing
# is not an issue (RDNA 3 + Xorg should be fine with it on).
if command -v picom >/dev/null 2>&1; then
    picom --backend glx --vsync &
fi

# ── Notification daemon (dunst) ──────────────────────────────────────────────
if command -v dunst >/dev/null 2>&1; then
    dunst &
fi

# ── Screen locker ─────────────────────────────────────────────────────────────
# Uncomment if you use slock or i3lock:
# slock &

# ── Status bar ────────────────────────────────────────────────────────────────
# Sets dwm's root window name as a simple status bar.
# Customize the fields below to your preference.
dwm_status() {
    while true; do
        # CPU temp (AMD k10temp — find the right hwmon device)
        TEMP=""
        for hwmon in /sys/class/hwmon/hwmon*; do
            if [ -f "$hwmon/name" ] && grep -q 'k10temp' "$hwmon/name" 2>/dev/null; then
                raw=$(cat "$hwmon/temp1_input" 2>/dev/null)
                if [ -n "$raw" ]; then
                    TEMP=" | ${raw%???}°C"
                fi
                break
            fi
        done

        # Memory usage
        MEM=$(free -h 2>/dev/null | awk '/^Mem:/ {printf "%s/%s", $3, $2}')

        # Volume — prefer wpctl (PipeWire) over amixer (ALSA)
        VOL=""
        if command -v wpctl >/dev/null 2>&1; then
            pw_vol=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null | awk '{printf "%.0f%%", $2*100}')
            if [ -n "$pw_vol" ]; then
                VOL=" | Vol: $pw_vol"
            fi
        elif command -v amixer >/dev/null 2>&1; then
            VOL=" | Vol: $(amixer get Master 2>/dev/null | grep -oP '\[\d+%\]' | head -1)"
        fi

        # Date/time
        DT=$(date '+%a %d %b %H:%M')

        xsetroot -name " ${MEM}${TEMP}${VOL} | ${DT} "
        sleep 2
    done
}
dwm_status &

# ── Launch dwm (restart loop) ────────────────────────────────────────────────
# If dwm exits cleanly (e.g. restart signal), it restarts.
# If you want a single-run, replace the while loop with: exec dwm
while true; do
    dwm 2>/dev/null
    # dwm exited — if it was a crash, small delay before restart
    sleep 0.5
done
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
    cat >> "${BASH_PROFILE}" << 'EOF'

# auto-startx on TTY1
if [ -z "${DISPLAY}" ] && [ "${XDG_VTNR:-0}" -eq 1 ]; then
    exec startx
fi
EOF
    ok "auto-startx snippet added to ${BASH_PROFILE}"
fi

# ── 3. Create default dunst config (Gruvbox themed) ──────────────────────────
DUNST_DIR="${HOME}/.config/dunst"
if [[ ! -f "${DUNST_DIR}/dunstrc" ]]; then
    mkdir -p "${DUNST_DIR}"
    info "Creating Gruvbox-themed dunst config…"
    cat > "${DUNST_DIR}/dunstrc" << 'EOF'
[global]
    monitor = 0
    follow = mouse
    width = 350
    height = 100
    origin = top-right
    offset = 10x40
    notification_limit = 5
    progress_bar = true
    indicate_hidden = yes
    transparency = 10
    separator_height = 2
    padding = 12
    horizontal_padding = 12
    frame_width = 2
    frame_color = "#a9b665"
    separator_color = frame
    sort = yes
    font = monospace 11
    line_height = 0
    markup = full
    format = "<b>%s</b>\n%b"
    alignment = left
    show_age_threshold = 60
    word_wrap = yes
    corner_radius = 4
    mouse_left_click = close_current
    mouse_middle_click = do_action, close_current
    mouse_right_click = close_all

[urgency_low]
    background = "#1d2021"
    foreground = "#d4be98"
    timeout = 5

[urgency_normal]
    background = "#1d2021"
    foreground = "#d4be98"
    frame_color = "#a9b665"
    timeout = 10

[urgency_critical]
    background = "#1d2021"
    foreground = "#ea6962"
    frame_color = "#ea6962"
    timeout = 0
EOF
    ok "Dunst config written to ${DUNST_DIR}/dunstrc"
else
    ok "Dunst config already exists: ${DUNST_DIR}/dunstrc"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
ok "xinitrc, bash_profile, and dunst configured."
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "  Files written:"
echo "    • ${XINITRC}"
echo "    • ${BASH_PROFILE}"
echo "    • ${DUNST_DIR}/dunstrc"
echo ""
echo "  Enabled by default:"
echo "    ✔  PipeWire + WirePlumber (modern audio server)"
echo "    ✔  picom (GLX compositor with vsync)"
echo "    ✔  dunst (Gruvbox-themed notifications)"
echo "    ✔  xwallpaper (auto-detects ~/Pictures/wallpaper.{png,jpg})"
echo "    ✔  Status bar (RAM, CPU temp, volume, date/time)"
echo "    ✔  D-Bus session launch"
echo "    ✔  dwm restart loop (survives dwm restart signal)"
echo ""
info "Log out and back in on TTY1 — X will start automatically."
info "To customise: edit ${XINITRC}"

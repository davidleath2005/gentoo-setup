#!/usr/bin/env bash
# =============================================================================
# scripts/dwm/02-deps.sh
# Description: Install Xorg, build libraries for dwm/st/dmenu, fonts, audio,
#              desktop utilities, AMD GPU packages, and essential services.
#              Shows ALL missing packages before emerging anything.
# Usage:       sudo bash scripts/dwm/02-deps.sh
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../common/detect-hardware.sh
source "${SCRIPT_DIR}/../common/detect-hardware.sh"

if [[ "${EUID}" -ne 0 ]]; then
    error "This script must be run as root."
    exit 1
fi

# ── Terminal width ────────────────────────────────────────────────────────────
COLS=$(tput cols 2>/dev/null || echo 80)
[[ "${COLS}" -lt 60 ]] && COLS=60
[[ "${COLS}" -gt 120 ]] && COLS=120
DIM='\033[2m'

hr() {
    printf "${CYAN}"
    printf '━%.0s' $(seq 1 "${COLS}")
    printf "${NC}\n"
}

hr_thin() {
    printf "${DIM}"
    printf '─%.0s' $(seq 1 "${COLS}")
    printf "${NC}\n"
}

center() {
    local text="$1"
    local color="${2:-${NC}}"
    local stripped
    stripped=$(echo -e "${text}" | sed 's/\x1b\[[0-9;]*m//g')
    local len=${#stripped}
    local pad=$(( (COLS - len) / 2 ))
    [[ ${pad} -lt 0 ]] && pad=0
    printf "%${pad}s" ""
    echo -e "${color}${text}${NC}"
}

echo ""
hr
center "Install Dependencies — DWM / Suckless" "${BOLD}${GREEN}"
hr
echo ""

MARKER_DONE="${GREEN}●${NC}"
MARKER_TODO="${RED}○${NC}"

# ══════════════════════════════════════════════════════════════════════════════
# PACKAGE GROUPS — all packages needed for a complete DWM desktop
# ══════════════════════════════════════════════════════════════════════════════
declare -A PKG_GROUPS
declare -a GROUP_ORDER=(xorg suckless_build_libs fonts audio desktop_utils system_services amd_gpu)

PKG_GROUPS[xorg]="
    x11-base/xorg-server
    x11-apps/xinit
    x11-apps/xrandr
    x11-apps/xsetroot
"

PKG_GROUPS[suckless_build_libs]="
    x11-libs/libX11
    x11-libs/libXft
    x11-libs/libXinerama
    x11-libs/libXrender
    media-libs/fontconfig
    media-libs/freetype
    media-libs/harfbuzz
    x11-libs/libxcb
    x11-libs/xcb-util-wm
"

PKG_GROUPS[fonts]="
    media-fonts/terminus-font
    media-fonts/dejavu
    media-fonts/noto
    media-fonts/noto-emoji
"

PKG_GROUPS[audio]="
    media-libs/alsa-lib
    media-sound/alsa-utils
    media-plugins/alsa-plugins
    media-video/pipewire
    media-video/wireplumber
"

PKG_GROUPS[desktop_utils]="
    x11-misc/picom
    x11-misc/xwallpaper
    x11-misc/xclip
    x11-misc/dunst
    media-gfx/scrot
    app-misc/brightnessctl
    x11-misc/xdg-utils
    x11-misc/xdg-user-dirs
"

PKG_GROUPS[system_services]="
    sys-apps/dbus
    sys-auth/elogind
    sys-auth/polkit
    sys-process/cronie
    sys-apps/mlocate
"

PKG_GROUPS[amd_gpu]="
    sys-kernel/linux-firmware
    x11-libs/libdrm
    media-libs/mesa
    media-libs/vulkan-loader
    dev-util/vulkan-tools
"

# Pretty names for each group
declare -A GROUP_LABELS
GROUP_LABELS[xorg]="Xorg Display Server"
GROUP_LABELS[suckless_build_libs]="Suckless Build Libraries"
GROUP_LABELS[fonts]="Fonts"
GROUP_LABELS[audio]="Audio (ALSA + PipeWire)"
GROUP_LABELS[desktop_utils]="Desktop Utilities"
GROUP_LABELS[system_services]="System Services"
GROUP_LABELS[amd_gpu]="AMD GPU (RDNA 3)"

# ── 1. Sync portage ──────────────────────────────────────────────────────────
info "Syncing Portage tree…"
emaint sync -a
ok "Portage sync complete"
echo ""

# ── 2. Install git if not present ────────────────────────────────────────────
if ! command -v git &>/dev/null; then
    info "Installing git…"
    emerge --ask dev-vcs/git
    ok "git installed"
else
    ok "git already installed"
fi

# ══════════════════════════════════════════════════════════════════════════════
#  SCAN ALL PACKAGES — build a complete picture before touching anything
# ══════════════════════════════════════════════════════════════════════════════
echo ""
hr
center "Package Status Scan" "${BOLD}${CYAN}"
hr
echo ""

all_missing=()           # flat list of every missing package
declare -A group_missing # per-group missing lists (for display)
total_installed=0
total_missing=0

for group in "${GROUP_ORDER[@]}"; do
    echo -e "  ${CYAN}${BOLD}${GROUP_LABELS[${group}]}${NC}"
    missing_in_group=()

    for pkg in ${PKG_GROUPS[${group}]}; do
        if pkg_installed "${pkg}"; then
            printf "    ${MARKER_DONE}  %-42s ${GREEN}installed${NC}\n" "${pkg}"
            (( total_installed++ )) || true
        else
            printf "    ${MARKER_TODO}  %-42s ${RED}missing${NC}\n" "${pkg}"
            missing_in_group+=("${pkg}")
            all_missing+=("${pkg}")
            (( total_missing++ )) || true
        fi
    done
    echo ""

    group_missing[${group}]="${missing_in_group[*]:-}"
done

# ══════════════════════════════════════════════════════════════════════════════
#  SUMMARY — show what will be emerged BEFORE asking to proceed
# ══════════════════════════════════════════════════════════════════════════════
hr
center "Installation Summary" "${BOLD}${GREEN}"
hr
echo ""
echo -e "  ${GREEN}Installed${NC}: ${total_installed} packages"
echo -e "  ${RED}Missing${NC}:   ${total_missing} packages"
echo ""

if [[ ${total_missing} -eq 0 ]]; then
    ok "All packages are already installed — nothing to do!"
    echo ""
else
    echo -e "  ${BOLD}${YELLOW}The following packages will be emerged:${NC}"
    echo ""

    for group in "${GROUP_ORDER[@]}"; do
        if [[ -n "${group_missing[${group}]:-}" ]]; then
            echo -e "  ${CYAN}${GROUP_LABELS[${group}]}${NC}"
            for pkg in ${group_missing[${group}]}; do
                echo -e "    ${YELLOW}→${NC} ${pkg}"
            done
            echo ""
        fi
    done

    hr_thin
    echo ""
    echo -e "  ${BOLD}emerge command:${NC}"
    echo -e "    ${DIM}emerge --ask --verbose ${all_missing[*]}${NC}"
    echo ""
    hr_thin
    echo ""
    read -rp "  Proceed with installation? [Y/n]: " yn
    yn="${yn:-Y}"
    if [[ "${yn}" =~ ^[Nn]$ ]]; then
        warn "Installation cancelled."
        exit 0
    fi

    echo ""
    info "Emerging ${total_missing} package(s)…"
    echo ""
    emerge --ask --verbose "${all_missing[@]}"
    echo ""
    ok "All packages installed successfully."
fi

# ── Rebuild font cache ────────────────────────────────────────────────────────
echo ""
info "Rebuilding font cache…"
fc-cache -fv 2>&1 | tail -3
ok "Font cache rebuilt"

# ══════════════════════════════════════════════════════════════════════════════
#  ENABLE ESSENTIAL SERVICES
# ══════════════════════════════════════════════════════════════════════════════
enable_service() {
    local svc="$1"
    local runlevel="${2:-default}"
    if is_service_enabled "${svc}" "${runlevel}"; then
        ok "${svc} already in ${runlevel} runlevel"
    else
        info "Adding ${svc} to ${runlevel} runlevel"
        rc-update add "${svc}" "${runlevel}"
        ok "${svc} added to ${runlevel}"
    fi
}

echo ""
hr
center "OpenRC Services" "${BOLD}${CYAN}"
hr
echo ""

enable_service elogind boot
enable_service dbus default
enable_service cronie default

# ── Service status ────────────────────────────────────────────────────────────
echo ""
info "Service status:"
for svc in dbus elogind cronie; do
    if rc-service "${svc}" status &>/dev/null 2>&1; then
        ok "${svc} is running"
    else
        warn "${svc} is not running (will start on next boot or: rc-service ${svc} start)"
    fi
done

# ══════════════════════════════════════════════════════════════════════════════
#  AUDIO SETUP — ALSA + PipeWire
# ══════════════════════════════════════════════════════════════════════════════
echo ""
hr
center "Audio Configuration" "${BOLD}${CYAN}"
hr
echo ""

# ── Ensure desktop user is in essential groups ────────────────────────────────
DESKTOP_USER="${SUDO_USER:-}"
if [[ -n "${DESKTOP_USER}" ]] && id "${DESKTOP_USER}" &>/dev/null; then
    info "Checking group membership for ${DESKTOP_USER}…"
    REQUIRED_GROUPS=(audio video input seat plugdev wheel usb)
    for grp in "${REQUIRED_GROUPS[@]}"; do
        if getent group "${grp}" &>/dev/null; then
            if id -nG "${DESKTOP_USER}" | grep -qw "${grp}"; then
                ok "${DESKTOP_USER} already in ${grp}"
            else
                usermod -aG "${grp}" "${DESKTOP_USER}"
                ok "Added ${DESKTOP_USER} to ${grp}"
            fi
        fi
    done
    echo ""
fi

# Verify ALSA can see the sound card
if [[ -d /proc/asound ]]; then
    info "ALSA sound cards detected:"
    if [[ -f /proc/asound/cards ]]; then
        while IFS= read -r line; do
            echo "    ${line}"
        done < /proc/asound/cards
    fi
    echo ""
else
    warn "No ALSA sound devices found in /proc/asound"
    warn "Make sure CONFIG_SND_HDA_INTEL=y or =m is set in your kernel config."
    warn "For AMD Ryzen / B870, you also need CONFIG_SND_HDA_CODEC_REALTEK=m"
    echo ""
fi

# Unmute master channel if amixer is available
if command -v amixer &>/dev/null; then
    info "Ensuring ALSA Master channel is unmuted…"
    amixer -q sset Master unmute 2>/dev/null && ok "Master unmuted" || warn "Could not unmute Master (may need specific card name)"
    amixer -q sset Master 80% 2>/dev/null && ok "Master volume set to 80%" || true
else
    warn "amixer not available — install alsa-utils and reboot"
fi

# PipeWire note — PipeWire runs as a user-space daemon (NOT a system service)
info "PipeWire runs as a user-space process (started from ~/.xinitrc)."
info "After setup, audio will route through: ALSA → PipeWire → WirePlumber"
echo ""
ok "Audio stack configured (ALSA + PipeWire + WirePlumber)"

# ══════════════════════════════════════════════════════════════════════════════
#  FINAL SUMMARY
# ══════════════════════════════════════════════════════════════════════════════
echo ""
hr
center "Setup Complete" "${BOLD}${GREEN}"
hr
echo ""
echo "  ${BOLD}Installed:${NC}"
echo "    • Xorg server, xinit, xrandr, xsetroot"
echo "    • Build libs: libX11, libXft, libXinerama, libXrender, xcb"
echo "    • Fonts: terminus, dejavu, noto, noto-emoji"
echo "    • Audio: alsa-lib, alsa-utils, pipewire, wireplumber"
echo "    • Desktop: picom, xwallpaper, xclip, dunst, scrot, brightnessctl"
echo "    • Services: dbus, elogind, polkit, cronie"
echo "    • AMD GPU: linux-firmware, mesa, vulkan-loader"
echo ""
echo "  ${BOLD}Enabled services:${NC}"
echo "    • elogind  (boot)    — seat management"
echo "    • dbus     (default) — IPC bus"
echo "    • cronie   (default) — cron scheduler"
echo ""
echo "  ${BOLD}Audio stack:${NC}"
echo "    • ALSA     — kernel-level sound driver"
echo "    • PipeWire — user-space audio server (started from xinitrc)"
echo "    • WirePlumber — PipeWire session manager"
echo ""
info "Next step: bash scripts/dwm/03-build-suckless.sh  (run as your normal user)"

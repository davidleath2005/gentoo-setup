#!/usr/bin/env bash
# =============================================================================
# scripts/dwm/01-make-conf.sh
# Description: Configure /etc/portage/make.conf for a minimal Xorg/suckless setup
# Usage:       sudo bash scripts/dwm/01-make-conf.sh
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
ok()    { echo -e "${GREEN}[ OK ]${NC}  $*"; }
error() { echo -e "${RED}[ERR ]${NC}  $*" >&2; }

if [[ "${EUID}" -ne 0 ]]; then
    error "This script must be run as root."
    exit 1
fi

MAKE_CONF="/etc/portage/make.conf"

# ── Backup ────────────────────────────────────────────────────────────────────
BACKUP="${MAKE_CONF}.bak.$(date +%Y%m%d_%H%M%S)"
info "Backing up ${MAKE_CONF} → ${BACKUP}"
cp "${MAKE_CONF}" "${BACKUP}"
ok "Backup created: ${BACKUP}"

# ── CPU core count ────────────────────────────────────────────────────────────
NCPUS=$(nproc)
info "Detected ${NCPUS} CPU thread(s)"

# ── VIDEO_CARDS ───────────────────────────────────────────────────────────────
detect_video_cards() {
    local cards=""
    if lspci 2>/dev/null | grep -qi "AMD\|Radeon"; then
        cards="amdgpu radeonsi"
    elif lspci 2>/dev/null | grep -qi "NVIDIA"; then
        cards="nvidia"
    elif lspci 2>/dev/null | grep -qi "Intel"; then
        cards="intel i965 iris"
    fi
    echo "${cards}"
}

AUTO_CARDS=$(detect_video_cards)
if [[ -n "${AUTO_CARDS}" ]]; then
    info "Auto-detected VIDEO_CARDS=\"${AUTO_CARDS}\""
    read -rp "Use detected VIDEO_CARDS? [Y/n]: " yn
    yn="${yn:-Y}"
    if [[ "${yn}" =~ ^[Nn]$ ]]; then
        read -rp "Enter VIDEO_CARDS value: " AUTO_CARDS
    fi
else
    warn "Could not auto-detect GPU. Common values:"
    warn "  AMD:    amdgpu radeonsi"
    warn "  NVIDIA: nvidia"
    warn "  Intel:  intel i965 iris"
    read -rp "Enter VIDEO_CARDS value: " AUTO_CARDS
fi
VIDEO_CARDS="${AUTO_CARDS}"

# ── Helper: set or append a variable (idempotent) ─────────────────────────────
set_var() {
    local var="$1"
    local val="$2"
    if grep -q "^${var}=" "${MAKE_CONF}"; then
        warn "${var} already set — updating in place"
        sed -i "s|^${var}=.*|${var}=\"${val}\"|" "${MAKE_CONF}"
    else
        info "Appending ${var}"
        echo "${var}=\"${val}\"" >> "${MAKE_CONF}"
    fi
}

# ── Apply minimal settings ────────────────────────────────────────────────────
info "Configuring ${MAKE_CONF} for minimal Xorg/suckless setup…"

set_var "USE" "X -kde -gnome -plasma alsa"
set_var "VIDEO_CARDS" "${VIDEO_CARDS}"
set_var "INPUT_DEVICES" "libinput"
set_var "MAKEOPTS" "-j${NCPUS} -l${NCPUS}"

if ! grep -q "^ACCEPT_LICENSE=" "${MAKE_CONF}"; then
    info "Appending ACCEPT_LICENSE"
    echo 'ACCEPT_LICENSE="*"' >> "${MAKE_CONF}"
else
    ok "ACCEPT_LICENSE already present"
fi

# ── Verify ────────────────────────────────────────────────────────────────────
info "Validating ${MAKE_CONF} syntax…"
bash -n "${MAKE_CONF}" && ok "Syntax OK"

echo ""
ok "make.conf configured for minimal Xorg/suckless."
echo -e "  USE           = X -kde -gnome -plasma alsa"
echo -e "  VIDEO_CARDS   = ${VIDEO_CARDS}"
echo -e "  INPUT_DEVICES = libinput"
echo -e "  MAKEOPTS      = -j${NCPUS} -l${NCPUS}"
echo ""
info "Next step: sudo bash scripts/dwm/02-deps.sh"

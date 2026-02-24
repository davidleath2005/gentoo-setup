#!/usr/bin/env bash
# =============================================================================
# scripts/kde/01-make-conf.sh
# Description: Configure /etc/portage/make.conf for KDE Plasma 6 on Gentoo.
#              Optimised for Zen 5 (9800X3D) + RDNA 3 (RX 7800 XT).
# Usage:       sudo bash scripts/kde/01-make-conf.sh
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../common/detect-hardware.sh
source "${SCRIPT_DIR}/../common/detect-hardware.sh"

if [[ "${EUID}" -ne 0 ]]; then
    error "This script must be run as root."
    exit 1
fi

MAKE_CONF="/etc/portage/make.conf"

echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  ${GREEN}Configure make.conf — KDE Plasma 6${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# ── Pre-flight ────────────────────────────────────────────────────────────────
print_hardware_summary
echo ""
check_system_clock || true

# ── Backup ────────────────────────────────────────────────────────────────────
BACKUP="${MAKE_CONF}.bak.$(date +%Y%m%d_%H%M%S)"
info "Backing up ${MAKE_CONF} → ${BACKUP}"
cp "${MAKE_CONF}" "${BACKUP}"
ok "Backup created"

# ── CPU ───────────────────────────────────────────────────────────────────────
NCPUS=$(nproc)
info "Detected ${NCPUS} CPU thread(s)"

RAW_MARCH=$(detect_cpu_arch)
info "Detected CPU microarchitecture: ${RAW_MARCH}"
MARCH="${RAW_MARCH}"
check_gcc_version "${RAW_MARCH}" "native"
info "Using -march=${MARCH}"

CPU_FLAGS=""
detect_cpu_flags

# ── VIDEO_CARDS ───────────────────────────────────────────────────────────────
AUTO_CARDS=$(detect_video_cards)
if [[ -n "${AUTO_CARDS}" ]]; then
    info "Auto-detected VIDEO_CARDS=\"${AUTO_CARDS}\""
    read -rp "  Use detected VIDEO_CARDS? [Y/n]: " yn
    yn="${yn:-Y}"
    if [[ "${yn}" =~ ^[Nn]$ ]]; then
        read -rp "  Enter VIDEO_CARDS value: " AUTO_CARDS
    fi
else
    read -rp "  Enter VIDEO_CARDS value [amdgpu radeonsi]: " AUTO_CARDS
    AUTO_CARDS="${AUTO_CARDS:-amdgpu radeonsi}"
fi
VIDEO_CARDS="${AUTO_CARDS}"

check_linux_firmware

# ── Apply settings ────────────────────────────────────────────────────────────
info "Configuring ${MAKE_CONF} for KDE Plasma 6…"

set_var "CFLAGS"          "-march=${MARCH} -O2 -pipe"
set_var "CXXFLAGS"        "\${CFLAGS}"
if [[ -n "${CPU_FLAGS}" ]]; then
    set_var "CPU_FLAGS_X86" "${CPU_FLAGS}"
fi
set_var "USE"             "X wayland dbus elogind -systemd pipewire sound-server kde plasma alsa bluetooth networkmanager policykit vulkan vaapi"
set_var "VIDEO_CARDS"     "${VIDEO_CARDS}"
set_var "INPUT_DEVICES"   "libinput"
set_var "MAKEOPTS"        "-j${NCPUS} -l${NCPUS}"
set_var "ACCEPT_KEYWORDS" "~amd64"

if ! grep -q "^ACCEPT_LICENSE=" "${MAKE_CONF}"; then
    echo 'ACCEPT_LICENSE="*"' >> "${MAKE_CONF}"
fi

if ! grep -q "^FEATURES=" "${MAKE_CONF}"; then
    echo 'FEATURES="parallel-fetch candy"' >> "${MAKE_CONF}"
fi

# ── Validate ──────────────────────────────────────────────────────────────────
info "Validating syntax…"
bash -n "${MAKE_CONF}" && ok "Syntax OK"

echo ""
ok "make.conf configured for KDE Plasma 6."
echo -e "  CFLAGS        = -march=${MARCH} -O2 -pipe"
[[ -n "${CPU_FLAGS}" ]] && echo -e "  CPU_FLAGS_X86 = ${CPU_FLAGS}"
echo -e "  USE           = X wayland dbus elogind -systemd pipewire sound-server kde plasma alsa bluetooth networkmanager policykit vulkan vaapi"
echo -e "  VIDEO_CARDS   = ${VIDEO_CARDS}"
echo -e "  MAKEOPTS      = -j${NCPUS} -l${NCPUS}"
echo ""
info "Next step: sudo bash scripts/kde/02-install-plasma.sh"

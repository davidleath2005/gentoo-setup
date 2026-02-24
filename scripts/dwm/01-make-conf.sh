#!/usr/bin/env bash
# =============================================================================
# scripts/dwm/01-make-conf.sh
# Description: Configure /etc/portage/make.conf for a minimal Xorg/suckless
#              setup.  Optimised for Zen 5 (9800X3D) + RDNA 3 (RX 7800 XT).
# Usage:       sudo bash scripts/dwm/01-make-conf.sh
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
echo -e "  ${GREEN}Configure make.conf — DWM / Suckless${NC}"
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

# ── CPU core count ────────────────────────────────────────────────────────────
NCPUS=$(nproc)
info "Detected ${NCPUS} CPU thread(s)"

# ── CPU architecture ─────────────────────────────────────────────────────────
RAW_MARCH=$(detect_cpu_arch)
info "Detected CPU microarchitecture: ${RAW_MARCH}"
MARCH="${RAW_MARCH}"
check_gcc_version "${RAW_MARCH}" "native"
info "Using -march=${MARCH}"

# ── CPU_FLAGS_X86 ─────────────────────────────────────────────────────────────
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
    warn "Could not auto-detect GPU."
    echo "    AMD (RDNA 3):  amdgpu radeonsi"
    echo "    NVIDIA:        nvidia"
    echo "    Intel:         intel i965 iris"
    read -rp "  Enter VIDEO_CARDS value [amdgpu radeonsi]: " AUTO_CARDS
    AUTO_CARDS="${AUTO_CARDS:-amdgpu radeonsi}"
fi
VIDEO_CARDS="${AUTO_CARDS}"

# ── linux-firmware ────────────────────────────────────────────────────────────
check_linux_firmware

# ── USE flags for minimal suckless + RDNA 3 ──────────────────────────────────
# elogind dbus: required for seat management, polkit, power management
# vulkan vaapi: GPU acceleration (RDNA 3)
# alsa pipewire: modern audio stack (PipeWire replaces PulseAudio)
# sound-server: enables PipeWire's pipewire-pulse compat layer
# -systemd: OpenRC system
USE_FLAGS="X elogind dbus -systemd -gnome -kde -plasma alsa pipewire sound-server vulkan vaapi"

# ── Apply ─────────────────────────────────────────────────────────────────────
info "Configuring ${MAKE_CONF}…"

set_var "CFLAGS"          "-march=${MARCH} -O2 -pipe"
set_var "CXXFLAGS"        "\${CFLAGS}"
if [[ -n "${CPU_FLAGS}" ]]; then
    set_var "CPU_FLAGS_X86" "${CPU_FLAGS}"
fi
set_var "USE"             "${USE_FLAGS}"
set_var "VIDEO_CARDS"     "${VIDEO_CARDS}"
set_var "INPUT_DEVICES"   "libinput"
set_var "MAKEOPTS"        "-j${NCPUS} -l${NCPUS}"
set_var "ACCEPT_KEYWORDS" "~amd64"

if ! grep -q "^ACCEPT_LICENSE=" "${MAKE_CONF}"; then
    info "Appending ACCEPT_LICENSE"
    echo 'ACCEPT_LICENSE="*"' >> "${MAKE_CONF}"
else
    ok "ACCEPT_LICENSE already present"
fi

# ── Ensure FEATURES has useful defaults ───────────────────────────────────────
if ! grep -q "^FEATURES=" "${MAKE_CONF}"; then
    info "Appending FEATURES"
    echo 'FEATURES="parallel-fetch candy"' >> "${MAKE_CONF}"
else
    ok "FEATURES already present"
fi

# ── Validate ──────────────────────────────────────────────────────────────────
info "Validating ${MAKE_CONF} syntax…"
bash -n "${MAKE_CONF}" && ok "Syntax OK"

echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
ok "make.conf configured for DWM / Suckless"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  CFLAGS          = -march=${MARCH} -O2 -pipe"
echo -e "  CXXFLAGS        = \${CFLAGS}"
[[ -n "${CPU_FLAGS}" ]] && echo -e "  CPU_FLAGS_X86   = ${CPU_FLAGS}"
echo -e "  USE             = ${USE_FLAGS}"
echo -e "  VIDEO_CARDS     = ${VIDEO_CARDS}"
echo -e "  INPUT_DEVICES   = libinput"
echo -e "  MAKEOPTS        = -j${NCPUS} -l${NCPUS}"
echo -e "  ACCEPT_KEYWORDS = ~amd64"
echo ""
info "Next step: sudo bash scripts/dwm/02-deps.sh"

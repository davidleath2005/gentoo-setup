#!/usr/bin/env bash
# =============================================================================
# scripts/common/system-info.sh
# Description: Display important system information — boot config, Portage
#              profile, make.conf, kernel, services, hardware, and more.
#              Supports EFI stub / efibootmgr / systemd-boot / GRUB.
# Usage:       bash scripts/common/system-info.sh       (user or root)
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=detect-hardware.sh
source "${SCRIPT_DIR}/detect-hardware.sh"

DONE="${GREEN}●${NC}"
TODO="${RED}○${NC}"

section() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  ${BOLD}${GREEN}$*${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# ── Hardware Overview ─────────────────────────────────────────────────────────
section "Hardware"

if [[ -r /proc/cpuinfo ]]; then
    cpu_model=$(grep -m1 "^model name" /proc/cpuinfo | cut -d: -f2 | xargs)
    cpu_cores=$(nproc)
    cpu_family=$(grep -m1 "^cpu family" /proc/cpuinfo | awk -F': ' '{print $2}' | tr -d '[:space:]')
    echo -e "  CPU:         ${cpu_model} (${cpu_cores} threads)"
    # Zen generation hint
    case "${cpu_family}" in
        26) echo -e "  Arch:        Zen 5 (znver5)" ;;
        25) echo -e "  Arch:        Zen 3/4" ;;
        23) echo -e "  Arch:        Zen / Zen+ / Zen 2" ;;
    esac
fi

mem_total=$(grep -m1 MemTotal /proc/meminfo 2>/dev/null | awk '{printf "%.1f GB", $2/1024/1024}')
echo -e "  RAM:         ${mem_total}"

if command -v lspci &>/dev/null; then
    gpu=$(lspci 2>/dev/null | grep -i "VGA\|3D\|Display" | head -1 | sed 's/.*: //')
    echo -e "  GPU:         ${gpu:-not detected}"
    # RDNA generation hint
    if echo "${gpu}" | grep -qi "7[78]00\|7900\|7600"; then
        echo -e "  GPU Arch:    RDNA 3 (Navi 3x)"
    fi
fi

if [[ -b /dev/nvme0n1 ]] || [[ -b /dev/sda ]]; then
    echo -e "  Storage:"
    lsblk -dno NAME,SIZE,TYPE,MODEL 2>/dev/null | grep -E "disk|nvme" | while read -r line; do
        echo -e "    ${line}"
    done
fi

# Motherboard
if [[ -r /sys/class/dmi/id/board_vendor ]]; then
    board_vendor=$(cat /sys/class/dmi/id/board_vendor 2>/dev/null)
    board_name=$(cat /sys/class/dmi/id/board_name 2>/dev/null)
    echo -e "  Board:       ${board_vendor} ${board_name}"
fi

# ── Date/Time ─────────────────────────────────────────────────────────────────
section "Date / Time"
echo -e "  System:      $(date '+%Y-%m-%d %H:%M:%S %Z')"
echo -e "  HW clock:    $(hwclock --show 2>/dev/null || echo 'unavailable (need root)')"
local_year=$(date +%Y)
if [[ "${local_year}" -lt 2025 ]]; then
    echo -e "  ${TODO} ${RED}Date looks incorrect!${NC} SSL/TLS sync will fail."
    echo -e "       Fix with: date -s 'YYYY-MM-DD HH:MM:SS' && hwclock --systohc"
else
    echo -e "  ${DONE} Date looks correct"
fi

# ── Boot Method ───────────────────────────────────────────────────────────────
section "Boot Configuration"

# UEFI vs BIOS
if [[ -d /sys/firmware/efi ]]; then
    echo -e "  ${DONE} Firmware:     UEFI"
    echo -e "  EFI vars:    /sys/firmware/efi/efivars ($(ls /sys/firmware/efi/efivars 2>/dev/null | wc -l) entries)"
else
    echo -e "  ${TODO} Firmware:     BIOS / Legacy"
fi

# Detect boot method
BOOT_METHOD=$(detect_boot_method)
echo -e "  Boot method: ${BOOT_METHOD}"

# ESP mount
for mp in /boot/efi /efi /boot; do
    if mountpoint -q "${mp}" 2>/dev/null; then
        esp_size=$(df -h "${mp}" 2>/dev/null | tail -1 | awk '{print $2 " total, " $4 " free"}')
        echo -e "  ESP:         ${mp} (${esp_size})"
        break
    fi
done

# EFI boot entries
if command -v efibootmgr &>/dev/null && [[ -d /sys/firmware/efi ]]; then
    echo ""
    echo "  EFI boot entries:"
    efibootmgr 2>/dev/null | grep -E "^Boot[0-9]" | while read -r line; do
        echo "    ${line}"
    done
fi

# Kernel images in /boot
if ls /boot/vmlinuz* &>/dev/null 2>&1; then
    echo ""
    echo "  Kernel images in /boot:"
    ls -1 /boot/vmlinuz* 2>/dev/null | while read -r f; do
        fsize=$(stat --printf="%s" "${f}" 2>/dev/null | awk '{printf "%.1f MB", $1/1024/1024}')
        echo "    ${f} (${fsize})"
    done
fi

# ── Kernel ────────────────────────────────────────────────────────────────────
section "Kernel"

echo -e "  Running:     $(uname -r)"
if [[ -d /usr/src/linux ]]; then
    src_ver=$(readlink -f /usr/src/linux 2>/dev/null | xargs basename 2>/dev/null || echo "unknown")
    echo -e "  Source:      /usr/src/linux → ${src_ver}"
fi

if command -v eselect &>/dev/null && eselect kernel list &>/dev/null 2>&1; then
    echo ""
    echo "  Installed kernels:"
    eselect kernel list 2>/dev/null | while read -r line; do
        echo "    ${line}"
    done
fi

# ── Portage Profile ──────────────────────────────────────────────────────────
section "Portage Profile"

if command -v eselect &>/dev/null; then
    profile=$(eselect profile show 2>/dev/null | tail -1 | xargs)
    echo -e "  Active:      ${profile}"
else
    echo -e "  ${YELLOW}eselect not available${NC}"
fi

# ── make.conf ─────────────────────────────────────────────────────────────────
section "make.conf (/etc/portage/make.conf)"

MAKE_CONF="/etc/portage/make.conf"
if [[ -r "${MAKE_CONF}" ]]; then
    for var in CFLAGS USE VIDEO_CARDS INPUT_DEVICES MAKEOPTS ACCEPT_KEYWORDS CPU_FLAGS_X86 ACCEPT_LICENSE FEATURES; do
        val=$(grep "^${var}=" "${MAKE_CONF}" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"')
        if [[ -n "${val}" ]]; then
            printf "  %-18s %s\n" "${var}:" "${val}"
        fi
    done
else
    warn "Cannot read ${MAKE_CONF}"
fi

# ── OpenRC Services ──────────────────────────────────────────────────────────
section "OpenRC Services"

if command -v rc-update &>/dev/null; then
    for svc in elogind dbus cronie display-manager NetworkManager sshd; do
        if rc-update show 2>/dev/null | grep -q "${svc}"; then
            echo -e "  ${DONE} ${svc} — enabled"
        else
            echo -e "  ${TODO} ${svc} — not enabled"
        fi
    done
    echo ""
    echo "  All default runlevel:"
    rc-update show default 2>/dev/null | head -20 || true
    echo ""
    echo "  Boot runlevel:"
    rc-update show boot 2>/dev/null | head -10 || true
else
    warn "rc-update not available (not on OpenRC?)"
fi

# ── User & Groups ────────────────────────────────────────────────────────────
section "User & Groups"

echo -e "  Current:     $(whoami) (UID ${EUID})"
echo -e "  Groups:      $(id -nG)"
if [[ -n "${SUDO_USER:-}" ]]; then
    echo -e "  Invoker:     ${SUDO_USER}"
    echo -e "  Groups:      $(id -nG "${SUDO_USER}" 2>/dev/null || echo 'N/A')"
fi

# ── Package Stats ────────────────────────────────────────────────────────────
section "Package Stats"

if command -v qlist &>/dev/null; then
    total=$(qlist -CI 2>/dev/null | wc -l)
    echo -e "  Installed:   ${total} packages"
fi

if [[ -f /var/lib/portage/world ]]; then
    world_count=$(wc -l < /var/lib/portage/world)
    echo -e "  World set:   ${world_count} entries"
fi

# Disk usage
echo ""
echo "  Disk usage:"
df -h / /boot /home /var 2>/dev/null | awk 'NR==1||/\// {printf "    %-20s %6s used / %6s total (%s)\n", $6, $3, $2, $5}' || true

# ── Suckless Status ──────────────────────────────────────────────────────────
section "Suckless Tools"

for bin in dwm st dmenu picom dunst xwallpaper xclip scrot brightnessctl; do
    if command -v "${bin}" &>/dev/null; then
        ver=$("${bin}" -v 2>&1 | head -1 || echo "installed")
        echo -e "  ${DONE} ${bin}: ${ver}"
    else
        echo -e "  ${TODO} ${bin}: not installed"
    fi
done

# ── Key Config Files ─────────────────────────────────────────────────────────
section "Key Configuration Files"

files=(
    "/etc/portage/make.conf"
    "/etc/portage/package.accept_keywords"
    "/etc/portage/package.use"
    "/etc/fstab"
    "/etc/locale.gen"
    "/etc/conf.d/display-manager"
    "${HOME}/.xinitrc"
    "${HOME}/.bash_profile"
)

for f in "${files[@]}"; do
    if [[ -e "${f}" ]]; then
        if [[ -d "${f}" ]]; then
            echo -e "  ${DONE} ${f}/ (directory)"
        else
            size=$(stat --printf="%s" "${f}" 2>/dev/null || echo "?")
            echo -e "  ${DONE} ${f} (${size} bytes)"
        fi
    else
        echo -e "  ${TODO} ${f} — missing"
    fi
done

# ── Audio Stack ───────────────────────────────────────────────────────────────
section "Audio"

# ALSA devices
if [[ -d /proc/asound ]] && [[ -f /proc/asound/cards ]]; then
    echo "  ALSA cards:"
    while IFS= read -r line; do
        echo "    ${line}"
    done < /proc/asound/cards
else
    echo -e "  ${TODO} No ALSA sound devices detected"
    echo "       Check kernel: CONFIG_SND_HDA_INTEL=m, CONFIG_SND_HDA_CODEC_REALTEK=m"
fi

# ALSA packages
for pkg in media-libs/alsa-lib media-sound/alsa-utils media-plugins/alsa-plugins; do
    if pkg_installed "${pkg}" 2>/dev/null; then
        echo -e "  ${DONE} ${pkg}"
    else
        echo -e "  ${TODO} ${pkg} — not installed"
    fi
done

# PipeWire
echo ""
for pkg in media-video/pipewire media-video/wireplumber; do
    if pkg_installed "${pkg}" 2>/dev/null; then
        echo -e "  ${DONE} ${pkg}"
    else
        echo -e "  ${TODO} ${pkg} — not installed"
    fi
done

# PipeWire runtime status (user-space — may not be running as root)
if command -v wpctl &>/dev/null; then
    echo ""
    echo "  WirePlumber status:"
    wpctl status 2>/dev/null | head -15 | while IFS= read -r line; do
        echo "    ${line}"
    done || echo "    (not running — PipeWire runs in user-space)"
fi

# Volume
if command -v wpctl &>/dev/null; then
    vol=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null || echo "N/A (not running)")
    echo -e "  Volume:      ${vol}"
elif command -v amixer &>/dev/null; then
    vol=$(amixer get Master 2>/dev/null | grep -oP '\[\d+%\]' | head -1 || echo "N/A")
    echo -e "  Volume:      ${vol} (via ALSA)"
fi

# ── Useful Commands ──────────────────────────────────────────────────────────
section "Quick Reference"

echo "  Update system:          emerge --ask --verbose --update --deep --newuse @world"
echo "  Sync repos:             emaint sync -a"
echo "  Install package:        emerge --ask <category/name>"
echo "  Search packages:        emerge --search <name>"
echo "  Remove orphans:         emerge --ask --depclean"
echo "  Fix broken deps:        revdep-rebuild"
echo "  Clean distfiles:        eclean distfiles"
echo "  Check USE flags:        equery uses <package>"
echo "  List installed:         qlist -I <pattern>"
echo "  Kernel update:          sudo bash scripts/common/kernel-update.sh"
echo "  EFI boot entries:       efibootmgr -v"
echo ""

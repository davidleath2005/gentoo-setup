#!/usr/bin/env bash
# =============================================================================
# scripts/common/kernel-update.sh
# Description: Update to the latest kernel sources, build, and update the
#              bootloader.  Detects EFI stub / efibootmgr / systemd-boot / GRUB
#              and acts accordingly.
# Usage:       sudo bash scripts/common/kernel-update.sh
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=detect-hardware.sh
source "${SCRIPT_DIR}/detect-hardware.sh"

if [[ "${EUID}" -ne 0 ]]; then
    error "This script must be run as root."
    exit 1
fi

echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  ${GREEN}Gentoo Kernel Update${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  Running kernel : $(uname -r)"

# ── Detect boot method ───────────────────────────────────────────────────────
BOOT_METHOD=$(detect_boot_method)
if [[ -d /sys/firmware/efi ]]; then
    info "System booted via UEFI"
else
    info "System booted via BIOS/Legacy"
fi
echo -e "  Boot method    : ${BOOT_METHOD}"

# ── Check current kernel source ───────────────────────────────────────────────
if [[ -L /usr/src/linux ]]; then
    current_src=$(readlink -f /usr/src/linux | xargs basename)
    echo -e "  Source symlink : /usr/src/linux → ${current_src}"
fi

# ── Check EFI/ESP mount ──────────────────────────────────────────────────────
ESP_DIR=""
if [[ -d /sys/firmware/efi ]]; then
    if mountpoint -q /boot/efi 2>/dev/null; then
        ESP_DIR="/boot/efi"
    elif mountpoint -q /boot 2>/dev/null; then
        ESP_DIR="/boot"
    elif mountpoint -q /efi 2>/dev/null; then
        ESP_DIR="/efi"
    fi
    if [[ -n "${ESP_DIR}" ]]; then
        echo -e "  ESP mounted at : ${ESP_DIR}"
    else
        warn "EFI system detected but no ESP mount found at /boot/efi, /boot, or /efi"
        warn "Make sure your ESP is mounted before updating the bootloader"
    fi
fi
echo ""

# ── 1. Sync Portage ──────────────────────────────────────────────────────────
info "Syncing Portage tree…"
emaint sync -a
ok "Portage tree synced"

# ── 2. Update linux-firmware ─────────────────────────────────────────────────
info "Updating linux-firmware (critical for RDNA 3 / Zen 5)…"
emerge --ask --update sys-kernel/linux-firmware
ok "linux-firmware up-to-date"

# ── 3. Detect and update kernel sources ──────────────────────────────────────
KERNEL_PKG=""
if command -v qlist &>/dev/null; then
    if qlist -I sys-kernel/gentoo-sources &>/dev/null 2>&1; then
        KERNEL_PKG="sys-kernel/gentoo-sources"
    elif qlist -I sys-kernel/gentoo-kernel &>/dev/null 2>&1; then
        KERNEL_PKG="sys-kernel/gentoo-kernel"
    elif qlist -I sys-kernel/gentoo-kernel-bin &>/dev/null 2>&1; then
        KERNEL_PKG="sys-kernel/gentoo-kernel-bin"
    fi
fi

if [[ -z "${KERNEL_PKG}" ]]; then
    warn "Could not auto-detect installed kernel package."
    echo ""
    echo "  1) sys-kernel/gentoo-sources       (manual config, most control)"
    echo "  2) sys-kernel/gentoo-kernel         (dist-kernel, auto-configured)"
    echo "  3) sys-kernel/gentoo-kernel-bin     (prebuilt binary kernel)"
    read -rp "  Select kernel package [1/2/3]: " kc
    case "${kc}" in
        2) KERNEL_PKG="sys-kernel/gentoo-kernel" ;;
        3) KERNEL_PKG="sys-kernel/gentoo-kernel-bin" ;;
        *) KERNEL_PKG="sys-kernel/gentoo-sources" ;;
    esac
fi

info "Updating ${KERNEL_PKG}…"
emerge --ask --update "${KERNEL_PKG}"
ok "${KERNEL_PKG} updated"

# ── 4. Select latest kernel ──────────────────────────────────────────────────
info "Available kernel sources:"
eselect kernel list

latest=$(eselect kernel list 2>/dev/null | tail -1 | awk '{print $1}' | tr -d '[]')
if [[ -n "${latest}" ]]; then
    read -rp "  Select kernel number [${latest}]: " kn
    kn="${kn:-${latest}}"
    eselect kernel set "${kn}"
    ok "Kernel source set to: $(eselect kernel show 2>/dev/null | tail -1 | xargs)"
fi

# ── 5. Build kernel (gentoo-sources only) ─────────────────────────────────────
if [[ "${KERNEL_PKG}" == "sys-kernel/gentoo-sources" ]]; then
    echo ""
    echo -e "  ${CYAN}Kernel build options:${NC}"
    echo "    1) Use existing .config (make oldconfig && make) — recommended for updates"
    echo "    2) Open menuconfig (manual configuration)"
    echo "    3) Copy running kernel config (zcat /proc/config.gz && make oldconfig)"
    echo "    4) Skip kernel build (I'll do it manually)"
    read -rp "  Select [1/2/3/4]: " build_choice
    build_choice="${build_choice:-1}"

    cd /usr/src/linux
    NCPUS=$(nproc)

    case "${build_choice}" in
        1)
            if [[ -f .config ]]; then
                info "Running make oldconfig…"
                make oldconfig
            else
                warn "No .config found — trying /proc/config.gz…"
                if [[ -f /proc/config.gz ]]; then
                    zcat /proc/config.gz > .config
                    make oldconfig
                else
                    warn "No config source found — running make defconfig"
                    make defconfig
                fi
            fi
            info "Building kernel with -j${NCPUS}…"
            warn "This will take some time."
            make -j"${NCPUS}"
            make modules_install
            make install
            ok "Kernel compiled and installed"
            ;;
        2)
            if [[ ! -f .config ]]; then
                if [[ -f /proc/config.gz ]]; then
                    zcat /proc/config.gz > .config
                fi
            fi
            info "Opening menuconfig…"
            make menuconfig
            read -rp "  Build now? [Y/n]: " yn
            yn="${yn:-Y}"
            if [[ ! "${yn}" =~ ^[Nn]$ ]]; then
                make -j"${NCPUS}"
                make modules_install
                make install
                ok "Kernel compiled and installed"
            fi
            ;;
        3)
            if [[ -f /proc/config.gz ]]; then
                info "Copying running kernel config…"
                zcat /proc/config.gz > .config
                make oldconfig
                make -j"${NCPUS}"
                make modules_install
                make install
                ok "Kernel compiled and installed"
            else
                error "/proc/config.gz not available. Enable IKCONFIG_PROC in your kernel."
                error "Try option 1 or 2 instead."
            fi
            ;;
        4)
            info "Skipping kernel build."
            ;;
    esac
else
    info "${KERNEL_PKG} handles compilation automatically via installkernel."
fi

# ── 6. Rebuild kernel modules ────────────────────────────────────────────────
if command -v emerge &>/dev/null; then
    info "Rebuilding external kernel modules (@module-rebuild)…"
    emerge --ask @module-rebuild 2>/dev/null || true
fi

# ── 7. Update bootloader ────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}──────────────────────────────────────────────────────────${NC}"
info "Updating bootloader (${BOOT_METHOD})…"
echo -e "${CYAN}──────────────────────────────────────────────────────────${NC}"

case "${BOOT_METHOD}" in
    grub-efi|grub-bios)
        if command -v grub-mkconfig &>/dev/null; then
            grub-mkconfig -o /boot/grub/grub.cfg
            ok "GRUB configuration updated"
        fi
        ;;
    systemd-boot)
        if command -v bootctl &>/dev/null; then
            bootctl update
            ok "systemd-boot updated"
            info "Verify your loader entries in ${ESP_DIR}/loader/entries/"
        fi
        ;;
    efistub)
        info "EFI stub boot detected — updating EFI boot entry via efibootmgr"

        # Detect the kernel image in /boot or ESP
        KERNEL_IMG=""
        for candidate in /boot/vmlinuz /boot/vmlinuz-* "${ESP_DIR:-/boot/efi}"/vmlinuz*; do
            if [[ -f "${candidate}" ]]; then
                KERNEL_IMG="${candidate}"
            fi
        done

        if [[ -z "${KERNEL_IMG}" ]]; then
            warn "Could not find kernel image in /boot or ESP"
            info "Copy your kernel manually:  cp /usr/src/linux/arch/x86/boot/bzImage ${ESP_DIR:-/boot/efi}/vmlinuz"
        else
            ok "Latest kernel image: ${KERNEL_IMG}"
        fi

        # Show current EFI entries
        echo ""
        info "Current EFI boot entries:"
        efibootmgr -v 2>/dev/null | head -20 || true
        echo ""
        info "If you need to create/update an EFI entry, use:"
        echo "  efibootmgr --create --disk /dev/nvme0n1 --part 1 \\"
        echo "    --label 'Gentoo' --loader '\\vmlinuz' \\"
        echo "    --unicode 'root=PARTUUID=<your-partuuid> ro'"
        echo ""
        info "Or copy the built kernel to your ESP:"
        echo "  cp /usr/src/linux/arch/x86/boot/bzImage ${ESP_DIR:-/boot/efi}/vmlinuz"
        ;;
    efi-unknown)
        warn "UEFI system but no known bootloader detected."
        info "You may be using:"
        echo "   • EFI stub boot (efibootmgr)"
        echo "   • systemd-boot (bootctl)"
        echo "   • rEFInd"
        echo ""
        info "Copy the kernel to your ESP manually and update your bootloader."
        ;;
    *)
        warn "Unknown boot configuration — update your bootloader manually."
        ;;
esac

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
ok "Kernel update complete."
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  Running      : $(uname -r)"
echo -e "  Selected     : $(eselect kernel show 2>/dev/null | tail -1 | xargs)"
echo -e "  Boot method  : ${BOOT_METHOD}"
echo ""
info "Reboot to use the new kernel."
echo ""

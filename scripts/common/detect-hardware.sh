#!/usr/bin/env bash
# =============================================================================
# scripts/common/detect-hardware.sh
# Description: Shared hardware detection helpers sourced by make.conf scripts.
#              Optimised for AMD Zen 5 (9800X3D) + RDNA 3 (RX 7800 XT) + B870.
# Usage:       source "$(dirname "$0")/../common/detect-hardware.sh"
# =============================================================================

# ── Colour helpers ────────────────────────────────────────────────────────────
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'
BOLD='\033[1m'; NC='\033[0m'
info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
ok()    { echo -e "${GREEN}[ OK ]${NC}  $*"; }
error() { echo -e "${RED}[ERR ]${NC}  $*" >&2; }

# ── Helper: set or replace a variable in make.conf ────────────────────────────
# Usage: set_var VAR_NAME "value string"  (MAKE_CONF must be set by caller)
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

# ── GPU detection ─────────────────────────────────────────────────────────────
# Prints the appropriate VIDEO_CARDS value, or empty string on failure.
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

# ── CPU microarchitecture detection ──────────────────────────────────────────
# Reads /proc/cpuinfo and returns the best -march= value for GCC.
# AMD Ryzen 9800X3D = Zen 5, Family 0x1A (26).
detect_cpu_arch() {
    local cpu_family cpu_model vendor march="native"

    if [[ -r /proc/cpuinfo ]]; then
        vendor=$(grep -m1 "^vendor_id" /proc/cpuinfo | awk -F': ' '{print $2}' | tr -d '[:space:]')
        cpu_family=$(grep -m1 "^cpu family" /proc/cpuinfo | awk -F': ' '{print $2}' | tr -d '[:space:]')
        cpu_model=$(grep -m1 "^model[[:space:]]" /proc/cpuinfo | awk -F': ' '{print $2}' | tr -d '[:space:]')

        if [[ "${vendor}" == "AuthenticAMD" ]]; then
            # Family 26 (0x1A) = Zen 5 (Ryzen 9000 / 9800X3D) → znver5
            # Family 25 (0x19) = Zen 3 / Zen 4 (model >= 0x60 → Zen 4)
            # Family 23 (0x17) = Zen / Zen+ / Zen 2
            case "${cpu_family}" in
                26) march="znver5" ;;
                25)
                    if [[ "${cpu_model}" -ge 96 ]] 2>/dev/null; then
                        march="znver4"
                    else
                        march="znver3"
                    fi
                    ;;
                23)
                    if [[ "${cpu_model}" -ge 48 ]] 2>/dev/null; then
                        march="znver2"
                    else
                        march="znver1"
                    fi
                    ;;
                *) march="native" ;;
            esac
        elif [[ "${vendor}" == "GenuineIntel" ]]; then
            march="native"
        fi
    fi

    echo "${march}"
}

# ── GCC version check ─────────────────────────────────────────────────────────
# Verifies GCC supports the requested -march flag.
# Falls back to a safer alternative and warns the user.
# Sets the global MARCH variable (may be modified on fallback).
check_gcc_version() {
    local requested_march="$1"
    local fallback="${2:-native}"

    if ! command -v gcc &>/dev/null; then
        warn "gcc not found — cannot verify -march support; using -march=${fallback}"
        MARCH="${fallback}"
        return
    fi

    # Try compiling a trivial program with the requested -march flag
    if echo 'int main(){}' | gcc -x c -march="${requested_march}" -o /dev/null - 2>/dev/null; then
        MARCH="${requested_march}"
    else
        local gcc_ver
        gcc_ver=$(gcc -dumpfullversion 2>/dev/null || gcc -dumpversion 2>/dev/null)
        warn "GCC ${gcc_ver} does not support -march=${requested_march}"

        # Zen 5 fallback chain: znver5 → znver4 → znver3 → native
        if [[ "${requested_march}" == "znver5" ]]; then
            warn "Trying znver4 fallback for Zen 5 CPU…"
            if echo 'int main(){}' | gcc -x c -march=znver4 -o /dev/null - 2>/dev/null; then
                MARCH="znver4"
                warn "Using -march=znver4 (upgrade GCC for full znver5 support)"
                return
            fi
            warn "Trying znver3 fallback…"
            if echo 'int main(){}' | gcc -x c -march=znver3 -o /dev/null - 2>/dev/null; then
                MARCH="znver3"
                warn "Using -march=znver3 (upgrade GCC for full znver5 support)"
                return
            fi
        fi

        warn "Falling back to -march=${fallback}"
        MARCH="${fallback}"
    fi
}

# ── CPU_FLAGS_X86 detection ───────────────────────────────────────────────────
# Installs cpuid2cpuflags if missing, then uses it to detect CPU_FLAGS_X86.
# Falls back to parsing /proc/cpuinfo flags and mapping to Gentoo names.
# Sets the global CPU_FLAGS variable.
detect_cpu_flags() {
    # Install cpuid2cpuflags if it is not already present
    if ! command -v cpuid2cpuflags &>/dev/null; then
        warn "cpuid2cpuflags not found — installing app-portage/cpuid2cpuflags…"
        if [[ "${EUID}" -ne 0 ]]; then
            warn "Not running as root; cannot install cpuid2cpuflags — falling back to /proc/cpuinfo"
        elif emerge --ask app-portage/cpuid2cpuflags; then
            ok "app-portage/cpuid2cpuflags installed"
        else
            warn "emerge failed — falling back to /proc/cpuinfo"
        fi
    fi

    # Use cpuid2cpuflags if now available
    if command -v cpuid2cpuflags &>/dev/null; then
        CPU_FLAGS=$(cpuid2cpuflags | sed 's/^CPU_FLAGS_X86: //')
        ok "CPU_FLAGS_X86 detected via cpuid2cpuflags"
        return
    fi

    # Fallback: map /proc/cpuinfo flags to Gentoo CPU_FLAGS_X86 names
    # Zen 5 (9800X3D) supports: AES AVX AVX2 AVX512F/DQ/CD/BW/VL/VBMI/VBMI2/VNNI/BITALG
    #   BMI1 BMI2 F16C FMA3 MMX MMXEXT PCLMUL POPCNT RDRAND SHA SSE SSE2 SSE3 SSE4_1 SSE4_2 SSE4A SSSE3
    info "Detecting CPU_FLAGS_X86 from /proc/cpuinfo…"
    local proc_flags=""
    if [[ -r /proc/cpuinfo ]]; then
        proc_flags=$(grep -m1 "^flags" /proc/cpuinfo | cut -d: -f2)
    fi

    local flags=""
    _has() { echo "${proc_flags}" | grep -qw "$1"; }

    _has aes        && flags+=" aes"
    _has avx        && flags+=" avx"
    _has avx2       && flags+=" avx2"
    _has avx512f    && flags+=" avx512f"
    _has avx512dq   && flags+=" avx512dq"
    _has avx512cd   && flags+=" avx512cd"
    _has avx512bw   && flags+=" avx512bw"
    _has avx512vl   && flags+=" avx512vl"
    _has avx512vbmi && flags+=" avx512vbmi"
    _has avx512_vbmi2 && flags+=" avx512vbmi2"
    _has avx512_vnni  && flags+=" avx512vnni"
    _has avx512_bitalg && flags+=" avx512bitalg"
    _has bmi1       && flags+=" bmi1"
    _has bmi2       && flags+=" bmi2"
    _has f16c       && flags+=" f16c"
    _has fma        && flags+=" fma3"
    _has mmx        && flags+=" mmx"
    _has mmxext     && flags+=" mmxext"
    _has pclmulqdq  && flags+=" pclmul"
    _has popcnt     && flags+=" popcnt"
    _has rdrand     && flags+=" rdrand"
    _has rdseed     && flags+=" rdseed"
    _has sha_ni     && flags+=" sha"
    _has sse        && flags+=" sse"
    _has sse2       && flags+=" sse2"
    _has pni        && flags+=" sse3"
    _has sse4_1     && flags+=" sse4_1"
    _has sse4_2     && flags+=" sse4_2"
    _has sse4a      && flags+=" sse4a"
    _has ssse3      && flags+=" ssse3"
    _has vaes       && flags+=" vaes"
    _has vpclmulqdq && flags+=" vpclmulqdq"

    CPU_FLAGS="${flags# }"

    if [[ -n "${CPU_FLAGS}" ]]; then
        ok "CPU_FLAGS_X86 detected from /proc/cpuinfo"
    else
        warn "Could not detect CPU_FLAGS_X86; leaving unset"
    fi
}

# ── linux-firmware check ──────────────────────────────────────────────────────
# Warns if sys-kernel/linux-firmware is not installed or outdated.
# Critical: RDNA 3 (Navi 32, RX 7800 XT) needs up-to-date firmware blobs.
check_linux_firmware() {
    if command -v qlist &>/dev/null && qlist -I sys-kernel/linux-firmware &>/dev/null; then
        local ver
        ver=$(qlist -I sys-kernel/linux-firmware 2>/dev/null | head -1)
        ok "sys-kernel/linux-firmware installed: ${ver}"
        info "Run 'emerge --ask --update sys-kernel/linux-firmware' to ensure RDNA 3 firmware blobs are current."
    else
        warn "sys-kernel/linux-firmware does not appear to be installed."
        warn "RDNA 3 GPUs (RX 7800 XT / Navi 32) require up-to-date firmware blobs."
        warn "Install with: emerge --ask sys-kernel/linux-firmware"
    fi
}

# ── Boot method detection ─────────────────────────────────────────────────────
# Returns: efistub, grub-efi, grub-bios, systemd-boot, refind, unknown
detect_boot_method() {
    if [[ -d /sys/firmware/efi ]]; then
        if [[ -f /boot/grub/grub.cfg ]]; then
            echo "grub-efi"
        elif command -v bootctl &>/dev/null && bootctl is-installed &>/dev/null 2>&1; then
            echo "systemd-boot"
        elif [[ -f /boot/efi/EFI/refind/refind.conf ]] || [[ -f /efi/EFI/refind/refind.conf ]]; then
            echo "refind"
        elif command -v efibootmgr &>/dev/null; then
            echo "efistub"
        else
            echo "efi-unknown"
        fi
    else
        if [[ -f /boot/grub/grub.cfg ]]; then
            echo "grub-bios"
        else
            echo "unknown"
        fi
    fi
}

# ── ESP detection ─────────────────────────────────────────────────────────────
detect_esp() {
    for mp in /boot/efi /efi /boot; do
        if mountpoint -q "${mp}" 2>/dev/null; then
            echo "${mp}"
            return
        fi
    done
    echo ""
}

# ── Date/time check ──────────────────────────────────────────────────────────
# Warns if the system clock looks wrong (>1 day from hardware clock)
check_system_clock() {
    local year
    year=$(date +%Y)
    if [[ "${year}" -lt 2025 ]]; then
        warn "System date looks incorrect: $(date)"
        warn "This can cause SSL/TLS errors with emerge sync."
        info "Set the date with:  date -s 'YYYY-MM-DD HH:MM:SS'"
        info "Or sync via NTP:    emerge --ask net-misc/ntp && ntpd -gq"
        return 1
    fi
    return 0
}

# ── Service status check ─────────────────────────────────────────────────────
# Usage: is_service_enabled <service> [runlevel]
is_service_enabled() {
    local svc="$1"
    local runlevel="${2:-default}"
    if command -v rc-update &>/dev/null; then
        rc-update show "${runlevel}" 2>/dev/null | grep -q "${svc}"
    else
        return 1
    fi
}

# ── Package installed check ──────────────────────────────────────────────────
# Usage: pkg_installed <category/name>
pkg_installed() {
    if command -v qlist &>/dev/null; then
        qlist -I "$1" &>/dev/null
    elif command -v eix &>/dev/null; then
        eix -I --exact "$1" &>/dev/null
    else
        return 1
    fi
}

# ── Hardware summary (for banner) ────────────────────────────────────────────
print_hardware_summary() {
    local cpu_model gpu_model mem_total

    if [[ -r /proc/cpuinfo ]]; then
        cpu_model=$(grep -m1 "^model name" /proc/cpuinfo | cut -d: -f2 | xargs)
    fi
    mem_total=$(grep -m1 MemTotal /proc/meminfo 2>/dev/null | awk '{printf "%.0f GB", $2/1024/1024}')
    if command -v lspci &>/dev/null; then
        gpu_model=$(lspci 2>/dev/null | grep -i "VGA\|3D\|Display" | head -1 | sed 's/.*: //' | cut -c1-60)
    fi

    echo -e "  CPU : ${cpu_model:-unknown}"
    echo -e "  GPU : ${gpu_model:-unknown}"
    echo -e "  RAM : ${mem_total:-unknown}"
}

# ── Audio stack detection ─────────────────────────────────────────────────────
# Checks if the audio stack (ALSA + PipeWire) is properly set up.
audio_configured() {
    # Check ALSA basics
    pkg_installed "media-sound/alsa-utils" 2>/dev/null || return 1
    pkg_installed "media-video/pipewire" 2>/dev/null || return 1
    return 0
}

# ── Essential services check ─────────────────────────────────────────────────
# Checks and reports on critical OpenRC services
check_essential_services() {
    local all_ok=true
    local services=("dbus:default" "elogind:boot" "cronie:default")

    for entry in "${services[@]}"; do
        local svc="${entry%%:*}"
        local rl="${entry##*:}"
        if is_service_enabled "${svc}" "${rl}"; then
            ok "${svc} enabled in ${rl} runlevel"
        else
            warn "${svc} NOT enabled in ${rl} runlevel"
            all_ok=false
        fi
    done

    if [[ "${all_ok}" == "false" ]]; then
        warn "Some essential services are not enabled. Run the DWM deps or KDE services script to fix."
    fi
}

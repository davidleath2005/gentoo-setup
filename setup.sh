#!/usr/bin/env bash
# =============================================================================
# setup.sh — Gentoo Post-Install Setup Wizard
# Description: Resumable interactive wizard that scans the system to detect
#              what is already configured and lets you pick up where you left
#              off.  Supports KDE Plasma and DWM/Suckless paths.
#
# Hardware:    AMD Ryzen 9 9800X3D · Radeon RX 7800 XT · ASRock B870 Taichi Lite
# Boot:       UEFI / EFI stub (no GRUB)
# Init:       OpenRC + elogind
#
# Usage:      sudo bash setup.sh
# =============================================================================
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=scripts/common/detect-hardware.sh
source "${REPO_DIR}/scripts/common/detect-hardware.sh"

if [[ "${EUID}" -ne 0 ]]; then
    error "This script must be run as root:  sudo bash setup.sh"
    exit 1
fi

# ═════════════════════════════════════════════════════════════════════════════
# TERMINAL LAYOUT — dynamic width
# ═════════════════════════════════════════════════════════════════════════════
COLS=$(tput cols 2>/dev/null || echo 80)
[[ "${COLS}" -lt 60 ]] && COLS=60
[[ "${COLS}" -gt 120 ]] && COLS=120

# ── Drawing helpers ───────────────────────────────────────────────────────────
DIM='\033[2m'
REVERSE='\033[7m'

hr() {
    # Full-width horizontal rule
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
    # Center text within terminal width
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

right_pad() {
    # Print text left-aligned with right padding
    local text="$1"
    echo -e "  ${text}"
}

# ── Status markers ────────────────────────────────────────────────────────────
DONE="${GREEN}● DONE${NC}"
TODO="${RED}○ TODO${NC}"
INFO="${CYAN}◆${NC}"

status_label() {
    if "$1" 2>/dev/null; then
        echo -e "${GREEN}● DONE${NC}"
    else
        echo -e "${RED}○ TODO${NC}"
    fi
}

status_dot() {
    if "$1" 2>/dev/null; then
        echo -e "${GREEN}●${NC}"
    else
        echo -e "${RED}○${NC}"
    fi
}

# ═════════════════════════════════════════════════════════════════════════════
# STATUS DETECTION — scan the system
# ═════════════════════════════════════════════════════════════════════════════
make_conf_configured() {
    local mc="/etc/portage/make.conf"
    [[ -f "${mc}" ]] && grep -q "^CFLAGS=" "${mc}" && grep -q "^VIDEO_CARDS=" "${mc}" && grep -q "^USE=" "${mc}"
}

xorg_installed() {
    pkg_installed "x11-base/xorg-server"
}

suckless_built() {
    command -v dwm &>/dev/null && command -v st &>/dev/null && command -v dmenu &>/dev/null
}

xinitrc_exists() {
    local user_home
    user_home=$(eval echo "~${DESKTOP_USER:-root}")
    [[ -f "${user_home}/.xinitrc" ]]
}

kde_installed() {
    pkg_installed "kde-plasma/plasma-meta" 2>/dev/null || pkg_installed "kde-plasma/plasma-desktop" 2>/dev/null
}

services_enabled() {
    is_service_enabled "dbus" "default" && is_service_enabled "elogind" "boot"
}

cronie_enabled() {
    is_service_enabled "cronie" "default"
}

date_looks_ok() {
    local year
    year=$(date +%Y)
    [[ "${year}" -ge 2025 ]]
}

# ═════════════════════════════════════════════════════════════════════════════
# BANNER — full-width, colourful header
# ═════════════════════════════════════════════════════════════════════════════
show_banner() {
    clear
    echo ""
    hr
    echo ""
    center "G E N T O O   S E T U P   W I Z A R D" "${BOLD}${GREEN}"
    center "AMD Ryzen 9 9800X3D  ·  Radeon RX 7800 XT  ·  B870 Taichi" "${DIM}"
    echo ""
    hr
    echo ""

    # ── System status panel ───────────────────────────────────────────────────
    center "── System Status ──" "${BOLD}${CYAN}"
    echo ""

    local bm
    bm=$(detect_boot_method)

    # Left-aligned status rows with coloured dots
    printf "  ${CYAN}%-20s${NC}" "Date / Time"
    if date_looks_ok; then
        echo -e "${GREEN}●${NC}  $(date '+%a %Y-%m-%d  %H:%M %Z')"
    else
        echo -e "${RED}●${NC}  ${RED}$(date '+%Y-%m-%d %H:%M')${NC}  ← clock may be wrong"
    fi

    printf "  ${CYAN}%-20s${NC}" "Boot Method"
    echo -e "${INFO}  ${bm}"

    printf "  ${CYAN}%-20s${NC}" "Firmware"
    if [[ -d /sys/firmware/efi ]]; then
        echo -e "${GREEN}●${NC}  UEFI"
    else
        echo -e "${YELLOW}●${NC}  BIOS / Legacy"
    fi

    printf "  ${CYAN}%-20s${NC}" "Kernel"
    echo -e "${INFO}  $(uname -r)"

    printf "  ${CYAN}%-20s${NC}" "dbus + elogind"
    if services_enabled 2>/dev/null; then
        echo -e "${GREEN}●${NC}  enabled"
    else
        echo -e "${RED}○${NC}  not enabled"
    fi

    printf "  ${CYAN}%-20s${NC}" "cronie"
    if cronie_enabled 2>/dev/null; then
        echo -e "${GREEN}●${NC}  enabled"
    else
        echo -e "${RED}○${NC}  not enabled"
    fi

    printf "  ${CYAN}%-20s${NC}" "make.conf"
    if make_conf_configured 2>/dev/null; then
        echo -e "${GREEN}●${NC}  configured"
    else
        echo -e "${RED}○${NC}  needs setup"
    fi

    printf "  ${CYAN}%-20s${NC}" "Audio"
    if audio_configured 2>/dev/null; then
        echo -e "${GREEN}●${NC}  ALSA + PipeWire"
    else
        echo -e "${RED}○${NC}  not configured"
    fi

    echo ""
    hr_thin
    echo ""
}

# ═════════════════════════════════════════════════════════════════════════════
# DESKTOP USER DETECTION
# ═════════════════════════════════════════════════════════════════════════════
detect_desktop_user() {
    DESKTOP_USER="${SUDO_USER:-}"

    if [[ -n "${DESKTOP_USER}" ]]; then
        echo -e "  Detected user: ${GREEN}${BOLD}${DESKTOP_USER}${NC}"
        read -rp "  Use '${DESKTOP_USER}' as the desktop user? [Y/n]: " yn
        yn="${yn:-Y}"
        if [[ "${yn}" =~ ^[Nn]$ ]]; then
            DESKTOP_USER=""
        fi
    fi

    if [[ -z "${DESKTOP_USER}" ]]; then
        read -rp "  Enter the desktop username: " DESKTOP_USER
    fi

    if ! id "${DESKTOP_USER}" &>/dev/null; then
        warn "User '${DESKTOP_USER}' does not exist."
        read -rp "  Create it now? [Y/n]: " yn
        yn="${yn:-Y}"
        if [[ ! "${yn}" =~ ^[Nn]$ ]]; then
            bash "${REPO_DIR}/scripts/common/add-user.sh" "${DESKTOP_USER}"
        else
            error "Cannot continue without a valid desktop user."
            exit 1
        fi
    fi
}

# ═════════════════════════════════════════════════════════════════════════════
# MAIN MENU
# ═════════════════════════════════════════════════════════════════════════════
show_main_menu() {
    center "── Main Menu ──" "${BOLD}${CYAN}"
    echo ""
    echo -e "  ${BOLD}${GREEN}Desktop Environment${NC}"
    echo ""
    printf "    ${BOLD}1${NC})  %-28s %s\n" "KDE Plasma 6" "full desktop · Wayland · SDDM"
    printf "    ${BOLD}2${NC})  %-28s %s\n" "DWM / Suckless" "minimal tiling WM · dwm+st+dmenu"
    echo ""
    echo -e "  ${BOLD}${CYAN}System Tools${NC}"
    echo ""
    printf "    ${BOLD}3${NC})  %-28s %s\n" "System Information" "hardware · boot · services · packages"
    printf "    ${BOLD}4${NC})  %-28s %s\n" "Kernel Update" "update sources & bootloader"
    printf "    ${BOLD}5${NC})  %-28s %s\n" "Rebuild & Clean" "@world · depclean · revdep-rebuild"
    printf "    ${BOLD}6${NC})  %-28s %s\n" "Maintenance" "logs · cache · temp cleanup"
    printf "    ${BOLD}7${NC})  %-28s %s\n" "Set Date / Time" "fix system clock · NTP sync"
    printf "    ${BOLD}8${NC})  %-28s %s\n" "Check Services" "dbus · elogind · cronie"
    echo ""
    hr_thin
    echo -e "    ${DIM}q)  Quit${NC}"
    echo ""
}

# ═════════════════════════════════════════════════════════════════════════════
# DWM SETUP MENU — per-step status, clear layout
# ═════════════════════════════════════════════════════════════════════════════
show_dwm_menu() {
    while true; do
        clear
        echo ""
        hr
        center "DWM / Suckless Setup" "${BOLD}${GREEN}"
        hr
        echo ""
        echo -e "  ${BOLD}Setup Steps${NC}                               ${DIM}Status${NC}"
        hr_thin
        echo ""

        printf "    ${BOLD}1${NC})  %-40s [$(status_label make_conf_configured)]\n" "Configure make.conf"
        printf "    ${BOLD}2${NC})  %-40s [$(status_label xorg_installed)]\n" "Install Xorg + deps + fonts + services"
        printf "    ${BOLD}3${NC})  %-40s [$(status_label suckless_built)]\n" "Build dwm / st / dmenu  (as ${DESKTOP_USER})"
        printf "    ${BOLD}4${NC})  %-40s [$(status_label xinitrc_exists)]\n" "Write ~/.xinitrc + auto-startx"

        echo ""
        hr_thin
        echo ""

        printf "    ${BOLD}5${NC})  %-40s [$(status_label services_enabled)]\n" "Verify essential services"
        echo ""

        echo -e "    ${BOLD}a${NC})  Run ALL steps ${DIM}(auto-skips completed)${NC}"
        echo -e "    ${DIM}b)  Back to main menu${NC}"
        echo ""
        read -rp "  Select [1-5/a/b]: " choice

        case "${choice}" in
            1) run_step_with_status "Configure make.conf" make_conf_configured root "${REPO_DIR}/scripts/dwm/01-make-conf.sh" ;;
            2) run_step_with_status "Install Xorg + deps" xorg_installed root "${REPO_DIR}/scripts/dwm/02-deps.sh" ;;
            3) run_step_with_status "Build suckless tools" suckless_built user "${REPO_DIR}/scripts/dwm/03-build-suckless.sh" ;;
            4) run_step_with_status "Write xinitrc" xinitrc_exists user "${REPO_DIR}/scripts/dwm/04-xinitrc.sh" ;;
            5) check_and_fix_services ;;
            a|A) run_all_dwm_steps ;;
            b|B) return ;;
            *) warn "Invalid selection." ; sleep 0.5 ;;
        esac
    done
}

# ═════════════════════════════════════════════════════════════════════════════
# KDE SETUP MENU
# ═════════════════════════════════════════════════════════════════════════════
show_kde_menu() {
    while true; do
        clear
        echo ""
        hr
        center "KDE Plasma 6 Setup" "${BOLD}${GREEN}"
        hr
        echo ""
        echo -e "  ${BOLD}Setup Steps${NC}                               ${DIM}Status${NC}"
        hr_thin
        echo ""

        printf "    ${BOLD}1${NC})  %-40s [$(status_label make_conf_configured)]\n" "Configure make.conf"
        printf "    ${BOLD}2${NC})  %-40s [$(status_label kde_installed)]\n" "Sync + install KDE Plasma"
        printf "    ${BOLD}3${NC})  %-40s [$(status_label services_enabled)]\n" "Enable services + groups"

        echo ""
        hr_thin
        echo ""

        echo -e "    ${BOLD}a${NC})  Run ALL steps ${DIM}(auto-skips completed)${NC}"
        echo -e "    ${DIM}b)  Back to main menu${NC}"
        echo ""
        read -rp "  Select [1-3/a/b]: " choice

        case "${choice}" in
            1) run_step_with_status "Configure make.conf" make_conf_configured root "${REPO_DIR}/scripts/kde/01-make-conf.sh" ;;
            2) run_step_with_status "Install KDE Plasma" kde_installed root "${REPO_DIR}/scripts/kde/02-install-plasma.sh" ;;
            3) run_step_with_status "Enable services" services_enabled root "${REPO_DIR}/scripts/kde/03-services.sh" "${DESKTOP_USER}" ;;
            a|A) run_all_kde_steps ;;
            b|B) return ;;
            *) warn "Invalid selection." ; sleep 0.5 ;;
        esac
    done
}

# ═════════════════════════════════════════════════════════════════════════════
# STEP RUNNER — status-aware, confirms before running
# ═════════════════════════════════════════════════════════════════════════════
run_step_with_status() {
    local label="$1"
    local check_fn="$2"
    local mode="$3"
    local script="$4"
    shift 4
    local extra_args=("$@")

    echo ""
    hr_thin
    if "${check_fn}" 2>/dev/null; then
        echo -e "  ${GREEN}●${NC} ${BOLD}${label}${NC}  —  ${GREEN}already completed${NC}"
        echo ""
        read -rp "  Re-run anyway? [y/N]: " yn
        yn="${yn:-N}"
        if [[ ! "${yn}" =~ ^[Yy]$ ]]; then
            info "Skipped."
            sleep 0.5
            return
        fi
    else
        echo -e "  ${RED}○${NC} ${BOLD}${label}${NC}  —  ${YELLOW}needs setup${NC}"
        echo ""
        read -rp "  Run now? [Y/n]: " yn
        yn="${yn:-Y}"
        if [[ "${yn}" =~ ^[Nn]$ ]]; then
            info "Skipped."
            sleep 0.5
            return
        fi
    fi

    echo ""
    if [[ "${mode}" == "user" ]]; then
        local cmd="bash $(printf '%q' "${script}")"
        if [[ ${#extra_args[@]} -gt 0 ]]; then
            cmd+="$(printf ' %q' "${extra_args[@]}")"
        fi
        su - "${DESKTOP_USER}" -c "${cmd}"
    else
        bash "${script}" "${extra_args[@]+"${extra_args[@]}"}"
    fi

    echo ""
    ok "${label} complete."
    echo ""
    read -rp "  Press Enter to continue…" _
}

# ═════════════════════════════════════════════════════════════════════════════
# RUN ALL STEPS — auto-skip done steps for resumability
# ═════════════════════════════════════════════════════════════════════════════
run_all_dwm_steps() {
    local steps=("01-make-conf.sh" "02-deps.sh" "03-build-suckless.sh" "04-xinitrc.sh")
    local checks=(make_conf_configured xorg_installed suckless_built xinitrc_exists)
    local modes=(root root user user)
    local labels=("Configure make.conf" "Install Xorg + deps" "Build suckless tools" "Write xinitrc")

    echo ""
    hr
    center "Running all DWM steps" "${BOLD}${GREEN}"
    hr
    echo ""
    echo -e "  ${DIM}Already-completed steps will be automatically skipped.${NC}"
    echo ""

    for i in "${!steps[@]}"; do
        local script="${REPO_DIR}/scripts/dwm/${steps[$i]}"
        local check="${checks[$i]}"
        local mode="${modes[$i]}"
        local label="${labels[$i]}"

        if "${check}" 2>/dev/null; then
            echo -e "  ${GREEN}●${NC} ${label}  ${DIM}— skipped (already done)${NC}"
            continue
        fi

        echo -e "  ${YELLOW}▶${NC} ${BOLD}${label}${NC}  — running…"
        echo ""

        if [[ "${mode}" == "user" ]]; then
            su - "${DESKTOP_USER}" -c "bash $(printf '%q' "${script}")"
        else
            bash "${script}"
        fi

        echo ""
        ok "${label} complete."
        echo ""
    done

    hr_thin
    ok "All DWM setup steps processed."
    echo ""
    read -rp "  Press Enter to continue…" _
}

run_all_kde_steps() {
    local steps=("01-make-conf.sh" "02-install-plasma.sh" "03-services.sh")
    local checks=(make_conf_configured kde_installed services_enabled)
    local labels=("Configure make.conf" "Install KDE Plasma" "Enable services")

    echo ""
    hr
    center "Running all KDE steps" "${BOLD}${GREEN}"
    hr
    echo ""
    echo -e "  ${DIM}Already-completed steps will be automatically skipped.${NC}"
    echo ""

    for i in "${!steps[@]}"; do
        local script="${REPO_DIR}/scripts/kde/${steps[$i]}"
        local check="${checks[$i]}"
        local label="${labels[$i]}"
        local extra=""
        [[ "${steps[$i]}" == "03-services.sh" ]] && extra="${DESKTOP_USER}"

        if "${check}" 2>/dev/null; then
            echo -e "  ${GREEN}●${NC} ${label}  ${DIM}— skipped (already done)${NC}"
            continue
        fi

        echo -e "  ${YELLOW}▶${NC} ${BOLD}${label}${NC}  — running…"
        echo ""
        bash "${script}" ${extra}

        echo ""
        ok "${label} complete."
        echo ""
    done

    hr_thin
    ok "All KDE setup steps processed."
    echo ""
    read -rp "  Press Enter to continue…" _
}

# ═════════════════════════════════════════════════════════════════════════════
# SERVICE CHECKER
# ═════════════════════════════════════════════════════════════════════════════
check_and_fix_services() {
    clear
    echo ""
    hr
    center "Essential OpenRC Services" "${BOLD}${GREEN}"
    hr
    echo ""

    echo -e "  ${BOLD}Service                 Runlevel        Status${NC}"
    hr_thin

    local services=("dbus:default" "elogind:boot" "cronie:default" "udev:sysinit")
    local need_fix=()

    for entry in "${services[@]}"; do
        local svc="${entry%%:*}"
        local rl="${entry##*:}"
        if is_service_enabled "${svc}" "${rl}" 2>/dev/null; then
            printf "  ${GREEN}●${NC} %-22s %-15s ${GREEN}enabled${NC}\n" "${svc}" "${rl}"
        else
            printf "  ${RED}○${NC} %-22s %-15s ${RED}NOT enabled${NC}\n" "${svc}" "${rl}"
            need_fix+=("${entry}")
        fi
    done

    echo ""
    echo -e "  ${BOLD}Package                         Status${NC}"
    hr_thin

    local pkgs=("sys-apps/dbus" "sys-auth/elogind" "sys-auth/polkit" "sys-process/cronie" "media-sound/alsa-utils" "media-video/pipewire" "media-video/wireplumber")
    local missing_pkgs=()
    for pkg in "${pkgs[@]}"; do
        if pkg_installed "${pkg}" 2>/dev/null; then
            printf "  ${GREEN}●${NC} %-32s ${GREEN}installed${NC}\n" "${pkg}"
        else
            printf "  ${RED}○${NC} %-32s ${RED}not installed${NC}\n" "${pkg}"
            missing_pkgs+=("${pkg}")
        fi
    done

    if [[ ${#missing_pkgs[@]} -gt 0 ]]; then
        echo ""
        hr_thin
        echo -e "  ${BOLD}${YELLOW}Packages to install:${NC}"
        for pkg in "${missing_pkgs[@]}"; do
            echo -e "    ${YELLOW}→${NC} ${pkg}"
        done
        echo ""
        read -rp "  Install these packages? [Y/n]: " yn
        yn="${yn:-Y}"
        if [[ ! "${yn}" =~ ^[Nn]$ ]]; then
            emerge --ask "${missing_pkgs[@]}"
        fi
    fi

    if [[ ${#need_fix[@]} -gt 0 ]]; then
        echo ""
        hr_thin
        echo -e "  ${BOLD}${YELLOW}Services to enable:${NC}"
        for entry in "${need_fix[@]}"; do
            echo -e "    ${YELLOW}→${NC} ${entry%%:*} (${entry##*:} runlevel)"
        done
        echo ""
        read -rp "  Enable these services? [Y/n]: " yn
        yn="${yn:-Y}"
        if [[ ! "${yn}" =~ ^[Nn]$ ]]; then
            for entry in "${need_fix[@]}"; do
                local svc="${entry%%:*}"
                local rl="${entry##*:}"
                rc-update add "${svc}" "${rl}" 2>/dev/null && ok "Enabled ${svc} in ${rl}" || warn "Failed to enable ${svc}"
            done
        fi
    fi

    if [[ ${#missing_pkgs[@]} -eq 0 && ${#need_fix[@]} -eq 0 ]]; then
        echo ""
        ok "All essential services are installed and enabled!"
    fi

    echo ""
    read -rp "  Press Enter to continue…" _
}

# ═════════════════════════════════════════════════════════════════════════════
# DATE/TIME FIXER
# ═════════════════════════════════════════════════════════════════════════════
fix_datetime() {
    clear
    echo ""
    hr
    center "Set System Date / Time" "${BOLD}${GREEN}"
    hr
    echo ""
    printf "  ${CYAN}%-16s${NC} %s\n" "System clock:" "$(date '+%a %Y-%m-%d  %H:%M:%S %Z')"
    printf "  ${CYAN}%-16s${NC} %s\n" "Hardware clock:" "$(hwclock --show 2>/dev/null || echo 'unavailable')"
    echo ""
    hr_thin
    echo ""
    echo -e "    ${BOLD}1${NC})  Set date manually  ${DIM}(YYYY-MM-DD HH:MM:SS)${NC}"
    echo -e "    ${BOLD}2${NC})  Sync via NTP       ${DIM}(requires network)${NC}"
    echo -e "    ${BOLD}3${NC})  Sync from HW clock"
    echo -e "    ${DIM}4)  Back${NC}"
    echo ""
    read -rp "  Select [1-4]: " choice

    case "${choice}" in
        1)
            read -rp "  Enter date (YYYY-MM-DD HH:MM:SS): " dt
            if [[ -n "${dt}" ]]; then
                date -s "${dt}"
                hwclock --systohc
                ok "Date set to: $(date)"
            fi
            ;;
        2)
            if ! command -v ntpd &>/dev/null && ! command -v chronyd &>/dev/null; then
                info "Installing net-misc/ntp…"
                emerge --ask net-misc/ntp
            fi
            if command -v ntpd &>/dev/null; then
                info "Syncing with NTP servers…"
                ntpd -gq 2>/dev/null || ntpdate pool.ntp.org 2>/dev/null || true
                hwclock --systohc
                ok "Time synced: $(date)"
            elif command -v chronyd &>/dev/null; then
                chronyd -q 'server pool.ntp.org iburst' 2>/dev/null || true
                hwclock --systohc
                ok "Time synced: $(date)"
            fi
            ;;
        3)
            hwclock --hctosys
            ok "System clock synced from hardware clock: $(date)"
            ;;
        4) return ;;
    esac

    echo ""
    read -rp "  Press Enter to continue…" _
}

# ═════════════════════════════════════════════════════════════════════════════
# MAINTENANCE TOOLS
# ═════════════════════════════════════════════════════════════════════════════
show_maintenance_menu() {
    while true; do
        clear
        echo ""
        hr
        center "Gentoo Maintenance" "${BOLD}${GREEN}"
        hr
        echo ""
        echo -e "    ${BOLD}1${NC})  Clean distfiles          ${DIM}old source tarballs${NC}"
        echo -e "    ${BOLD}2${NC})  Clean binary packages"
        echo -e "    ${BOLD}3${NC})  Clean Portage temp        ${DIM}/var/tmp/portage${NC}"
        echo -e "    ${BOLD}4${NC})  List installed kernels"
        echo -e "    ${BOLD}5${NC})  Clean old logs            ${DIM}/var/log${NC}"
        echo -e "    ${BOLD}6${NC})  Disk usage overview"
        echo -e "    ${BOLD}7${NC})  View world file"
        echo -e "    ${BOLD}8${NC})  eclean-kernel              ${DIM}remove old kernels${NC}"
        echo -e "    ${BOLD}9${NC})  Run all cleanup"
        echo ""
        echo -e "    ${DIM}b)  Back to main menu${NC}"
        echo ""
        read -rp "  Select: " choice

        case "${choice}" in
            1)
                if command -v eclean &>/dev/null; then
                    eclean --ask distfiles
                else
                    warn "eclean not found — install app-portage/gentoolkit"
                    read -rp "  Install gentoolkit? [Y/n]: " yn
                    yn="${yn:-Y}"
                    [[ ! "${yn}" =~ ^[Nn]$ ]] && emerge --ask app-portage/gentoolkit
                fi
                ;;
            2)
                if command -v eclean &>/dev/null; then
                    eclean --ask packages
                else
                    warn "eclean not found."
                fi
                ;;
            3)
                local tsize
                tsize=$(du -sh /var/tmp/portage 2>/dev/null | awk '{print $1}')
                echo -e "  /var/tmp/portage: ${BOLD}${tsize:-0}${NC}"
                read -rp "  Remove contents? [y/N]: " yn
                yn="${yn:-N}"
                if [[ "${yn}" =~ ^[Yy]$ ]]; then
                    rm -rf /var/tmp/portage/*
                    ok "Portage temp cleaned"
                fi
                ;;
            4)
                echo ""
                echo -e "  ${BOLD}Kernel images in /boot:${NC}"
                ls -1 /boot/vmlinuz* 2>/dev/null | while read -r f; do echo "    ${f}"; done || echo "    (none)"
                echo ""
                echo -e "  ${BOLD}eselect kernel list:${NC}"
                eselect kernel list 2>/dev/null | while read -r line; do echo "    ${line}"; done || true
                ;;
            5)
                echo ""
                echo -e "  ${BOLD}Log files > 1 MB:${NC}"
                find /var/log -name "*.log" -size +1M -exec ls -lh {} \; 2>/dev/null || echo "    (none)"
                echo ""
                read -rp "  Truncate logs > 1MB? [y/N]: " yn
                yn="${yn:-N}"
                if [[ "${yn}" =~ ^[Yy]$ ]]; then
                    find /var/log -name "*.log" -size +1M -exec truncate -s 0 {} \;
                    ok "Large logs truncated"
                fi
                ;;
            6)
                echo ""
                echo -e "  ${BOLD}Disk Usage${NC}"
                hr_thin
                df -h / /boot /home /var 2>/dev/null | head -10
                ;;
            7)
                echo ""
                if [[ -f /var/lib/portage/world ]]; then
                    local wc_count
                    wc_count=$(wc -l < /var/lib/portage/world)
                    echo -e "  ${BOLD}World file${NC} — ${wc_count} entries"
                    hr_thin
                    cat /var/lib/portage/world
                else
                    warn "World file not found"
                fi
                ;;
            8)
                if command -v eclean-kernel &>/dev/null; then
                    eclean-kernel --ask
                else
                    warn "eclean-kernel not found — install app-admin/eclean-kernel"
                    read -rp "  Install? [Y/n]: " yn
                    yn="${yn:-Y}"
                    [[ ! "${yn}" =~ ^[Nn]$ ]] && emerge --ask app-admin/eclean-kernel
                fi
                ;;
            9)
                echo ""
                info "Running full cleanup…"
                if command -v eclean &>/dev/null; then
                    eclean distfiles && eclean packages
                fi
                rm -rf /var/tmp/portage/* 2>/dev/null
                find /var/log -name "*.log" -size +10M -exec truncate -s 0 {} \; 2>/dev/null
                ok "Cleanup complete"
                echo ""
                df -h / /boot /home 2>/dev/null || true
                ;;
            b|B) return ;;
            *) warn "Invalid selection." ; sleep 0.5 ;;
        esac

        echo ""
        read -rp "  Press Enter to continue…" _
    done
}

# ═════════════════════════════════════════════════════════════════════════════
# MAIN LOOP
# ═════════════════════════════════════════════════════════════════════════════
detect_desktop_user

while true; do
    show_banner
    show_main_menu
    read -rp "  Select [1-8/q]: " main_choice

    case "${main_choice}" in
        1) show_kde_menu ;;
        2) show_dwm_menu ;;
        3)
            bash "${REPO_DIR}/scripts/common/system-info.sh"
            echo ""
            read -rp "  Press Enter to continue…" _
            ;;
        4)
            bash "${REPO_DIR}/scripts/common/kernel-update.sh"
            echo ""
            read -rp "  Press Enter to continue…" _
            ;;
        5)
            bash "${REPO_DIR}/scripts/common/rebuild-clean.sh"
            echo ""
            read -rp "  Press Enter to continue…" _
            ;;
        6) show_maintenance_menu ;;
        7) fix_datetime ;;
        8) check_and_fix_services ;;
        q|Q)
            echo ""
            hr
            center "Goodbye!" "${GREEN}"
            hr
            echo ""
            exit 0
            ;;
        *) warn "Invalid selection." ; sleep 0.5 ;;
    esac
done

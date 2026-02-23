#!/usr/bin/env bash
# =============================================================================
# setup.sh — Gentoo Post-Install Setup Wizard
# Usage:  sudo bash setup.sh
# =============================================================================
set -euo pipefail

# ── Locate repo root (script lives at repo root) ──────────────────────────────
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Source shared helpers (colours, set_var, detect_*) ───────────────────────
# shellcheck source=scripts/common/detect-hardware.sh
source "${REPO_DIR}/scripts/common/detect-hardware.sh"

# ── Root check ────────────────────────────────────────────────────────────────
if [[ "${EUID}" -ne 0 ]]; then
    error "This script must be run as root:  sudo bash setup.sh"
    exit 1
fi

# ── Banner ────────────────────────────────────────────────────────────────────
clear
echo -e "${CYAN}"
echo "  ╔══════════════════════════════════════════════════════╗"
echo "  ║        Gentoo Post-Install Setup Wizard              ║"
echo "  ║        AMD Ryzen 9 9800X3D + Radeon RX 7800 XT       ║"
echo "  ╚══════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo "  This wizard runs each setup script in the correct order."
echo "  You will be prompted before every step — press Enter to"
echo "  accept the default [Y] or type 'n' to skip a step you've"
echo "  already completed."
echo ""

# ── Helper: run a step ────────────────────────────────────────────────────────
# run_step <label> <description> <root|user> <desktop_user> <script> [args…]
#   root  → runs as root (current process)
#   user  → runs as <desktop_user> via su -
run_step() {
    local label="$1"
    local desc="$2"
    local mode="$3"        # root | user
    local run_as="$4"      # desktop username (used when mode=user)
    local script="$5"
    shift 5
    local extra_args=("$@")

    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  ${GREEN}Step ${label}${NC}: ${desc}"
    if [[ "${mode}" == "user" ]]; then
        echo -e "  ${YELLOW}(runs as user: ${run_as})${NC}"
    fi
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    read -rp "  Run this step? [Y/n]: " yn
    yn="${yn:-Y}"
    if [[ "${yn}" =~ ^[Nn]$ ]]; then
        warn "  Skipping step ${label}."
        return
    fi

    if [[ "${mode}" == "user" ]]; then
        # Build a safely-quoted command string for su -c.
        # Handle extra_args separately to avoid issues when the array is empty.
        local cmd="bash $(printf '%q' "${script}")"
        if [[ ${#extra_args[@]} -gt 0 ]]; then
            cmd+="$(printf ' %q' "${extra_args[@]}")"
        fi
        su - "${run_as}" -c "${cmd}"
    else
        bash "${script}" "${extra_args[@]+"${extra_args[@]}"}"
    fi

    ok "  Step ${label} complete."
}

# ═════════════════════════════════════════════════════════════════════════════
# 1. Desktop environment selection
# ═════════════════════════════════════════════════════════════════════════════
echo -e "  ${CYAN}Select a desktop environment:${NC}"
echo ""
echo "    1) KDE Plasma 6    — full desktop with Wayland, SDDM, NetworkManager"
echo "    2) DWM / Suckless  — minimal tiling WM (dwm + st + dmenu)"
echo ""
DE_CHOICE=""
while [[ "${DE_CHOICE}" != "1" && "${DE_CHOICE}" != "2" ]]; do
    read -rp "  Enter 1 or 2: " DE_CHOICE
done

if [[ "${DE_CHOICE}" == "1" ]]; then
    DE_LABEL="KDE Plasma 6"
else
    DE_LABEL="DWM / Suckless"
fi
ok "Selected: ${DE_LABEL}"

# ═════════════════════════════════════════════════════════════════════════════
# 2. Desktop user selection / creation
# ═════════════════════════════════════════════════════════════════════════════
echo ""
echo -e "  ${CYAN}Desktop user account${NC}"
echo ""
DESKTOP_USER="${SUDO_USER:-}"

if [[ -n "${DESKTOP_USER}" ]]; then
    echo "  Detected invoking user: ${DESKTOP_USER}"
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
    read -rp "  Create it now with add-user.sh? [Y/n]: " yn
    yn="${yn:-Y}"
    if [[ ! "${yn}" =~ ^[Nn]$ ]]; then
        bash "${REPO_DIR}/scripts/common/add-user.sh" "${DESKTOP_USER}"
    else
        error "Cannot continue without a valid desktop user. Exiting."
        exit 1
    fi
else
    ok "Desktop user: ${DESKTOP_USER}"
fi

# ═════════════════════════════════════════════════════════════════════════════
# 3. Run steps
# ═════════════════════════════════════════════════════════════════════════════
echo ""
echo -e "  ${CYAN}The following steps will be run for ${DE_LABEL}:${NC}"

if [[ "${DE_CHOICE}" == "1" ]]; then
    # ── KDE path ──────────────────────────────────────────────────────────────
    echo "    [1] Configure make.conf"
    echo "    [2] Sync Portage, select profile, install KDE Plasma"
    echo "    [3] Enable services + configure groups"
    echo "    [R] Deep update, depclean, revdep-rebuild"
    echo ""

    run_step "1" "Configure /etc/portage/make.conf for KDE Plasma 6" \
        root "" "${REPO_DIR}/scripts/kde/01-make-conf.sh"

    run_step "2" "Sync Portage tree, select KDE profile, install kde-plasma/plasma-meta" \
        root "" "${REPO_DIR}/scripts/kde/02-install-plasma.sh"

    run_step "3" "Install SDDM, enable OpenRC services, add ${DESKTOP_USER} to groups" \
        root "" "${REPO_DIR}/scripts/kde/03-services.sh" "${DESKTOP_USER}"

else
    # ── DWM path ──────────────────────────────────────────────────────────────
    echo "    [1] Configure make.conf"
    echo "    [2] Sync Portage, install Xorg + build libs + fonts"
    echo "    [3] Clone, patch, and build dwm / st / dmenu  (runs as ${DESKTOP_USER})"
    echo "    [4] Write ~/.xinitrc and auto-startx snippet  (runs as ${DESKTOP_USER})"
    echo "    [R] Deep update, depclean, revdep-rebuild"
    echo ""

    run_step "1" "Configure /etc/portage/make.conf for minimal Xorg/suckless" \
        root "" "${REPO_DIR}/scripts/dwm/01-make-conf.sh"

    run_step "2" "Sync Portage tree, install Xorg + libraries + fonts" \
        root "" "${REPO_DIR}/scripts/dwm/02-deps.sh"

    run_step "3" "Clone, patch, and build dwm / st / dmenu" \
        user "${DESKTOP_USER}" "${REPO_DIR}/scripts/dwm/03-build-suckless.sh"

    run_step "4" "Write ~/.xinitrc and auto-startx snippet in ~/.bash_profile" \
        user "${DESKTOP_USER}" "${REPO_DIR}/scripts/dwm/04-xinitrc.sh"
fi

# ═════════════════════════════════════════════════════════════════════════════
# 4. Rebuild & clean (offered to both paths)
# ═════════════════════════════════════════════════════════════════════════════
run_step "R" "Deep @world update, depclean, revdep-rebuild, preserved-rebuild" \
    root "" "${REPO_DIR}/scripts/common/rebuild-clean.sh"

# ═════════════════════════════════════════════════════════════════════════════
# 5. Final summary
# ═════════════════════════════════════════════════════════════════════════════
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  ${GREEN}Setup complete!${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

if [[ "${DE_CHOICE}" == "1" ]]; then
    echo -e "  ${GREEN}KDE Plasma 6${NC} is installed."
    echo ""
    echo "  • Reboot to start SDDM and log in to a Plasma session:"
    echo "      reboot"
    echo ""
    echo "  • At the SDDM login screen select 'Plasma (Wayland)' for best"
    echo "    performance on RDNA 3, or 'Plasma (X11)' as a fallback."
else
    echo -e "  ${GREEN}DWM / Suckless${NC} is installed."
    echo ""
    echo "  • Log out and back in as ${DESKTOP_USER} on TTY1."
    echo "    X will start automatically and launch dwm."
    echo ""
    echo "  • Edit ~/.local/src/dwm/config.h to customise keybindings, colours,"
    echo "    and fonts, then re-run scripts/dwm/03-build-suckless.sh to rebuild."
fi

echo ""
echo "  See the docs/ folder for full configuration guides:"
echo "    docs/kde-plasma.md"
echo "    docs/dwm-suckless.md"
echo ""

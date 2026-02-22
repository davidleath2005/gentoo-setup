#!/usr/bin/env bash
# =============================================================================
# scripts/kde/03-services.sh
# Description: Install and enable SDDM, elogind, dbus, NetworkManager;
#              add user to required groups
# Usage:       sudo bash scripts/kde/03-services.sh [username]
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

# ── Determine target user ─────────────────────────────────────────────────────
TARGET_USER="${1:-}"
if [[ -z "${TARGET_USER}" ]]; then
    # Default to the user who invoked sudo, or prompt
    TARGET_USER="${SUDO_USER:-}"
fi
if [[ -z "${TARGET_USER}" ]]; then
    read -rp "Enter the desktop username to configure: " TARGET_USER
fi
if ! id "${TARGET_USER}" &>/dev/null; then
    error "User '${TARGET_USER}' does not exist. Create it first with scripts/common/add-user.sh"
    exit 1
fi
info "Configuring services for user: ${TARGET_USER}"

# ── 1. Install required packages ──────────────────────────────────────────────
PKGS=()

if ! command -v sddm &>/dev/null; then
    PKGS+=(x11-misc/sddm gui-libs/display-manager-init)
else
    ok "sddm already installed"
fi

if ! command -v dbus-daemon &>/dev/null; then
    PKGS+=(sys-apps/dbus)
else
    ok "dbus already installed"
fi

if ! command -v NetworkManager &>/dev/null; then
    PKGS+=(net-misc/networkmanager kde-plasma/plasma-nm)
else
    ok "NetworkManager already installed"
fi

if [[ ${#PKGS[@]} -gt 0 ]]; then
    info "Installing: ${PKGS[*]}"
    emerge --ask "${PKGS[@]}"
fi

ok "All required packages installed"

# ── 2. Configure SDDM as display manager ─────────────────────────────────────
DM_CONF="/etc/conf.d/display-manager"
if [[ -f "${DM_CONF}" ]]; then
    if grep -q 'DISPLAYMANAGER="sddm"' "${DM_CONF}"; then
        ok "SDDM already set as display manager"
    else
        info "Setting SDDM as display manager in ${DM_CONF}"
        sed -i 's|^DISPLAYMANAGER=.*|DISPLAYMANAGER="sddm"|' "${DM_CONF}"
        ok "DISPLAYMANAGER set to sddm"
    fi
else
    info "Creating ${DM_CONF}"
    echo 'DISPLAYMANAGER="sddm"' > "${DM_CONF}"
    ok "${DM_CONF} created"
fi

# ── 3. Enable OpenRC services ─────────────────────────────────────────────────
enable_service() {
    local svc="$1"
    local runlevel="${2:-default}"
    if rc-update show "${runlevel}" 2>/dev/null | grep -q "^[[:space:]]*${svc}"; then
        ok "${svc} already in ${runlevel} runlevel"
    else
        info "Adding ${svc} to ${runlevel} runlevel"
        rc-update add "${svc}" "${runlevel}"
    fi
}

enable_service elogind boot
enable_service dbus default
enable_service display-manager default
enable_service NetworkManager default

# ── 4. Add user to required groups ───────────────────────────────────────────
GROUPS_TO_ADD=(video audio plugdev seat usb input wheel)

info "Adding ${TARGET_USER} to groups: ${GROUPS_TO_ADD[*]}"
for grp in "${GROUPS_TO_ADD[@]}"; do
    if getent group "${grp}" &>/dev/null; then
        if id -nG "${TARGET_USER}" | grep -qw "${grp}"; then
            ok "${TARGET_USER} already in group '${grp}'"
        else
            usermod -aG "${grp}" "${TARGET_USER}"
            ok "Added ${TARGET_USER} to '${grp}'"
        fi
    else
        warn "Group '${grp}' does not exist — skipping"
    fi
done

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
ok "Service configuration complete."
echo ""
echo -e "  Enabled services:"
for svc in elogind dbus display-manager NetworkManager; do
    echo -e "    • ${svc}"
done
echo ""
echo -e "  Groups for ${TARGET_USER}:"
id "${TARGET_USER}"
echo ""
info "Reboot to start SDDM and the KDE Plasma desktop:"
echo "  reboot"

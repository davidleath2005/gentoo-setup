#!/usr/bin/env bash
# =============================================================================
# scripts/common/add-user.sh
# Description: Create a standard desktop user with correct group memberships
# Usage:       sudo bash scripts/common/add-user.sh <username>
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

if [[ $# -lt 1 || -z "${1:-}" ]]; then
    error "Usage: $0 <username>"
    exit 1
fi

USERNAME="$1"

# Validate username (alphanumeric, dash, underscore; starts with letter)
if ! [[ "${USERNAME}" =~ ^[a-z][a-z0-9_-]*$ ]]; then
    error "Invalid username '${USERNAME}'. Must start with a lowercase letter and contain only [a-z0-9_-]."
    exit 1
fi

# ── 1. Create user if not present ─────────────────────────────────────────────
if id "${USERNAME}" &>/dev/null; then
    ok "User '${USERNAME}' already exists"
else
    info "Creating user '${USERNAME}'…"
    useradd \
        --create-home \
        --shell /bin/bash \
        --user-group \
        "${USERNAME}"
    ok "User '${USERNAME}' created with home directory /home/${USERNAME}"

    info "Set a password for '${USERNAME}':"
    passwd "${USERNAME}"
fi

# ── 2. Add to required groups ─────────────────────────────────────────────────
GROUPS_TO_ADD=(wheel audio video plugdev usb input portage seat)

info "Adding '${USERNAME}' to groups…"
for grp in "${GROUPS_TO_ADD[@]}"; do
    if getent group "${grp}" &>/dev/null; then
        if id -nG "${USERNAME}" | grep -qw "${grp}"; then
            ok "  Already in group '${grp}'"
        else
            usermod -aG "${grp}" "${USERNAME}"
            ok "  Added to group '${grp}'"
        fi
    else
        warn "  Group '${grp}' does not exist — skipping"
    fi
done

# ── 3. Ensure home directory exists with correct ownership ────────────────────
HOME_DIR="/home/${USERNAME}"
if [[ ! -d "${HOME_DIR}" ]]; then
    info "Creating home directory ${HOME_DIR}…"
    mkdir -p "${HOME_DIR}"
fi
chown "${USERNAME}:${USERNAME}" "${HOME_DIR}"
chmod 750 "${HOME_DIR}"
ok "Home directory: ${HOME_DIR}"

# ── 4. Ensure shell is /bin/bash ──────────────────────────────────────────────
CURRENT_SHELL=$(getent passwd "${USERNAME}" | cut -d: -f7)
if [[ "${CURRENT_SHELL}" != "/bin/bash" ]]; then
    info "Setting shell to /bin/bash…"
    usermod --shell /bin/bash "${USERNAME}"
    ok "Shell set to /bin/bash"
else
    ok "Shell already /bin/bash"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
ok "User '${USERNAME}' configured."
echo ""
echo "  Username : ${USERNAME}"
echo "  Home     : ${HOME_DIR}"
echo "  Shell    : /bin/bash"
echo "  Groups   : $(id -nG "${USERNAME}")"
echo ""
info "If this user will run KDE Plasma, continue with: sudo bash scripts/kde/03-services.sh ${USERNAME}"
info "If this user will run DWM, continue with:        bash scripts/dwm/03-build-suckless.sh  (as ${USERNAME})"

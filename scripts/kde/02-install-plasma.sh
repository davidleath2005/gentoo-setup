#!/usr/bin/env bash
# =============================================================================
# scripts/kde/02-install-plasma.sh
# Description: Sync portage, select KDE profile, and install KDE Plasma 6
# Usage:       sudo bash scripts/kde/02-install-plasma.sh
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

# ── 1. Sync portage ───────────────────────────────────────────────────────────
info "Syncing Portage tree…"
emaint sync -a
ok "Portage sync complete"

# ── 2. package.accept_keywords for KDE ───────────────────────────────────────
KW_DIR="/etc/portage/package.accept_keywords"
KW_FILE="${KW_DIR}/kde"

mkdir -p "${KW_DIR}"

if [[ -f "${KW_FILE}" ]]; then
    ok "${KW_FILE} already exists — skipping"
else
    info "Writing ${KW_FILE}…"
    cat > "${KW_FILE}" <<'EOF'
kde-plasma/*      ~amd64
kde-frameworks/*  ~amd64
kde-apps/*        ~amd64
EOF
    ok "Keywords file written"
fi

# ── 3. Select KDE Plasma profile ─────────────────────────────────────────────
info "Available Portage profiles:"
eselect profile list

PLASMA_PROFILE=$(eselect profile list | grep -i "plasma" | grep -v "developer\|hardened" | head -n1 | awk '{print $2}')

if [[ -z "${PLASMA_PROFILE}" ]]; then
    warn "Could not auto-detect plasma profile."
    eselect profile list
    read -rp "Enter profile number or name to select: " PLASMA_PROFILE
fi

info "Selecting profile: ${PLASMA_PROFILE}"
eselect profile set "${PLASMA_PROFILE}"
ok "Profile set to: $(eselect profile show | tail -n1 | xargs)"

# ── 4. Update @world ──────────────────────────────────────────────────────────
info "Updating @world with new profile and USE flags…"
warn "This may take a long time. Review the package list carefully."
emerge --ask --verbose --update --deep --newuse @world

ok "@world update complete"

# ── 5. Install KDE Plasma meta package ───────────────────────────────────────
info "Installing kde-plasma/plasma-meta…"
emerge --ask kde-plasma/plasma-meta
ok "KDE Plasma installed"

# ── 6. Optional: full KDE applications suite ─────────────────────────────────
echo ""
read -rp "Install kde-apps/kde-apps-meta (large, ~200 packages)? [y/N]: " INSTALL_APPS
INSTALL_APPS="${INSTALL_APPS:-N}"
if [[ "${INSTALL_APPS}" =~ ^[Yy]$ ]]; then
    info "Installing kde-apps/kde-apps-meta…"
    emerge --ask kde-apps/kde-apps-meta
    ok "KDE applications installed"
else
    info "Skipping kde-apps-meta. You can install individual apps later."
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
ok "KDE Plasma 6 installation complete."
info "Next step: sudo bash scripts/kde/03-services.sh"

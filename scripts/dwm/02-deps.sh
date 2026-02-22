#!/usr/bin/env bash
# =============================================================================
# scripts/dwm/02-deps.sh
# Description: Install Xorg, xinit, build libraries for dwm/st/dmenu, and fonts
# Usage:       sudo bash scripts/dwm/02-deps.sh
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

# ── 2. Install git if not present ────────────────────────────────────────────
if ! command -v git &>/dev/null; then
    info "Installing git…"
    emerge --ask dev-vcs/git
    ok "git installed"
else
    ok "git already installed: $(git --version)"
fi

# ── 3. Install Xorg and xinit ─────────────────────────────────────────────────
info "Installing Xorg server and xinit…"
emerge --ask \
    x11-base/xorg-server \
    x11-apps/xinit

ok "Xorg and xinit installed"

# ── 4. Install build-time libraries for dwm/st/dmenu ─────────────────────────
info "Installing build libraries for dwm/st/dmenu…"
emerge --ask \
    x11-libs/libX11 \
    x11-libs/libXft \
    x11-libs/libXinerama \
    x11-libs/libXrender \
    media-libs/fontconfig \
    media-libs/freetype

ok "Build libraries installed"

# ── 5. Install fonts ──────────────────────────────────────────────────────────
info "Installing recommended fonts…"
emerge --ask \
    media-fonts/terminus-font \
    media-fonts/dejavu \
    media-fonts/noto

# Rebuild font cache
info "Rebuilding font cache…"
fc-cache -fv 2>&1 | tail -n3

ok "Fonts installed and font cache rebuilt"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
ok "All Xorg dependencies installed."
echo ""
echo "  Installed:"
echo "    • x11-base/xorg-server"
echo "    • x11-apps/xinit"
echo "    • x11-libs/libX11, libXft, libXinerama, libXrender"
echo "    • media-libs/fontconfig, freetype"
echo "    • media-fonts/terminus-font, dejavu, noto"
echo ""
info "Next step: bash scripts/dwm/03-build-suckless.sh  (run as your normal user)"

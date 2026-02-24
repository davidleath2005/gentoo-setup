#!/usr/bin/env bash
# =============================================================================
# scripts/dwm/03-build-suckless.sh
# Description: Build and install dwm, st, and dmenu from the repo's
#              suckless/  flexipatch trees (no network clone needed).
# Usage:       bash scripts/dwm/03-build-suckless.sh
#              (runs as normal user; sudo is used only for make install)
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
ok()    { echo -e "${GREEN}[ OK ]${NC}  $*"; }
error() { echo -e "${RED}[ERR ]${NC}  $*" >&2; }

# Run as normal user (sudo is only used for make install)
if [[ "${EUID}" -eq 0 ]]; then
    error "Do not run this script as root. It will use sudo for 'make install' steps."
    exit 1
fi

# ── Locate repo root ──────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SUCKLESS_DIR="${REPO_DIR}/suckless"

# ── Verify suckless source trees exist ────────────────────────────────────────
TOOLS=("dwm-flexipatch" "st-flexipatch" "dmenu-flexipatch")
BINNAMES=("dwm" "st" "dmenu")

for tool in "${TOOLS[@]}"; do
    if [[ ! -d "${SUCKLESS_DIR}/${tool}" ]]; then
        error "Missing source tree: ${SUCKLESS_DIR}/${tool}"
        error "Clone:  git clone https://github.com/bakkeby/${tool}.git ${SUCKLESS_DIR}/${tool}"
        exit 1
    fi
done

ok "All suckless source trees found in ${SUCKLESS_DIR}/"

# ── Build status check ───────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  ${GREEN}Suckless Build Status${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
for i in "${!BINNAMES[@]}"; do
    bin="${BINNAMES[$i]}"
    tool="${TOOLS[$i]}"
    if command -v "${bin}" &>/dev/null; then
        installed_path=$(command -v "${bin}")
        echo -e "  ${GREEN}●${NC} ${bin} — installed at ${installed_path}"
    else
        echo -e "  ${RED}○${NC} ${bin} — not installed"
    fi
    if [[ -f "${SUCKLESS_DIR}/${tool}/patches.h" ]]; then
        echo -e "    patches.h: ${GREEN}configured${NC}"
    else
        echo -e "    patches.h: ${YELLOW}using defaults (patches.def.h)${NC}"
    fi
    if [[ -f "${SUCKLESS_DIR}/${tool}/config.h" ]]; then
        echo -e "    config.h:  ${GREEN}customised${NC}"
    else
        echo -e "    config.h:  ${YELLOW}using defaults (config.def.h)${NC}"
    fi
done
echo ""

# ── Confirm build ─────────────────────────────────────────────────────────────
read -rp "  Build and install all suckless tools? [Y/n]: " yn
yn="${yn:-Y}"
if [[ "${yn}" =~ ^[Nn]$ ]]; then
    info "Aborted."
    exit 0
fi

# ── Build and install each tool ───────────────────────────────────────────────
for i in "${!TOOLS[@]}"; do
    tool="${TOOLS[$i]}"
    bin="${BINNAMES[$i]}"
    src="${SUCKLESS_DIR}/${tool}"

    echo ""
    echo -e "${CYAN}──────────────────────────────────────────────────────────${NC}"
    info "Building ${bin} (from ${tool})…"
    echo -e "${CYAN}──────────────────────────────────────────────────────────${NC}"

    cd "${src}"

    # Ensure patches.h and config.h exist (flexipatch copies from .def.h if missing)
    if [[ ! -f "patches.h" && -f "patches.def.h" ]]; then
        info "  Copying patches.def.h → patches.h"
        cp patches.def.h patches.h
    fi
    if [[ ! -f "config.h" && -f "config.def.h" ]]; then
        info "  Copying config.def.h → config.h"
        cp config.def.h config.h
    fi

    sudo make clean install 2>&1 | tail -5
    ok "${bin} built and installed"
done

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
ok "Suckless tools built and installed."
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
for bin in "${BINNAMES[@]}"; do
    loc=$(command -v "${bin}" 2>/dev/null || echo 'not found in PATH')
    echo -e "  • ${bin}: ${loc}"
done
echo ""
info "To customise: edit config.h in suckless/<tool>/ and re-run this script."
info "Next step: bash scripts/dwm/04-xinitrc.sh"

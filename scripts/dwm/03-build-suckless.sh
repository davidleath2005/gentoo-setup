#!/usr/bin/env bash
# =============================================================================
# scripts/dwm/03-build-suckless.sh
# Description: Clone, configure, and build dwm, st, and dmenu from suckless.org
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

SRC_DIR="${HOME}/.local/src"
SUCKLESS_BASE="https://git.suckless.org"

TOOLS=(dwm st dmenu)

# ── 1. Create source directory ────────────────────────────────────────────────
info "Creating source directory: ${SRC_DIR}"
mkdir -p "${SRC_DIR}"
ok "Directory ready: ${SRC_DIR}"

# ── 2. Clone repos ────────────────────────────────────────────────────────────
for tool in "${TOOLS[@]}"; do
    TARGET="${SRC_DIR}/${tool}"
    if [[ -d "${TARGET}/.git" ]]; then
        info "${tool} already cloned — pulling latest…"
        git -C "${TARGET}" pull --ff-only
        ok "${tool} updated"
    else
        info "Cloning ${tool} from ${SUCKLESS_BASE}/${tool}…"
        git clone "${SUCKLESS_BASE}/${tool}" "${TARGET}"
        ok "${tool} cloned to ${TARGET}"
    fi
done

# ── 3. Apply patches (optional) ───────────────────────────────────────────────
apply_patches() {
    local tool="$1"
    local patches_dir="${SRC_DIR}/${tool}/patches"

    if [[ -d "${patches_dir}" ]]; then
        info "Found patches/ directory for ${tool} — applying patches…"
        while IFS= read -r -d '' patch; do
            info "  Applying: $(basename "${patch}")"
            if patch -p1 --forward --dry-run < "${patch}" &>/dev/null; then
                patch -p1 --forward < "${patch}"
                ok "  Applied: $(basename "${patch}")"
            else
                warn "  Skipping (already applied or conflict): $(basename "${patch}")"
            fi
        done < <(find "${patches_dir}" -name '*.diff' -o -name '*.patch' | sort -z)
    else
        info "No patches/ directory for ${tool} — skipping patch step"
        info "  To add patches: place .diff files in ${patches_dir}/"
    fi
}

for tool in "${TOOLS[@]}"; do
    cd "${SRC_DIR}/${tool}"
    apply_patches "${tool}"
done

# ── 4. Copy config.def.h → config.h ──────────────────────────────────────────
for tool in "${TOOLS[@]}"; do
    CONFIG_DEF="${SRC_DIR}/${tool}/config.def.h"
    CONFIG_H="${SRC_DIR}/${tool}/config.h"

    if [[ -f "${CONFIG_H}" ]]; then
        ok "${tool}/config.h already exists — not overwriting"
        info "  Edit ${CONFIG_H} to customise, then re-run this script to rebuild"
    else
        info "Copying config.def.h → config.h for ${tool}…"
        cp "${CONFIG_DEF}" "${CONFIG_H}"
        ok "${tool}/config.h created"
    fi
done

# ── 5. Build and install each tool ───────────────────────────────────────────
for tool in "${TOOLS[@]}"; do
    info "Building ${tool}…"
    cd "${SRC_DIR}/${tool}"
    sudo make clean install
    ok "${tool} built and installed"
done

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
ok "Suckless tools built and installed."
echo ""
for tool in "${TOOLS[@]}"; do
    echo -e "  • ${tool}: $(command -v "${tool}" 2>/dev/null || echo 'not found in PATH')"
done
echo ""
info "Next step: bash scripts/dwm/04-xinitrc.sh"

#!/usr/bin/env bash
# =============================================================================
# scripts/common/rebuild-clean.sh
# Description: Deep @world update, orphan removal, reverse-dependency rebuild,
#              and preserved-library rebuild.  Run after any major USE flag
#              or make.conf change to ensure the system is fully consistent.
# Usage:       sudo bash scripts/common/rebuild-clean.sh
# =============================================================================
set -euo pipefail

# ── Source shared colour helpers ──────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=detect-hardware.sh
source "${SCRIPT_DIR}/detect-hardware.sh"

# ── Root check ────────────────────────────────────────────────────────────────
if [[ "${EUID}" -ne 0 ]]; then
    error "This script must be run as root."
    exit 1
fi

# ── Banner ────────────────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  ${GREEN}Gentoo — Rebuild & Deep Clean${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "  Steps this script will run:"
echo "    [1] emerge --sync               — refresh Portage tree"
echo "    [2] emerge @world (deep)        — rebuild all packages against new USE/CFLAGS"
echo "    [3] emerge --depclean           — remove orphaned packages"
echo "    [4] revdep-rebuild              — fix broken reverse dependencies"
echo "    [5] emerge @preserved-rebuild   — rebuild against preserved libraries"
echo ""
warn "Step [2] may take a very long time on a first run."
echo ""
read -rp "  Continue? [Y/n]: " yn
yn="${yn:-Y}"
if [[ "${yn}" =~ ^[Nn]$ ]]; then
    info "Aborted."
    exit 0
fi

# ── Helper: section header ─────────────────────────────────────────────────────
section() {
    echo ""
    echo -e "${CYAN}──────────────────────────────────────────────────────────${NC}"
    echo -e "  ${GREEN}$*${NC}"
    echo -e "${CYAN}──────────────────────────────────────────────────────────${NC}"
}

# ═════════════════════════════════════════════════════════════════════════════
# Step 1 — Sync Portage tree
# ═════════════════════════════════════════════════════════════════════════════
section "Step 1 — Sync Portage tree"
emaint sync -a
ok "Portage tree synced"

# ═════════════════════════════════════════════════════════════════════════════
# Step 2 — Deep @world rebuild
# ═════════════════════════════════════════════════════════════════════════════
section "Step 2 — Deep @world rebuild"
info "Updating every installed package against current USE flags and CFLAGS…"
warn "Review the package list carefully. This may take a long time."
emerge --ask --verbose --update --deep --newuse @world
ok "@world rebuild complete"

# ═════════════════════════════════════════════════════════════════════════════
# Step 3 — Remove orphaned packages
# ═════════════════════════════════════════════════════════════════════════════
section "Step 3 — Remove orphaned packages (depclean)"
info "Removing packages that are no longer needed by anything in @world…"
emerge --ask --depclean
ok "depclean complete"

# ═════════════════════════════════════════════════════════════════════════════
# Step 4 — Reverse-dependency rebuild (revdep-rebuild)
# ═════════════════════════════════════════════════════════════════════════════
section "Step 4 — Reverse-dependency rebuild (revdep-rebuild)"

if ! command -v revdep-rebuild &>/dev/null; then
    warn "revdep-rebuild not found (part of app-portage/gentoolkit)."
    info "Installing app-portage/gentoolkit…"
    emerge --ask app-portage/gentoolkit
fi

info "Scanning for broken reverse dependencies and rebuilding…"
revdep-rebuild -- --ask
ok "revdep-rebuild complete"

# ═════════════════════════════════════════════════════════════════════════════
# Step 5 — Preserved-library rebuild
# ═════════════════════════════════════════════════════════════════════════════
section "Step 5 — Preserved-library rebuild"

# Check whether any preserved-rebuild targets exist before attempting
PRESERVED=$(emerge --pretend @preserved-rebuild 2>/dev/null | grep -c "ebuild" || true)
if [[ "${PRESERVED}" -gt 0 ]]; then
    info "Found ${PRESERVED} package(s) linked against preserved libraries — rebuilding…"
    emerge --ask @preserved-rebuild
    ok "preserved-rebuild complete"
else
    ok "No preserved-rebuild targets — system is clean"
fi

# ═════════════════════════════════════════════════════════════════════════════
# Summary
# ═════════════════════════════════════════════════════════════════════════════
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
ok "Rebuild & deep clean complete."
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "  Completed:"
echo "    ✔  Portage tree synced"
echo "    ✔  @world rebuilt with latest USE flags and CFLAGS"
echo "    ✔  Orphaned packages removed (depclean)"
echo "    ✔  Broken reverse dependencies rebuilt (revdep-rebuild)"
echo "    ✔  Preserved-library packages rebuilt"
echo ""
info "It is safe to reboot now."
echo ""

#!/usr/bin/env bash
# =============================================================================
# scripts/common/rebuild-clean.sh
# Description: Deep @world update, orphan removal, reverse-dependency rebuild,
#              preserved-library rebuild, and optional cleanup.  Run after any
#              major USE flag or make.conf change.
# Usage:       sudo bash scripts/common/rebuild-clean.sh
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=detect-hardware.sh
source "${SCRIPT_DIR}/detect-hardware.sh"

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

# ── Pre-flight checks ────────────────────────────────────────────────────────
check_system_clock || true

echo "  Steps this script will run:"
echo "    [1] emerge --sync               — refresh Portage tree"
echo "    [2] emerge @world (deep)        — rebuild all packages"
echo "    [3] emerge --depclean           — remove orphans"
echo "    [4] revdep-rebuild              — fix broken reverse deps"
echo "    [5] emerge @preserved-rebuild   — rebuild preserved libs"
echo "    [6] Rebuild kernel modules      — @module-rebuild"
echo "    [7] Clean distfiles & packages  — free disk space"
echo ""
warn "Step [2] may take a very long time on a first run."
echo ""
read -rp "  Continue? [Y/n]: " yn
yn="${yn:-Y}"
if [[ "${yn}" =~ ^[Nn]$ ]]; then
    info "Aborted."
    exit 0
fi

section() {
    echo ""
    echo -e "${CYAN}──────────────────────────────────────────────────────────${NC}"
    echo -e "  ${GREEN}$*${NC}"
    echo -e "${CYAN}──────────────────────────────────────────────────────────${NC}"
}

# ── Step 1: Sync ──────────────────────────────────────────────────────────────
section "Step 1 — Sync Portage tree"
emaint sync -a
ok "Portage tree synced"

# ── Step 2: @world ────────────────────────────────────────────────────────────
section "Step 2 — Deep @world rebuild"
info "Updating every installed package against current USE flags and CFLAGS…"
warn "Review the package list carefully."
emerge --ask --verbose --update --deep --newuse @world
ok "@world rebuild complete"

# ── Step 3: depclean ──────────────────────────────────────────────────────────
section "Step 3 — Remove orphaned packages (depclean)"
emerge --ask --depclean
ok "depclean complete"

# ── Step 4: revdep-rebuild ────────────────────────────────────────────────────
section "Step 4 — Reverse-dependency rebuild"
if ! command -v revdep-rebuild &>/dev/null; then
    warn "revdep-rebuild not found (app-portage/gentoolkit)"
    info "Installing gentoolkit…"
    emerge --ask app-portage/gentoolkit
fi
revdep-rebuild -- --ask
ok "revdep-rebuild complete"

# ── Step 5: preserved-rebuild ─────────────────────────────────────────────────
section "Step 5 — Preserved-library rebuild"
PRESERVED=$(emerge --pretend @preserved-rebuild 2>/dev/null | grep -c "ebuild" || true)
if [[ "${PRESERVED}" -gt 0 ]]; then
    info "Found ${PRESERVED} package(s) linked against preserved libraries…"
    emerge --ask @preserved-rebuild
    ok "preserved-rebuild complete"
else
    ok "No preserved-rebuild targets — system is clean"
fi

# ── Step 6: module-rebuild ────────────────────────────────────────────────────
section "Step 6 — Rebuild kernel modules"
MOD_COUNT=$(emerge --pretend @module-rebuild 2>/dev/null | grep -c "ebuild" || true)
if [[ "${MOD_COUNT}" -gt 0 ]]; then
    info "Rebuilding ${MOD_COUNT} external kernel module(s)…"
    emerge --ask @module-rebuild
    ok "module-rebuild complete"
else
    ok "No external kernel modules to rebuild"
fi

# ── Step 7: cleanup ──────────────────────────────────────────────────────────
section "Step 7 — Clean distfiles & binary packages"
if command -v eclean &>/dev/null; then
    read -rp "  Clean old distfiles and binary packages? [Y/n]: " yn
    yn="${yn:-Y}"
    if [[ ! "${yn}" =~ ^[Nn]$ ]]; then
        eclean distfiles
        eclean packages
        ok "Distfiles and packages cleaned"
    fi
else
    warn "eclean not found — install app-portage/gentoolkit for cleanup"
fi

# Clean portage temp
if [[ -d /var/tmp/portage ]]; then
    tmp_size=$(du -sh /var/tmp/portage 2>/dev/null | awk '{print $1}')
    if [[ "${tmp_size}" != "0" && "${tmp_size}" != "4.0K" ]]; then
        read -rp "  Clean Portage temp (/var/tmp/portage, ${tmp_size})? [Y/n]: " yn
        yn="${yn:-Y}"
        if [[ ! "${yn}" =~ ^[Nn]$ ]]; then
            rm -rf /var/tmp/portage/*
            ok "Portage temp cleaned"
        fi
    fi
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
ok "Rebuild & deep clean complete."
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "  ✔  Portage tree synced"
echo "  ✔  @world rebuilt with latest USE/CFLAGS"
echo "  ✔  Orphaned packages removed"
echo "  ✔  Broken reverse dependencies fixed"
echo "  ✔  Preserved-library packages rebuilt"
echo "  ✔  Kernel modules rebuilt"
echo "  ✔  Old distfiles cleaned"
echo ""

# Disk usage summary
echo "  Disk usage:"
df -h / /boot /home /var 2>/dev/null | awk 'NR==1||/\// {printf "    %-20s %6s / %6s (%s)\n", $6, $3, $2, $5}' || true
echo ""
info "It is safe to reboot now."
echo ""

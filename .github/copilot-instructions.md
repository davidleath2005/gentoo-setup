# Copilot Instructions for `gentoo-setup`

## Project purpose and architecture
- This repo is an **interactive, resumable Gentoo post-install orchestrator** for two paths: KDE Plasma and DWM/suckless.
- **Target hardware**: AMD Ryzen 9 9800X3D (Zen 5) + Radeon RX 7800 XT (RDNA 3) + ASRock B870 Taichi Lite.
- **Boot method**: UEFI / EFI stub (NO GRUB). System uses efibootmgr directly.
- **Init system**: OpenRC + elogind (NOT systemd).
- Entry point is `setup.sh`, a menu-driven wizard that scans the system and shows ●/○ status for each step.
- Flow is split by privilege:
  - **root scripts**: system package/service/config changes (`scripts/common/*`, `scripts/kde/*`, `scripts/dwm/01-02*`).
  - **user scripts**: home-directory and suckless source changes (`scripts/dwm/03-build-suckless.sh`, `scripts/dwm/04-xinitrc.sh`).
- `scripts/common/detect-hardware.sh` provides shared helpers sourced by all scripts.
- Docs in `docs/` are detailed manuals; scripts are the executable source of truth.

## Critical workflows (what to run)
- Full guided flow: `sudo bash setup.sh` — interactive menu, detects what's done, picks up where left off.
- DWM direct flow:
  1. `sudo bash scripts/dwm/01-make-conf.sh`
  2. `sudo bash scripts/dwm/02-deps.sh`
  3. `bash scripts/dwm/03-build-suckless.sh` (non-root)
  4. `bash scripts/dwm/04-xinitrc.sh` (non-root)
- KDE direct flow:
  1. `sudo bash scripts/kde/01-make-conf.sh`
  2. `sudo bash scripts/kde/02-install-plasma.sh`
  3. `sudo bash scripts/kde/03-services.sh <user>`
- Maintenance: `sudo bash scripts/common/rebuild-clean.sh`
- Kernel update: `sudo bash scripts/common/kernel-update.sh`
- System info: `bash scripts/common/system-info.sh`

## Repo-specific coding conventions
- All scripts use `set -euo pipefail` and fail-fast root/user checks.
- Keep **interactive confirmations** (`read -rp`, defaults like `[Y/n]`) for risky actions.
- Reuse shared helpers from `scripts/common/detect-hardware.sh`:
  - `set_var` for idempotent make.conf updates.
  - `detect_cpu_arch`, `check_gcc_version`, `detect_cpu_flags`, `detect_video_cards`.
  - `detect_boot_method`, `detect_esp`, `check_system_clock`.
  - `is_service_enabled`, `pkg_installed`, `check_essential_services`.
  - `print_hardware_summary` for banner displays.
- Preserve idempotency: backup before overwrite, skip if already configured, ●/○ status indicators.
- Keep colorized log helpers (`info/warn/ok/error`) consistent.
- **NEVER** assume GRUB — always use `detect_boot_method()` and handle efistub/efibootmgr.

## Hardware-specific notes
- CPU: Zen 5, Family 0x1A → `-march=znver5` (with znver4/znver3 fallback if GCC too old).
- GPU: RDNA 3 Navi 32 → `VIDEO_CARDS="amdgpu radeonsi"`, needs `sys-kernel/linux-firmware` up-to-date.
- Board: ASRock B870 Taichi Lite → EFI boot, no legacy BIOS support assumed.
- Audio: ALSA (kernel) + PipeWire (user-space) + WirePlumber (session manager). No PulseAudio.
- Essential USE flags: `elogind dbus alsa pipewire sound-server vulkan vaapi -systemd`.

## Integration points
- Gentoo/OpenRC: `emerge`, `emaint`, `eselect`, `rc-update`, `revdep-rebuild`, `efibootmgr`.
- DWM uses **flexipatch** from local `suckless/` directory (NOT downloaded from suckless.org).
- Suckless tools: `suckless/dwm-flexipatch/`, `suckless/st-flexipatch/`, `suckless/dmenu-flexipatch/`.
- Essential services: dbus (default), elogind (boot), cronie (default).
- Audio: PipeWire + WirePlumber run in user-space (started from xinitrc/autostart, NOT system services).

## When making changes
- If touching boot logic, support efistub + efibootmgr + systemd-boot + GRUB (don't assume any one).
- If changing package lists or USE flags, update `docs/kde-plasma.md` or `docs/dwm-suckless.md`.
- Validate: `bash -n setup.sh scripts/common/*.sh scripts/kde/*.sh scripts/dwm/*.sh`
- No test suite; validate by syntax check and dry-run reasoning.

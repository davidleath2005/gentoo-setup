# Gentoo Setup Guides

A collection of post-install Gentoo Linux setup guides and helper scripts.

Assumes a completed base install with:
- Stage 3 OpenRC Minimal
- Kernel compiled from source (gentoo-sources / dist-kernel)
- Bootloader configured (EFI stub / efibootmgr / systemd-boot / GRUB)
- Working network & locale

## Guides

| Guide | Description |
|-------|-------------|
| [KDE Plasma](docs/kde-plasma.md) | Full KDE Plasma 6 desktop environment |
| [DWM / Suckless](docs/dwm-suckless.md) | Minimal suckless WM stack (dwm + st + dmenu) |

## Quick Start

Run the interactive setup wizard as root — it will guide you through every step:

```bash
sudo bash setup.sh
```

To perform a deep rebuild and clean after any USE flag or make.conf change:

```bash
sudo bash scripts/common/rebuild-clean.sh
```

## Scripts

Helper scripts live in `scripts/`. They are modular — run only what you need,
or use `setup.sh` to orchestrate them interactively.

| Script | Purpose |
|--------|---------|
| `setup.sh` | **Interactive wizard** — select KDE or DWM and run all steps |
| `scripts/kde/01-make-conf.sh` | Configure make.conf for KDE (auto-detects CPU/GPU) |
| `scripts/kde/02-install-plasma.sh` | Install KDE Plasma 6 |
| `scripts/kde/03-services.sh` | Enable KDE/display manager services |
| `scripts/dwm/01-make-conf.sh` | Configure make.conf for DWM (auto-detects CPU/GPU) |
| `scripts/dwm/02-deps.sh` | Install Xorg and build dependencies |
| `scripts/dwm/03-build-suckless.sh` | Clone, patch, and build dwm/st/dmenu |
| `scripts/dwm/04-xinitrc.sh` | Set up .xinitrc and auto-startx |
| `scripts/common/add-user.sh` | Create a standard user with correct groups |
| `scripts/common/detect-hardware.sh` | Shared CPU/GPU detection helpers (sourced by other scripts) |
| `scripts/common/rebuild-clean.sh` | Deep @world rebuild, depclean, revdep-rebuild, preserved-rebuild |
| `scripts/common/kernel-update.sh` | Kernel update with EFI stub / GRUB / systemd-boot support |
| `scripts/common/system-info.sh` | System info: hardware, boot, services, audio, packages |
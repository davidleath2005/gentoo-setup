# Gentoo Setup Guides

A collection of post-install Gentoo Linux setup guides and helper scripts.

Assumes a completed base install with:
- Stage 3 OpenRC Minimal
- Kernel compiled from source (gentoo-sources / dist-kernel)
- GRUB bootloader configured
- Working network & locale

## Guides

| Guide | Description |
|-------|-------------|
| [KDE Plasma](docs/kde-plasma.md) | Full KDE Plasma 6 desktop environment |
| [DWM / Suckless](docs/dwm-suckless.md) | Minimal suckless WM stack (dwm + st + dmenu) |

## Scripts

Helper scripts live in `scripts/`. They are modular — run only what you need.

| Script | Purpose |
|--------|---------|
| `scripts/kde/01-make-conf.sh` | Configure make.conf for KDE |
| `scripts/kde/02-install-plasma.sh` | Install KDE Plasma 6 |
| `scripts/kde/03-services.sh` | Enable KDE/display manager services |
| `scripts/dwm/01-make-conf.sh` | Configure make.conf for DWM |
| `scripts/dwm/02-deps.sh` | Install Xorg and build dependencies |
| `scripts/dwm/03-build-suckless.sh` | Clone, patch, and build dwm/st/dmenu |
| `scripts/dwm/04-xinitrc.sh` | Set up .xinitrc and auto-startx |
| `scripts/common/add-user.sh` | Create a standard user with correct groups |
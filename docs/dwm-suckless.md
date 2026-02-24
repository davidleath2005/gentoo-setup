# DWM + Suckless Stack on Gentoo Linux (OpenRC)

A comprehensive guide for setting up a minimal, fast, and highly customisable desktop using **dwm**, **st**, and **dmenu** from [suckless.org](https://suckless.org) on Gentoo with OpenRC.

---

## Table of Contents

1. [Philosophy](#philosophy)
2. [Prerequisites](#prerequisites)
3. [Step 1 — make.conf for Minimal X](#step-1--makeconf-for-minimal-x)
4. [Step 2 — Install Xorg and Dependencies](#step-2--install-xorg-and-dependencies)
5. [Step 3 — Install Fonts](#step-3--install-fonts)
6. [Step 4 — Clone Suckless Repos](#step-4--clone-suckless-repos)
7. [Step 5 — Configure config.h](#step-5--configure-configh)
8. [Step 6 — Patching](#step-6--patching)
9. [Step 7 — Build & Install](#step-7--build--install)
10. [Step 8 — .xinitrc Setup](#step-8--xinitrc-setup)
11. [Step 9 — Auto-startx on TTY Login](#step-9--auto-startx-on-tty-login)
12. [Step 10 — Recommended Extras](#step-10--recommended-extras)

---

## Philosophy

The [suckless](https://suckless.org/philosophy/) philosophy centres on software that is:

- **Small** — measured in lines of code, not features
- **Simple** — a single C source file you can read and understand
- **Hackable** — configured by editing `config.h` directly, not through config files or GUIs

Instead of a traditional package manager workflow, you **fork the source**, make it yours, and rebuild. Patches from the suckless community allow you to add features without bloat.

> ℹ️ This means every time you want to change a key binding, colour, or font, you edit C code and recompile. This is intentional — it keeps the codebase lean and gives you full understanding of your tools.

---

## Prerequisites

- [ ] Stage 3 OpenRC Minimal install completed
- [ ] Kernel compiled with framebuffer and input device support
- [ ] Working network connection
- [ ] Portage tree synced (`emaint sync -a`)
- [ ] `git` installed (`emerge dev-vcs/git`)

---

## Step 1 — make.conf for Minimal X

Set lean USE flags that enable X without pulling in heavy desktop environments.

> ℹ️ The helper script [`scripts/dwm/01-make-conf.sh`](../scripts/dwm/01-make-conf.sh) configures this automatically. It will:
> - Detect your CPU microarchitecture and set optimal `CFLAGS` (`-march=znver5` for Zen 5, etc.)
> - Detect CPU instruction-set flags via `cpuid2cpuflags` (or fall back to `/proc/cpuinfo`) and set `CPU_FLAGS_X86`
> - Detect your GPU and set `VIDEO_CARDS` (e.g. `amdgpu radeonsi` for RDNA 3)
> - Set `ACCEPT_KEYWORDS="~amd64"` for cutting-edge hardware support

Edit `/etc/portage/make.conf`:

```bash
# Compiler optimisation — script auto-detects -march for your CPU
# (values below are for an AMD Ryzen 9 9800X3D)
CFLAGS="-march=znver5 -O2 -pipe"
CXXFLAGS="${CFLAGS}"

# CPU instruction-set flags — auto-detected by the script
CPU_FLAGS_X86="aes avx avx2 avx512f avx512dq avx512cd avx512bw avx512vl avx512vbmi avx512vbmi2 bmi1 bmi2 f16c fma3 mmx mmxext pclmul popcnt rdrand sha sse sse2 sse3 sse4_1 sse4_2 sse4a ssse3"

# Minimal X USE flags — no KDE, GNOME, GTK, or Plasma
# vulkan for picom GLX/Vulkan backend and Vulkan apps; vaapi for GPU video decode
# pipewire + sound-server for modern audio (replaces PulseAudio)
USE="X -kde -gnome -plasma alsa pipewire sound-server vulkan vaapi"

# Set VIDEO_CARDS for your hardware:
#   amdgpu radeonsi  — AMD Radeon (GCN+/RDNA)
#   nvidia           — NVIDIA proprietary
#   intel i965 iris  — Intel integrated
VIDEO_CARDS="amdgpu radeonsi"
INPUT_DEVICES="libinput"

# Build parallelism
MAKEOPTS="-j$(nproc) -l$(nproc)"

ACCEPT_LICENSE="*"

# ~amd64 (testing branch) — required for latest Mesa, linux-firmware, and
# kernel support on cutting-edge hardware like Zen 5 and RDNA 3
ACCEPT_KEYWORDS="~amd64"
```

> ⚠️ The `-kde -gnome -plasma` flags prevent Portage from pulling in heavy dependencies. Keep this list if you want a genuinely minimal system.

---

## Step 2 — Install Xorg and Dependencies

> ℹ️ The helper script [`scripts/dwm/02-deps.sh`](../scripts/dwm/02-deps.sh) installs all dependencies in one step.

### Xorg server and xinit

```bash
emerge --ask x11-base/xorg-server x11-apps/xinit
```

### Build-time libraries required by dwm, st, and dmenu

```bash
emerge --ask \
    x11-libs/libX11 \
    x11-libs/libXft \
    x11-libs/libXinerama \
    x11-libs/libXrender \
    media-libs/fontconfig \
    media-libs/freetype
```

| Library | Used by |
|---------|---------|
| `libX11` | All three (dwm, st, dmenu) |
| `libXft` | dwm, dmenu (font rendering) |
| `libXinerama` | dwm (multi-monitor support) |
| `libXrender` | dwm, dmenu |
| `fontconfig` | dwm, st, dmenu |
| `freetype` | libXft dependency |

Verify Xorg is installed:

```bash
Xorg -version
```

---

## Step 3 — Install Fonts

dwm and st use X core fonts or Xft fonts. Install a good selection:

```bash
emerge --ask \
    media-fonts/terminus-font \
    media-fonts/dejavu \
    media-fonts/noto \
    media-fonts/noto-emoji
```

Rebuild the font cache:

```bash
fc-cache -fv
```

List available fonts (to use in `config.h`):

```bash
fc-list | grep -i terminus
fc-list | grep -i "DejaVu Sans Mono"
```

> ℹ️ A common dwm font setting is `"monospace:size=10"` which uses fontconfig to resolve the best monospace font available.

---

## Step 4 — Suckless Source Trees (Flexipatch)

> **This project uses [flexipatch](https://github.com/bakkeby/dwm-flexipatch)** — a fork that lets you enable/disable patches via `#define` in `patches.h` instead of manually applying `.diff` files. The source trees are included in the repo under `suckless/`.

The three tools live in the repo:

```
suckless/
├── dwm-flexipatch/     # dwm with ~300 patches available
├── st-flexipatch/      # st with ~60 patches available
└── dmenu-flexipatch/   # dmenu with ~30 patches available
```

If the directories are empty, clone them:

```bash
cd suckless/
git clone https://github.com/bakkeby/dwm-flexipatch.git
git clone https://github.com/bakkeby/st-flexipatch.git
git clone https://github.com/bakkeby/dmenu-flexipatch.git
```

> No need to clone from `git.suckless.org` — flexipatch includes all upstream code plus the patch system.

---

## Step 5 — Configure config.h

Each flexipatch tool is configured by editing two files:
- **`patches.h`** — enable/disable patches with `#define` (1 = on, 0 = off)
- **`config.h`** — colours, fonts, key bindings, layout options

### Workflow

```bash
cd suckless/dwm-flexipatch

# First time: copy defaults
cp patches.def.h patches.h
cp config.def.h config.h

# Edit patches.h to enable features
$EDITOR patches.h

# Edit config.h for visual/behaviour customisation
$EDITOR config.h

# Rebuild
sudo make clean install
```

Repeat for `st-flexipatch` and `dmenu-flexipatch`.

### This project's config.h setup

The repo ships pre-configured `patches.h` and `config.h` files with:

- **dwm**: Gruvbox Material Dark theme, Super key, fullgaps, pertag, systray, alpha bar, vanity gaps, ~40 patches enabled
- **st**: Gruvbox colours, alpha 0.92, scrollback, clipboard, font size shortcuts, ~18 patches enabled
- **dmenu**: Centered, fuzzy matching, highlight, Gruvbox colours, ~10 patches enabled

> ℹ️ Changes to `config.h` or `patches.h` require a recompile: `sudo make clean install`. Build times are measured in seconds.

---

## Step 6 — Enabling Patches (Flexipatch)

With flexipatch, you **do not** download `.diff` files. Instead, edit `patches.h` and set defines to `1`:

```c
// patches.h — enable desired patches
#define BAR_ALPHA_PATCH 1
#define BAR_SYSTRAY_PATCH 1
#define FULLGAPS_PATCH 1
#define PERTAG_PATCH 1
#define VANITYGAPS_PATCH 1
```

### Popular dwm-flexipatch patches

| Define | Effect |
|--------|--------|
| `FULLGAPS_PATCH` | Configurable gaps between windows |
| `BAR_ALPHA_PATCH` | True transparency for the bar |
| `PERTAG_PATCH` | Per-tag layout settings |
| `BAR_SYSTRAY_PATCH` | System tray in the bar |
| `VANITYGAPS_PATCH` | Inner/outer gaps |
| `STICKY_PATCH` | Sticky windows visible on all tags |
| `SCRATCHPADS_PATCH` | Dropdown terminal / scratchpad windows |

### Popular st-flexipatch patches

| Define | Effect |
|--------|--------|
| `SCROLLBACK_PATCH` | Mouse/keyboard scroll through history |
| `ALPHA_PATCH` | Background transparency |
| `BOLD_IS_NOT_BRIGHT_PATCH` | Better colour handling |
| `CLIPBOARD_PATCH` | Sync clipboard and primary selection |
| `FONT2_PATCH` | Fallback font support |

### Rebuild after changing patches

```bash
cd suckless/dwm-flexipatch
sudo make clean install
```

> Each patch adds its code conditionally via `#if` directives — no merge conflicts, no `.rej` files.

---

## Step 7 — Build & Install

Build and install each tool. Repeat whenever you change `config.h` or apply patches.

```bash
# Build and install all three tools (automated)
bash scripts/dwm/03-build-suckless.sh

# Or manually per-tool:
cd suckless/dwm-flexipatch
sudo make clean install

cd suckless/st-flexipatch
sudo make clean install

cd suckless/dmenu-flexipatch
sudo make clean install
```

Verify installation:

```bash
which dwm st dmenu_run
dwm -v
st -v
```

> ℹ️ `make clean` removes previous build artifacts, ensuring a fresh compile. Always use `make clean install` rather than just `make install` after configuration changes.

---

## Step 8 — .xinitrc Setup

> ℹ️ The helper script [`scripts/dwm/04-xinitrc.sh`](../scripts/dwm/04-xinitrc.sh) creates `.xinitrc` and adds the auto-startx snippet automatically.

Create `~/.xinitrc` (or run [`scripts/dwm/04-xinitrc.sh`](../scripts/dwm/04-xinitrc.sh) which generates a full version):

```bash
cat > ~/.xinitrc <<'EOF'
#!/bin/sh

# D-Bus session (required for elogind, polkit, notifications)
if command -v dbus-launch >/dev/null 2>&1 && [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
    eval "$(dbus-launch --sh-syntax --exit-with-x11)"
fi

# Audio — PipeWire + WirePlumber
pipewire &
sleep 0.2
pipewire-pulse &
wireplumber &

# Wallpaper
xwallpaper --zoom ~/Pictures/wallpaper.png &

# Compositor
picom --backend glx --vsync &

# Notification daemon
dunst &

# Status bar
while true; do
    MEM=$(free -h | awk '/^Mem:/ {printf "%s/%s", $3, $2}')
    DT=$(date '+%a %d %b %H:%M')
    xsetroot -name " ${MEM} | ${DT} "
    sleep 2
done &

# Launch dwm (restart loop — survives mod+shift+q restart)
while true; do
    dwm 2>/dev/null
    sleep 0.5
done
EOF
chmod +x ~/.xinitrc
```

> The setup script generates a more complete version with CPU temperature (k10temp), volume (via `wpctl`), and auto-startx in `~/.bash_profile`.

### Autostart pattern

Start background processes before the dwm loop:

```sh
picom --backend glx --vsync &
dunst &
# dwm restart loop
while true; do dwm; sleep 0.5; done
```

> ⚠️ The dwm restart loop replaces `exec dwm` — it allows dwm to restart without logging you out.

---

## Step 9 — Auto-startx on TTY Login

Add the following to `~/.bash_profile` to automatically start X when logging in on TTY1:

```bash
cat >> ~/.bash_profile <<'EOF'

# Auto-start X on TTY1
if [ -z "${DISPLAY}" ] && [ "${XDG_VTNR}" -eq 1 ]; then
    exec startx
fi
EOF
```

> ⚠️ This uses `exec startx` which replaces the shell process. If Xorg exits unexpectedly you will be returned to the login prompt, not a broken terminal.

To apply, log out and log back in on TTY1. X will start automatically.

---

## Step 10 — Recommended Extras

### Audio — ALSA + PipeWire

The modern audio stack for Gentoo is **ALSA** (kernel-level driver) + **PipeWire** (user-space audio server) + **WirePlumber** (session manager). PipeWire replaces PulseAudio and offers lower latency, better Bluetooth support, and screen-sharing capabilities.

```bash
# Install audio packages
emerge --ask media-libs/alsa-lib media-sound/alsa-utils media-plugins/alsa-plugins media-video/pipewire media-video/wireplumber
```

**Unmute ALSA** (first-time setup — ALSA defaults to muted):

```bash
amixer sset Master unmute
amixer sset Master 80%
# Use alsamixer for an interactive TUI:
alsamixer
```

PipeWire runs in user-space and should be started from `.xinitrc` (the setup script does this automatically):

```sh
# In ~/.xinitrc, before exec dwm:
pipewire &
sleep 0.2
pipewire-pulse &   # PulseAudio compatibility
wireplumber &       # session manager
```

**Kernel requirements** (B870 Taichi / Realtek ALC codec):

```
CONFIG_SND=y
CONFIG_SND_HDA_INTEL=m
CONFIG_SND_HDA_CODEC_REALTEK=m
CONFIG_SND_HDA_CODEC_HDMI=m    # HDMI/DP audio from RX 7800 XT
CONFIG_SND_USB_AUDIO=m          # USB headsets/DACs
```

Verify sound cards are detected:

```bash
cat /proc/asound/cards
aplay -l
wpctl status    # WirePlumber status
```

### Status bar

The `xsetroot -name` approach in `.xinitrc` already provides a basic clock. Extend it:

```sh
# ~/.local/bin/statusbar
#!/bin/sh
while true; do
    DATETIME=$(date '+%a %d %b %H:%M')
    BATTERY=$(cat /sys/class/power_supply/BAT0/capacity 2>/dev/null && echo "%" || echo "AC")
    xsetroot -name "${BATTERY} | ${DATETIME}"
    sleep 5
done
```

### Compositor — picom

```bash
emerge --ask x11-misc/picom
```

Add to `.xinitrc` before `exec dwm`:

```sh
picom --backend glx --vsync &
```

### Wallpaper

```bash
# feh
emerge --ask media-gfx/feh
# In .xinitrc:
feh --bg-fill ~/Pictures/wallpaper.jpg &

# xwallpaper (lighter alternative)
emerge --ask x11-misc/xwallpaper
# In .xinitrc:
xwallpaper --zoom ~/Pictures/wallpaper.png &
```

### File manager

```bash
# lf — terminal file manager
emerge --ask sys-apps/lf

# ranger — Python-based terminal file manager
emerge --ask app-misc/ranger
```

### Notification daemon — dunst

```bash
emerge --ask x11-misc/dunst
```

Add to `.xinitrc`:

```sh
dunst &
```

Send a test notification:

```bash
notify-send "Hello" "dunst is working"
```

### Application launcher

```bash
# dmenu_run is already installed with dmenu
# Run with: Mod+p (default dwm binding)
dmenu_run
```

---

> ✅ You now have a fully functional, minimal suckless desktop on Gentoo. For further reading, see [suckless.org](https://suckless.org), the [dwm tutorial](https://dwm.suckless.org/tutorial/), and the [Gentoo Wiki X without DE guide](https://wiki.gentoo.org/wiki/X_without_Display_Manager).

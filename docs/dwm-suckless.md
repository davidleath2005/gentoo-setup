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
USE="X -kde -gnome -plasma alsa vulkan vaapi"

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
    media-fonts/noto
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

## Step 4 — Clone Suckless Repos

> ℹ️ The helper script [`scripts/dwm/03-build-suckless.sh`](../scripts/dwm/03-build-suckless.sh) handles cloning, configuring, and building automatically.

Create a directory for your suckless source trees:

```bash
mkdir -p ~/.local/src
cd ~/.local/src
```

Clone the three core tools:

```bash
git clone https://git.suckless.org/dwm
git clone https://git.suckless.org/st
git clone https://git.suckless.org/dmenu
```

> ⚠️ `git.suckless.org` uses plain git. If the clone fails, check your network and try again. These repos are small (< 100 KB each).

---

## Step 5 — Configure config.h

Each suckless tool is configured by editing `config.h` (generated from `config.def.h`).

### Workflow

```bash
cd ~/.local/src/dwm
cp config.def.h config.h
$EDITOR config.h
```

Repeat for `st` and `dmenu`.

### Key settings in `dwm/config.h`

```c
/* Font — use fc-list to find available names */
static const char *fonts[]          = { "monospace:size=10" };

/* Terminal emulator launched by Mod+Shift+Return */
static const char *termcmd[]  = { "st", NULL };

/* Colour scheme */
static const char col_gray1[]       = "#222222";  /* background */
static const char col_gray2[]       = "#444444";  /* border normal */
static const char col_gray3[]       = "#bbbbbb";  /* foreground */
static const char col_gray4[]       = "#eeeeee";  /* selected foreground */
static const char col_cyan[]        = "#005577";  /* selected background */
```

### Key settings in `st/config.h`

```c
/* Font — should match dwm for visual consistency */
static char *font = "monospace:pixelsize=14:antialias=true:autohint=true";

/* Shell */
static char *shell = "/bin/bash";

/* Colours (gruvbox dark example) */
static const char *colorname[] = {
    "#282828",   /* hard black */
    "#cc241d",   /* red */
    /* ... */
};
```

### Key settings in `dmenu/config.h`

```c
/* Font — must match dwm */
static const char *fonts[] = { "monospace:size=10" };

/* Position: top (0) or bottom (1) of screen */
static int topbar = 1;
```

> ℹ️ Changes to `config.h` require a recompile and reinstall. This is normal — build times are measured in seconds.

---

## Step 6 — Patching

Patches extend suckless tools without modifying core logic. Download patches from [https://dwm.suckless.org/patches/](https://dwm.suckless.org/patches/).

### Applying a patch

```bash
cd ~/.local/src/dwm

# Download a patch (example: fullgaps)
curl -O https://dwm.suckless.org/patches/fullgaps/dwm-fullgaps-20200508-7b77734.diff

# Apply with patch utility
patch -p1 < dwm-fullgaps-20200508-7b77734.diff
```

### Popular dwm patches

| Patch | Effect |
|-------|--------|
| `fullgaps` | Adds configurable gaps between windows |
| `alpha` | Adds true transparency to the bar |
| `pertag` | Per-tag layout settings |
| `autostart` | Run commands from `~/.dwm/autostart.sh` |
| `systray` | System tray in the status bar |

### Popular st patches

| Patch | Effect |
|-------|--------|
| `scrollback` | Mouse/keyboard scroll through terminal history |
| `alpha` | Background transparency |
| `bold-is-not-bright` | Better colour handling |
| `clipboard` | Sync clipboard and primary selection |

### Resolving conflicts

If a patch does not apply cleanly:

```bash
# patch will create .rej files showing the failed hunks
ls *.rej

# Edit the target file manually to apply the rejected hunks
# Then remove .rej files
rm *.rej
```

> ⚠️ Conflicts are common when applying multiple patches. Apply them one at a time and resolve conflicts before moving to the next.

---

## Step 7 — Build & Install

Build and install each tool. Repeat whenever you change `config.h` or apply patches.

```bash
# dwm
cd ~/.local/src/dwm
sudo make clean install

# st
cd ~/.local/src/st
sudo make clean install

# dmenu
cd ~/.local/src/dmenu
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

Create `~/.xinitrc`:

```bash
cat > ~/.xinitrc <<'EOF'
#!/bin/sh

# --- Monitor layout (adjust for your setup) ---
# xrandr --output HDMI-1 --mode 1920x1080 --rate 60

# --- Wallpaper ---
# feh --bg-fill ~/Pictures/wallpaper.jpg &
# xwallpaper --zoom ~/Pictures/wallpaper.png &

# --- Compositor (uncomment if installed) ---
# picom --daemon &

# --- Notification daemon ---
# dunst &

# --- Status bar (updates every second) ---
while true; do
    xsetroot -name "$(date '+%a %d %b %H:%M:%S')"
    sleep 1
done &

# --- Launch dwm ---
exec dwm
EOF
chmod +x ~/.xinitrc
```

### Autostart pattern

For persistent background processes, use a loop or start them before `exec dwm`:

```sh
# Good pattern: background & before exec
picom --daemon &
dunst &
exec dwm
```

> ⚠️ Never background `exec dwm` — it must be the last command and must not have `&`.

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

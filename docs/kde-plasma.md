# KDE Plasma 6 on Gentoo Linux (OpenRC)

A comprehensive guide for installing and configuring KDE Plasma 6 on a Gentoo base system running OpenRC.

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Step 1 — Portage Profile](#step-1--portage-profile)
3. [Step 2 — make.conf Configuration](#step-2--makeconf-configuration)
4. [Step 3 — package.accept_keywords](#step-3--packageaccept_keywords)
5. [Step 4 — System Update](#step-4--system-update)
6. [Step 5 — Install KDE Plasma](#step-5--install-kde-plasma)
7. [Step 6 — Display Manager (SDDM)](#step-6--display-manager-sddm)
8. [Step 7 — Session Management](#step-7--session-management)
9. [Step 8 — Audio](#step-8--audio)
10. [Step 9 — Networking](#step-9--networking)
11. [Step 10 — User Groups](#step-10--user-groups)
12. [Step 11 — First Boot & Troubleshooting](#step-11--first-boot--troubleshooting)

---

## Prerequisites

Before beginning, verify the following are true on your system:

- [ ] Stage 3 OpenRC Minimal install completed
- [ ] Kernel compiled from source (`sys-kernel/gentoo-sources` or `sys-kernel/dist-kernel`)
- [ ] GRUB bootloader installed and configured (`/boot/grub/grub.cfg` present)
- [ ] Working network connection (`ping -c1 gentoo.org` succeeds)
- [ ] Locale and timezone configured (`/etc/locale.gen`, `timedatectl`)
- [ ] Portage tree synced (`emerge --sync` or `emaint sync -a`)

> ℹ️ You can run the helper scripts in [`scripts/kde/`](../scripts/kde/) to automate most steps below.

---

## Step 1 — Portage Profile

Select the KDE Plasma desktop profile. This pulls in the correct default USE flags and package sets.

```bash
# List available profiles
eselect profile list

# Select the KDE Plasma / desktop profile (number may vary)
# Look for a line containing "plasma" or "desktop/plasma"
eselect profile set default/linux/amd64/23.0/desktop/plasma
```

Verify the selection:

```bash
eselect profile show
```

> ⚠️ If you do not see a `plasma` profile, ensure your Portage tree is up to date: `emaint sync -a`

---

## Step 2 — make.conf Configuration

Edit `/etc/portage/make.conf` to add the recommended settings for KDE Plasma 6.

> ℹ️ The helper script [`scripts/kde/01-make-conf.sh`](../scripts/kde/01-make-conf.sh) configures this automatically. It will:
> - Detect your CPU microarchitecture and set optimal `CFLAGS` (`-march=znver5` for Zen 5, etc.)
> - Detect CPU instruction-set flags via `cpuid2cpuflags` (or fall back to `/proc/cpuinfo`) and set `CPU_FLAGS_X86`
> - Detect your GPU and set `VIDEO_CARDS` (e.g. `amdgpu radeonsi` for RDNA 3)
> - Set `ACCEPT_KEYWORDS="~amd64"` for cutting-edge hardware support

```bash
# Recommended /etc/portage/make.conf additions
# (values below are for an AMD Ryzen 9 9800X3D + Radeon RX 7800 XT)

# Compiler optimisation — script auto-detects -march for your CPU
CFLAGS="-march=znver5 -O2 -pipe"
CXXFLAGS="${CFLAGS}"

# CPU instruction-set flags — auto-detected by the script
CPU_FLAGS_X86="aes avx avx2 avx512f avx512dq avx512cd avx512bw avx512vl avx512vbmi avx512vbmi2 bmi1 bmi2 f16c fma3 mmx mmxext pclmul popcnt rdrand sha sse sse2 sse3 sse4_1 sse4_2 sse4a ssse3"

# Global USE flags — vulkan for KWin Wayland compositing; vaapi for GPU video decode
USE="X wayland dbus elogind -systemd pulseaudio kde plasma \
     alsa bluetooth networkmanager policykit vulkan vaapi"

# GPU — auto-detected by the script
#   amdgpu radeonsi   — AMD Radeon (GCN+/RDNA)
#   nvidia            — NVIDIA proprietary
#   intel i965 iris   — Intel integrated
VIDEO_CARDS="amdgpu radeonsi"
INPUT_DEVICES="libinput"

# Build parallelism
MAKEOPTS="-j$(nproc) -l$(nproc)"

# Accept all licences (or whitelist as needed)
ACCEPT_LICENSE="*"

# ~amd64 (testing branch) — required for latest Mesa, linux-firmware, and
# kernel support on cutting-edge hardware like Zen 5 and RDNA 3
ACCEPT_KEYWORDS="~amd64"
```

Apply the changes:

```bash
# Verify syntax — no output means OK
bash -n /etc/portage/make.conf
```

---

## Step 3 — package.accept_keywords

Unmask KDE Plasma, frameworks, and applications for `~amd64` (testing branch):

```bash
mkdir -p /etc/portage/package.accept_keywords
```

Create `/etc/portage/package.accept_keywords/kde`:

```
# KDE Plasma 6
kde-plasma/*  ~amd64
kde-frameworks/*  ~amd64
kde-apps/*  ~amd64
```

```bash
cat > /etc/portage/package.accept_keywords/kde <<'EOF'
kde-plasma/*      ~amd64
kde-frameworks/*  ~amd64
kde-apps/*        ~amd64
EOF
```

> ⚠️ Using `~amd64` means you get pre-release/testing packages. This is required for KDE Plasma 6 on Gentoo until it stabilises in the tree.

---

## Step 4 — System Update

Rebuild `@world` to incorporate the new profile and USE flag changes. This step may take a significant amount of time depending on your hardware.

```bash
emerge --ask --verbose --update --deep --newuse @world
```

Expected output: A large list of packages to be rebuilt/updated. Review the list carefully and press `y` to confirm.

If you encounter blockers:

```bash
# Check for conflicts
emerge --pretend --verbose --update --deep --newuse @world 2>&1 | less

# Resolve with depclean after the update
emerge --ask --depclean
```

---

## Step 5 — Install KDE Plasma

> ℹ️ The helper script [`scripts/kde/02-install-plasma.sh`](../scripts/kde/02-install-plasma.sh) automates profile selection, keywords, and installation.

### Core Plasma desktop

```bash
emerge --ask kde-plasma/plasma-meta
```

This installs the full KDE Plasma 6 desktop, including Plasma Shell, KWin (compositor), Dolphin (file manager), and system settings.

### Optional: Full KDE Applications suite

```bash
emerge --ask kde-apps/kde-apps-meta
```

> ⚠️ `kde-apps-meta` is large (~200 packages). Consider installing individual apps instead, e.g. `kde-apps/dolphin kde-apps/konsole kde-apps/kate`.

### Verify installation

```bash
# Check that plasmashell is present
which plasmashell
plasmashell --version
```

---

## Step 6 — Display Manager (SDDM)

SDDM is the recommended display manager for KDE Plasma.

> ℹ️ The helper script [`scripts/kde/03-services.sh`](../scripts/kde/03-services.sh) installs and enables all required services.

### Install SDDM

```bash
emerge --ask gui-libs/display-manager-init x11-misc/sddm
```

### Configure SDDM

```bash
# Generate default config
sddm --example-config > /etc/sddm.conf
```

Edit `/etc/sddm.conf` to set the session:

```ini
[Autologin]
# Optional: auto-login a user
# User=yourusername
# Session=plasma

[Theme]
# Optional: install a theme with: emerge sddm-theme-breeze
# Current=breeze
```

### Enable SDDM via OpenRC

```bash
# Set SDDM as the display manager
echo 'DISPLAYMANAGER="sddm"' > /etc/conf.d/display-manager

# Add to default runlevel
rc-update add display-manager default
rc-update add elogind boot
rc-update add dbus default
```

---

## Step 7 — Session Management

KDE Plasma on OpenRC requires **elogind** (a standalone logind implementation) and **dbus**.

```bash
emerge --ask sys-auth/elogind sys-apps/dbus sys-auth/polkit
```

Enable at boot:

```bash
rc-update add elogind boot
rc-update add dbus default
```

Verify elogind is working after first boot:

```bash
loginctl session-status
```

> ⚠️ Do **not** install `systemd-utils[login]` — it conflicts with elogind on OpenRC systems.

---

## Step 8 — Audio

### Option A: PipeWire (recommended)

PipeWire handles both PulseAudio and JACK compatibility:

```bash
emerge --ask media-video/pipewire

# Install user-session launcher
emerge --ask media-video/wireplumber
```

Add to your user's autostart (or use the Plasma autostart settings):

```bash
# ~/.config/autostart-scripts/pipewire.sh
#!/bin/sh
pipewire &
pipewire-pulse &
wireplumber &
```

### Option B: PulseAudio

```bash
emerge --ask media-sound/pulseaudio

# Start at login
rc-update add pulseaudio default  # system-wide
# OR add to ~/.bash_profile for per-user
echo 'pulseaudio --start' >> ~/.bash_profile
```

Verify audio:

```bash
pactl info
aplay /usr/share/sounds/alsa/Front_Left.wav
```

---

## Step 9 — Networking

Install NetworkManager with the Plasma applet:

```bash
emerge --ask net-misc/networkmanager kde-plasma/plasma-nm
```

Enable NetworkManager:

```bash
# Disable any existing net.* scripts that may conflict
rc-update del net.eth0 default 2>/dev/null || true

rc-update add NetworkManager default
```

> ⚠️ If you previously used `net.eth0` / `dhcpcd` style networking, disable those services first to avoid conflicts.

### Verify

```bash
nmcli device status
nmcli connection show
```

---

## Step 10 — User Groups

Ensure your desktop user is a member of all required groups:

```bash
USERNAME="yourusername"  # replace with your actual username

usermod -aG video,audio,plugdev,seat,usb,input,wheel "${USERNAME}"
```

> ℹ️ The [`scripts/common/add-user.sh`](../scripts/common/add-user.sh) script can create a new user with all correct group memberships automatically.

| Group | Purpose |
|-------|---------|
| `video` | GPU/display access |
| `audio` | Sound device access |
| `plugdev` | Pluggable device access (USB drives, etc.) |
| `seat` | Seat-based device access via elogind |
| `usb` | USB device access |
| `input` | Input device access |
| `wheel` | sudo/su privilege escalation |

Verify group membership:

```bash
groups "${USERNAME}"
id "${USERNAME}"
```

---

## Step 11 — First Boot & Troubleshooting

### Starting Plasma for the first time

Reboot the system. SDDM should appear and allow you to log in to a Plasma session:

```bash
reboot
```

If the display manager does not start, check:

```bash
rc-service display-manager status
journalctl -xe  # if journald is available
cat /var/log/Xorg.0.log
```

### Wayland vs X11

At the SDDM login screen, select the session type:
- **Plasma (Wayland)** — recommended for modern hardware (AMD/Intel), better HiDPI support
- **Plasma (X11)** — fallback for NVIDIA or older hardware with stability issues

To force Wayland as default, create `/etc/environment`:

```ini
QT_QPA_PLATFORM=wayland
PLASMA_USE_QT_SCALING=1
```

### Common Issues

| Problem | Fix |
|---------|-----|
| Black screen after SDDM login | Check `~/.xsession-errors`, ensure `dbus` is running |
| No sound | Run `pavucontrol` or `pw-jack` to check PipeWire; verify group membership |
| KWin crashes | Try switching Wayland → X11 or vice versa; update GPU drivers |
| NetworkManager not showing | Ensure `plasma-nm` is installed; check `nmcli device status` |
| SDDM not starting | Verify `rc-update add display-manager default`; check `/var/log/Xorg.0.log` |
| elogind errors | Ensure no systemd packages are installed; check `loginctl` |

### Log Locations

| Log | Path |
|-----|------|
| Xorg log | `/var/log/Xorg.0.log` |
| SDDM log | `/var/log/sddm.log` |
| Plasma session errors | `~/.xsession-errors` |
| KWin debug | `QT_LOGGING_RULES="kwin*=true" kwin_x11` |
| OpenRC service log | `/var/log/rc.log` |

### Useful verification commands

```bash
# Check all required services are running
rc-service elogind status
rc-service dbus status
rc-service display-manager status
rc-service NetworkManager status

# Verify USE flags applied correctly
emerge -pv kde-plasma/plasma-meta | grep "USE="

# Check Plasma version
plasmashell --version
```

---

> ✅ At this point you should have a fully functional KDE Plasma 6 desktop on Gentoo with OpenRC. Refer to the [Gentoo KDE Project wiki](https://wiki.gentoo.org/wiki/KDE) for advanced configuration.

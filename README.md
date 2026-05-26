# Kindle Linux Chroot

> Turn your Amazon Kindle into a pocket Linux computer. Run Debian, Alpine, Ubuntu, or Arch Linux ARM — all without touching the stock system.

<p align="center">
  <img src="docs/screenshot.jpg" width="300" alt="Debian running on Kindle via kterm">
</p>

## What is this?

A set of scripts and a KUAL extension that let you run **any** ARM Linux distribution inside a `chroot` on a jailbroken Kindle. Your Kindle stays completely intact — everything lives inside a single `.ext3` image file on the USB storage partition.

**No dual-boot. No reflash. No risk. Just pure Linux on e-ink.**

### Features

- One-command rootfs builder (Debian / Alpine out of the box)
- KUAL integration — launch Linux from the Kindle menu
- Built-in SSH server for comfortable remote access
- Custom shell commands (`/landscape`, `/portrait`, `/rotate`, `/ssh`, `/help`)
- Works on any jailbroken Kindle with KUAL + kterm installed

### Supported Distros

| Distro | Status | Package Manager | Notes |
|--------|--------|----------------|-------|
| Debian Bookworm | Fully tested | `apt` | Recommended for beginners |
| Alpine 3.19 | Tested | `apk` | Ultra-lightweight (~8MB base) |
| Ubuntu 22.04 | Should work | `apt` | Use `--distro ubuntu` with debootstrap |
| Arch Linux ARM | Should work | `pacman` | Manual bootstrap required |
| Void Linux | Should work | `xbps` | Manual bootstrap required |

> Any distro that provides an `armhf` (ARMv7 hard-float) rootfs can be used.

---

## Prerequisites

- A **jailbroken** Kindle (tested on Kindle 10th gen / PW4, should work on PW3+)
- [KUAL](https://www.mobileread.com/forums/showthread.php?t=203326) installed
- [kterm](https://github.com/bfabiszewski/kterm) installed
- A Linux PC (or macOS with Docker) for building the image
- Wi-Fi connection on Kindle (for SSH and package downloads)

---

## Quick Start

### Step 1: Build the rootfs image

```bash
git clone https://github.com/YOUR_USERNAME/kindle-linux-chroot.git
cd kindle-linux-chroot/scripts
chmod +x build_rootfs.sh

# Debian (recommended)
sudo ./build_rootfs.sh --distro debian --size 1024

# Alpine (lightweight, ~50MB used)
sudo ./build_rootfs.sh --distro alpine --size 256
```

This produces a `debian.ext3` (or `alpine.ext3`) file ready for the Kindle.

**Host dependencies:**
```bash
# Arch Linux
sudo pacman -S debootstrap qemu-user-static qemu-user-static-binfmt debian-archive-keyring

# Ubuntu / Debian
sudo apt install debootstrap qemu-user-static binfmt-support

# macOS (use Docker)
# See docs/docker-build.md
```

### Step 2: Deploy to Kindle

Connect your Kindle via USB and copy files:

```bash
KINDLE=/media/$USER/Kindle   # adjust to your mount point

# Copy the rootfs image
cp debian.ext3 $KINDLE/

# Copy the KUAL extension
cp -r ../extensions/LinuxChroot $KINDLE/extensions/

# Copy the SSH helper script
cp start-ssh.sh $KINDLE/

sync
```

### Step 3: Launch on Kindle

1. Safely eject and disconnect Kindle from USB
2. Open **KUAL** on your Kindle
3. Tap **Linux Chroot** → **Start Terminal**
4. You're now in a Debian bash shell!

### Step 4: SSH from your PC (recommended)

The on-screen keyboard works, but SSH is way more comfortable:

```bash
# On Kindle (in kterm), run:
/ssh

# On your PC:
ssh root@192.168.1.XXX -p 2222
# Password: kindle
```

---

## Built-in Shell Commands

Once inside the chroot, these custom commands are available:

| Command | Description |
|---------|-------------|
| `/help` | Show all available commands |
| `/exit` | Cleanly exit the chroot |
| `/landscape` | Rotate screen to landscape mode |
| `/portrait` | Rotate screen back to portrait |
| `/rotate` | Toggle between portrait/landscape |
| `/ssh` | Start SSH server (installs dropbear if needed) |
| `/wifi` | Show current Wi-Fi IP address |
| `/info` | Display system info (RAM, disk, kernel) |

---

## Examples

### Install Python and run a script

```bash
apt-get update
apt-get install -y python3 python3-pip
python3 -c "print('Hello from Kindle!')"
```

### Run a web server

```bash
apt-get install -y python3
python3 -m http.server 8080 &
# Access from your PC: http://<kindle-ip>:8080
```

### Install Node.js

```bash
apt-get install -y nodejs npm
node -e "console.log('Node.js ' + process.version + ' on Kindle!')"
```

### Compile C code natively

```bash
apt-get install -y gcc
echo '#include <stdio.h>
int main() { printf("Compiled on Kindle!\\n"); return 0; }' > hello.c
gcc -o hello hello.c
./hello
```

### Install neofetch

```bash
apt-get install -y neofetch
neofetch
```

### Run a Git repo

```bash
apt-get install -y git
git clone https://github.com/someuser/somerepo.git
```

### Use as a network tool

```bash
apt-get install -y nmap curl wget dnsutils
nmap -sn 192.168.1.0/24
curl ifconfig.me
```

---

## How it works (technical)

```
┌─────────────────────────────────────┐
│         Kindle Hardware             │
│  (ARM Cortex-A7, 256MB RAM, e-ink)  │
├─────────────────────────────────────┤
│      Stock Kindle Linux Kernel      │
│           (4.1.15)                  │
├──────────────┬──────────────────────┤
│ Kindle OS    │   Linux Chroot       │
│ (Java GUI)   │   ┌────────────────┐ │
│              │   │ debian.ext3    │ │
│  ┌────────┐  │   │ mounted at     │ │
│  │ KUAL   │──┼──>│ /tmp/debian    │ │
│  │ kterm  │  │   │                │ │
│  └────────┘  │   │ bind mounts:   │ │
│              │   │  /dev /proc    │ │
│              │   │  /sys          │ │
│              │   └────────────────┘ │
└──────────────┴──────────────────────┘
```

The key insight: Kindle already runs Linux (kernel 4.1.15). We don't replace anything — we just mount an additional filesystem and `chroot` into it. The chroot shares the host kernel, so all hardware (Wi-Fi, touchscreen, framebuffer) is accessible.

---

## Directory Structure

```
kindle-linux-chroot/
├── README.md
├── scripts/
│   ├── build_rootfs.sh       # Universal rootfs builder
│   └── start-ssh.sh          # SSH server launcher for Kindle
├── extensions/
│   └── LinuxChroot/          # KUAL extension
│       ├── config.xml
│       ├── menu.json
│       └── bin/
│           ├── shell.sh      # Mount + launch kterm
│           └── stop.sh       # Unmount chroot
└── docs/
    ├── screenshot.jpg
    ├── troubleshooting.md
    └── advanced.md
```

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| "Cannot mount ext3" | Make sure the image file isn't corrupted. Re-run `build_rootfs.sh` |
| No internet in chroot | Check `/etc/resolv.conf` inside chroot. Run: `echo "nameserver 8.8.8.8" > /etc/resolv.conf` |
| `apt-get` hangs | Kindle Wi-Fi may have dropped. Reconnect and retry |
| kterm won't launch | Ensure kterm extension is installed correctly in `/mnt/us/extensions/kterm/` |
| SSH connection refused | Run `/ssh` inside the chroot first. Check Kindle is on Wi-Fi |
| Out of disk space | Build a larger image: `--size 2048` for 2GB |
| Screen rotation doesn't work | Your Kindle model may not support `/sys/class/graphics/fb0/rotate` |

---

## Limitations

- **Kernel version is fixed** — you use whatever kernel Kindle ships with (4.1.15 on most models). You cannot load custom kernel modules.
- **RAM is limited** — 256MB total, shared with Kindle OS. Don't run heavy workloads.
- **No systemd** — the kernel is too old and PID 1 is Kindle's init. Services must be started manually.
- **No GPU acceleration** — framebuffer only, no OpenGL.
- **Storage is slow** — internal eMMC is not fast. Large `apt` operations take time.

---

## Contributing

PRs welcome! Ideas for contribution:
- Add more distro support (Void, Gentoo, postmarketOS)
- Improve KUAL menu with status indicators
- Add a script to resize ext3 images
- Write a Docker-based builder for macOS users

---

## Credits

- [KUAL](https://www.mobileread.com/forums/showthread.php?t=203326) by knc1
- [kterm](https://github.com/bfabiszewski/kterm) by bfabiszewski
- Kindle jailbreak community at [MobileRead](https://www.mobileread.com/forums/forumdisplay.php?f=150)

## License

MIT

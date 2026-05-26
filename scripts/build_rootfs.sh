#!/bin/bash
# Universal Kindle Rootfs Bootstrap Script
# Supports: Debian, Alpine Linux (ARMhf architecture)

set -e

DISTRO="debian"
SIZE_MB=1024
OUTPUT_DIR="."
ROOTFS_URL=""
ROOTFS_FILE=""

usage() {
    echo "Usage: sudo $0 [options]"
    echo "Options:"
    echo "  --distro <name>           debian, alpine, arch, or custom (Default: debian)"
    echo "  --size <MB>               Image size in Megabytes (Default: 1024)"
    echo "  --out <path>              Output directory (Default: current directory)"
    echo "  --rootfs-url <url>        URL to armhf rootfs tarball (for --distro custom)"
    echo "  --rootfs-file <path>      Local path to armhf rootfs tarball (for --distro custom)"
    echo "  -h, --help                Show this help"
    echo ""
    echo "Examples:"
    echo "  sudo $0 --distro debian --size 1024"
    echo "  sudo $0 --distro arch --size 2048"
    echo "  sudo $0 --distro custom --rootfs-url https://example.com/rootfs-armhf.tar.gz --size 1024"
    echo "  sudo $0 --distro custom --rootfs-file /path/to/rootfs.tar.gz --size 512"
    exit 1
}

# Parse arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --distro) DISTRO="$2"; shift ;;
        --size) SIZE_MB="$2"; shift ;;
        --out) OUTPUT_DIR="$2"; shift ;;
        --rootfs-url) ROOTFS_URL="$2"; shift ;;
        --rootfs-file) ROOTFS_FILE="$2"; shift ;;
        -h|--help) usage ;;
        *) echo "Unknown parameter: $1"; usage ;;
    esac
    shift
done

if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run with sudo/root privileges."
    exit 1
fi

# Check dependencies
echo "[*] Checking host dependencies..."
for cmd in dd mkfs.ext3 qemu-arm-static; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Error: Required host dependency '$cmd' is missing. Please install it."
        exit 1
    fi
done

IMG_NAME="${DISTRO}.ext3"
IMG_PATH="${OUTPUT_DIR}/${IMG_NAME}"
MNT_DIR="/tmp/kindle-chroot-build"

echo "=============================================="
echo " Building Kindle Linux Chroot Image"
echo " Distribution: $DISTRO"
echo " Size:         $SIZE_MB MB"
echo " Destination:  $IMG_PATH"
echo "=============================================="

# 1. Create blank ext3 image
echo "[*] Allocating sparse image..."
dd if=/dev/zero of="$IMG_PATH" bs=1M count="$SIZE_MB"
echo "[*] Formatting as ext3..."
mkfs.ext3 -F "$IMG_PATH"

# 2. Mount image
echo "[*] Mounting image to temporary path..."
mkdir -p "$MNT_DIR"
mount -o loop "$IMG_PATH" "$MNT_DIR"

# Clean up mounts on failure
cleanup() {
    echo "[*] Cleaning up mounts..."
    umount "$MNT_DIR" 2>/dev/null || true
    rmdir "$MNT_DIR" 2>/dev/null || true
}
trap cleanup EXIT

# 3. Bootstrap target filesystem
if [ "$DISTRO" = "debian" ]; then
    if ! command -v debootstrap >/dev/null 2>&1; then
        echo "Error: 'debootstrap' is required for Debian. Install it first."
        exit 1
    fi
    echo "[*] Bootstrapping Debian Bookworm Stage 1 (armhf)..."
    debootstrap --arch=armhf --foreign bookworm "$MNT_DIR" http://deb.debian.org/debian
    
    echo "[*] Copying qemu-arm-static..."
    cp "$(which qemu-arm-static)" "$MNT_DIR/usr/bin/"
    
    echo "[*] Running Debian Stage 2 (Second Stage)..."
    chroot "$MNT_DIR" /debootstrap/debootstrap --second-stage
    
    # Configure networking and APT
    echo "nameserver 8.8.8.8" > "$MNT_DIR/etc/resolv.conf"
    echo "kindle" > "$MNT_DIR/etc/hostname"
    cat > "$MNT_DIR/etc/apt/sources.list" << EOF
deb http://deb.debian.org/debian bookworm main
deb http://deb.debian.org/debian bookworm-updates main
deb http://security.debian.org/debian-security bookworm-security main
EOF
    
    # Set default root password
    echo "[*] Setting root password to 'kindle'..."
    chroot "$MNT_DIR" /usr/sbin/chpasswd <<< "root:kindle"

    # Add custom kindle commands profile
    echo "[*] Installing custom chroot bash profile..."
    cat > "$MNT_DIR/etc/profile.d/kindle.sh" << 'EOF'
export LANG=C.UTF-8
export LC_ALL=C.UTF-8
export PS1='\[\033[1m\]root@kindle:\w# \[\033[0m\]'

alias /exit='echo "Bye!"; exit'
alias quit='exit'

/landscape() {
    echo 1 > /sys/class/graphics/fb0/rotate 2>/dev/null || xrandr -o right 2>/dev/null || echo "Rotation failed"
}

/portrait() {
    echo 0 > /sys/class/graphics/fb0/rotate 2>/dev/null || xrandr -o normal 2>/dev/null || echo "Rotation failed"
}

/rotate() {
    CUR=$(cat /sys/class/graphics/fb0/rotate 2>/dev/null)
    if [ "$CUR" = "0" ] || [ "$CUR" = "2" ]; then /landscape; else /portrait; fi
}

/help() {
    echo "=== Kindle Debian Commands ==="
    echo "  /exit       - exit chroot"
    echo "  /landscape  - rotate to landscape"
    echo "  /portrait   - rotate to portrait"  
    echo "  /rotate     - toggle rotation"
    echo "  /info       - system info"
    echo "  /wifi       - show WiFi IP"
    echo "  /ssh        - start SSH server"
    echo "  /help       - this help"
    echo "==============================="
}

/info() {
    echo "=== Kindle Debian ==="
    echo "Kernel: $(uname -r)"
    echo "Memory: $(free -m | awk '/Mem:/ {printf "%dMB / %dMB", $3, $2}')"
    echo "Disk:   $(df -h / | awk 'NR==2 {printf "%s / %s (%s)", $3, $2, $5}')"
    echo "====================="
}

/wifi() {
    IP=$(ip addr show wlan0 2>/dev/null | awk '/inet / {print $2}' | cut -d/ -f1)
    [ -n "$IP" ] && echo "WiFi IP: $IP" || echo "No WiFi connection"
}

/ssh() {
    if command -v dropbear >/dev/null 2>&1; then
        killall dropbear 2>/dev/null
        dropbear -R -p 0.0.0.0:2222 -B 2>/dev/null
        echo "SSH running on port 2222"
        /wifi
    else
        echo "Installing dropbear..."
        apt-get update -qq && apt-get install -y -qq dropbear
        /ssh
    fi
}

echo "Kindle Debian - type /help for commands"
EOF

elif [ "$DISTRO" = "alpine" ]; then
    echo "[*] Bootstrapping Alpine Linux (armhf)..."
    # Download static apk tool for bootstrap
    APK_STATIC="/tmp/apk-tools-static"
    if [ ! -f "$APK_STATIC" ]; then
        echo "[*] Downloading apk.static..."
        curl -sSL -o "$APK_STATIC" https://gitlab.alpinelinux.org/alpine/apk-tools/-/raw/master/src/apk.static?inline=false || \
        wget -q -O "$APK_STATIC" https://gitlab.alpinelinux.org/alpine/apk-tools/-/raw/master/src/apk.static?inline=false
        chmod +x "$APK_STATIC"
    fi
    
    # Bootstrap Alpine core
    "$APK_STATIC" --repository http://dl-cdn.alpinelinux.org/alpine/v3.19/main \
                  --update-cache \
                  --allow-untrusted \
                  --arch armhf \
                  --root "$MNT_DIR" \
                  init \
                  alpine-base alpine-keys apk-tools-static
                  
    # Set up networking & DNS inside Alpine
    echo "nameserver 8.8.8.8" > "$MNT_DIR/etc/resolv.conf"
    echo "http://dl-cdn.alpinelinux.org/alpine/v3.19/main" > "$MNT_DIR/etc/apk/repositories"
    echo "http://dl-cdn.alpinelinux.org/alpine/v3.19/community" >> "$MNT_DIR/etc/apk/repositories"
    
    # Configure root password (blank by default in Alpine, let's set 'kindle')
    echo "root:kindle" | chroot "$MNT_DIR" chpasswd
    
    # Add custom kindle commands profile
    echo "[*] Installing custom chroot ash profile..."
    cat > "$MNT_DIR/etc/profile" << 'EOF'
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export PS1='\[\033[1;32m\]root@alpine:\w# \[\033[0m\]'

alias /exit='echo "Bye!"; exit'
alias quit='exit'

/landscape() {
    echo 1 > /sys/class/graphics/fb0/rotate 2>/dev/null
}
/portrait() {
    echo 0 > /sys/class/graphics/fb0/rotate 2>/dev/null
}
/rotate() {
    CUR=$(cat /sys/class/graphics/fb0/rotate 2>/dev/null)
    if [ "$CUR" = "0" ] || [ "$CUR" = "2" ]; then /landscape; else /portrait; fi
}
/help() {
    echo "=== Kindle Alpine Commands ==="
    echo "  /exit, quit - exit chroot"
    echo "  /landscape  - rotate landscape"
    echo "  /portrait   - rotate portrait"
    echo "  /rotate     - toggle rotation"
    echo "  /help       - this help"
    echo "=============================="
}
echo "Kindle Alpine - type /help for commands"
EOF

elif [ "$DISTRO" = "arch" ]; then
    echo "[*] Bootstrapping Arch Linux ARM (armv7)..."
    TARBALL="/tmp/ArchLinuxARM-armv7-latest.tar.gz"
    
    if [ ! -f "$TARBALL" ]; then
        echo "[*] Downloading Arch Linux ARM rootfs..."
        wget -O "$TARBALL" http://os.archlinuxarm.org/os/ArchLinuxARM-armv7-latest.tar.gz || \
        curl -L -o "$TARBALL" http://os.archlinuxarm.org/os/ArchLinuxARM-armv7-latest.tar.gz
    fi
    
    echo "[*] Extracting rootfs (this may take a few minutes)..."
    set +e
    if command -v bsdtar >/dev/null 2>&1; then
        bsdtar -xpf "$TARBALL" -C "$MNT_DIR"
    else
        tar -xpf "$TARBALL" -C "$MNT_DIR" --numeric-owner --warning=no-unknown-keyword
    fi
    set -e
    
    rm -f "$MNT_DIR/etc/resolv.conf"
    echo "nameserver 8.8.8.8" > "$MNT_DIR/etc/resolv.conf"
    echo "kindle" > "$MNT_DIR/etc/hostname"

    echo "[*] Setting root password to 'kindle'..."
    cp "$(which qemu-arm-static)" "$MNT_DIR/usr/bin/"
    chroot "$MNT_DIR" bash -c 'echo "root:kindle" | chpasswd'

    echo "[*] Installing custom chroot bash profile..."
    cat > "$MNT_DIR/etc/profile.d/kindle.sh" << 'EOF'
export LANG=C.UTF-8
export LC_ALL=C.UTF-8
export PS1='\[\033[1;34m\]root@kindle:\w# \[\033[0m\]'

alias /exit='echo "Bye!"; exit'
alias quit='exit'

/landscape() {
    echo 1 > /sys/class/graphics/fb0/rotate 2>/dev/null || echo "Rotation failed"
}
/portrait() {
    echo 0 > /sys/class/graphics/fb0/rotate 2>/dev/null || echo "Rotation failed"
}
/rotate() {
    CUR=$(cat /sys/class/graphics/fb0/rotate 2>/dev/null)
    if [ "$CUR" = "0" ] || [ "$CUR" = "2" ]; then /landscape; else /portrait; fi
}
/help() {
    echo "=== Kindle Arch Commands ==="
    echo "  exit        - exit chroot"
    echo "  /landscape  - rotate landscape"
    echo "  /portrait   - rotate portrait"
    echo "  /rotate     - toggle rotation"
    echo "  /info       - system info"
    echo "  /wifi       - show WiFi IP"
    echo "  /ssh        - start SSH server"
    echo "  /help       - this help"
    echo "============================="
}
/info() {
    echo "=== Kindle Arch ==="
    echo "Kernel: $(uname -r)"
    echo "Memory: $(free -m | awk '/Mem:/ {printf "%dMB / %dMB", $3, $2}')"
    echo "Disk:   $(df -h / | awk 'NR==2 {printf "%s / %s (%s)", $3, $2, $5}')"
    echo "==================="
}
/wifi() {
    IP=$(ip addr show wlan0 2>/dev/null | awk '/inet / {print $2}' | cut -d/ -f1)
    [ -n "$IP" ] && echo "WiFi IP: $IP" || echo "No WiFi connection"
}
/ssh() {
    if command -v dropbear >/dev/null 2>&1; then
        killall dropbear 2>/dev/null
        dropbear -R -p 0.0.0.0:2222 -B 2>/dev/null
        echo "SSH running on port 2222"
        /wifi
    else
        echo "Installing dropbear..."
        pacman -Sy --noconfirm dropbear
        /ssh
    fi
}
echo "Kindle Arch - type /help for commands"
EOF

elif [ "$DISTRO" = "custom" ]; then
    echo "[*] Building custom rootfs image..."
    
    if [ -n "$ROOTFS_FILE" ]; then
        TARBALL="$ROOTFS_FILE"
        if [ ! -f "$TARBALL" ]; then
            echo "Error: File not found: $TARBALL"
            exit 1
        fi
    elif [ -n "$ROOTFS_URL" ]; then
        TARBALL="/tmp/custom-rootfs.tar.gz"
        if [ ! -f "$TARBALL" ]; then
            echo "[*] Downloading rootfs from $ROOTFS_URL..."
            wget -O "$TARBALL" "$ROOTFS_URL" || curl -L -o "$TARBALL" "$ROOTFS_URL"
        fi
    else
        echo "Error: --distro custom requires --rootfs-url or --rootfs-file"
        echo "  Example: sudo $0 --distro custom --rootfs-url https://example.com/rootfs-armhf.tar.xz --size 1024"
        exit 1
    fi
    
    echo "[*] Extracting rootfs..."
    set +e
    case "$TARBALL" in
        *.tar.xz) tar -xJpf "$TARBALL" -C "$MNT_DIR" --numeric-owner 2>/dev/null ;;
        *.tar.gz|*.tgz) 
            if command -v bsdtar >/dev/null 2>&1; then
                bsdtar -xpf "$TARBALL" -C "$MNT_DIR"
            else
                tar -xzpf "$TARBALL" -C "$MNT_DIR" --numeric-owner 2>/dev/null
            fi ;;
        *.tar.bz2) tar -xjpf "$TARBALL" -C "$MNT_DIR" --numeric-owner 2>/dev/null ;;
        *) tar -xpf "$TARBALL" -C "$MNT_DIR" --numeric-owner 2>/dev/null ;;
    esac
    set -e
    
    rm -f "$MNT_DIR/etc/resolv.conf" 2>/dev/null
    echo "nameserver 8.8.8.8" > "$MNT_DIR/etc/resolv.conf"
    echo "kindle" > "$MNT_DIR/etc/hostname"
    
    if [ -f "$MNT_DIR/bin/bash" ] || [ -f "$MNT_DIR/usr/bin/bash" ]; then
        cp "$(which qemu-arm-static)" "$MNT_DIR/usr/bin/" 2>/dev/null
        chroot "$MNT_DIR" bash -c 'echo "root:kindle" | chpasswd' 2>/dev/null || true
    fi

    echo "[*] Installing custom chroot profile..."
    mkdir -p "$MNT_DIR/etc/profile.d"
    cat > "$MNT_DIR/etc/profile.d/kindle.sh" << 'EOF'
export LANG=C.UTF-8
export PS1='\[\033[1;35m\]root@kindle:\w# \[\033[0m\]'
alias quit='exit'
echo "Kindle Custom Linux - enjoy!"
EOF

else
    echo "Error: Unsupported distribution '$DISTRO'."
    echo "Supported: debian, alpine, arch, custom"
    echo "For any other distro, use: --distro custom --rootfs-url <URL>"
    exit 1
fi

echo "[*] Success! Image has been created."
echo "    File: $IMG_PATH"
echo "    Size: $(du -h "$IMG_PATH" | cut -f1)"
echo "=============================================="

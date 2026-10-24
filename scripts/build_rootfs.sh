#!/bin/bash
set -e

DISTRO=""
SIZE_MB=""
OUTPUT_DIR="."
ROOTFS_URL=""
ROOTFS_FILE=""
DEBIAN_RELEASE="trixie"
ALPINE_RELEASE="v3.22"

usage() {
    echo "Usage: sudo $0 [options]"
    echo "Options:"
    echo "  --distro <name>           debian, alpine, arch, void, or custom (Default: debian)"
    echo "  --size <MB>               Image size in Megabytes (Default: 1024)"
    echo "  --out <path>              Output directory (Default: current directory)"
    echo "  --rootfs-url <url>        URL to armhf rootfs tarball (for --distro custom)"
    echo "  --rootfs-file <path>      Local path to armhf rootfs tarball (for --distro custom)"
    echo "  --debian-release <name>   Debian release to bootstrap (Default: trixie)"
    echo "  --alpine-release <ver>    Alpine version, e.g. v3.22 (Default: v3.22)"
    echo "  -h, --help                Show this help"
    echo ""
    echo "Run without arguments for interactive mode."
    exit 1
}

interactive_menu() {
    echo ""
    echo "  ╔══════════════════════════════════════╗"
    echo "  ║   Kindle Linux Chroot Builder        ║"
    echo "  ╚══════════════════════════════════════╝"
    echo ""
    echo "  Select distro:"
    echo ""
    echo "    1) Debian       (recommended, ~500MB)"
    echo "    2) Alpine       (lightweight, ~50MB)"
    echo "    3) Arch Linux   (rolling release, ~1.5GB)"
    echo "    4) Void Linux   (fast, runit, ~250MB)"
    echo "    5) Custom       (provide your own rootfs)"

    printf "  Choice [1]: "
    read -r DISTRO_CHOICE < /dev/tty
    [ -z "$DISTRO_CHOICE" ] && DISTRO_CHOICE=1

    case $DISTRO_CHOICE in
        1) DISTRO="debian" ;;
        2) DISTRO="alpine" ;;
        3) DISTRO="arch" ;;
        4) DISTRO="void" ;;
        5) DISTRO="custom" ;;
        *) echo "  Invalid choice"; exit 1 ;;
    esac

    echo ""
    if [ "$DISTRO" = "arch" ]; then
        DEFAULT_SIZE=2048
    elif [ "$DISTRO" = "alpine" ]; then
        DEFAULT_SIZE=256
    else
        DEFAULT_SIZE=1024
    fi
    printf '  Image size in MB [%s]: ' "$DEFAULT_SIZE"
    read -r SIZE_INPUT < /dev/tty
    SIZE_MB="${SIZE_INPUT:-$DEFAULT_SIZE}"

    echo ""
    printf "  Output directory [.]: "
    read -r OUT_INPUT < /dev/tty
    OUTPUT_DIR="${OUT_INPUT:-.}"

    if [ "$DISTRO" = "custom" ]; then
        echo ""
        echo "  How to provide rootfs?"
        echo "    1) Download from URL"
        echo "    2) Local file"
        printf "  Choice [1]: "
        read -r CUSTOM_CHOICE < /dev/tty
        [ -z "$CUSTOM_CHOICE" ] && CUSTOM_CHOICE=1
        if [ "$CUSTOM_CHOICE" = "2" ]; then
            printf "  Path to tarball: "
            read -r ROOTFS_FILE < /dev/tty
        else
            echo ""
            echo "  Where to get a direct link (armv7 rootfs):"
            echo "    Void:    https://repo-default.voidlinux.org/live/current/"
            echo "             look for void-armv7l-ROOTFS-*.tar.xz"
            echo "    Ubuntu:  https://cdimage.ubuntu.com/ubuntu-base/releases/"
            echo "             look for *-base-armhf.tar.gz"
            echo "    pmOS:    https://images.postmarketos.org/bpo/"
            echo "    Adelie:  https://distfiles.adelielinux.org/adelie/1.0/"
            echo "    AOSC:    https://releases.aosc.io/"
            echo ""
            printf "  URL to tarball: "
            read -r ROOTFS_URL < /dev/tty
        fi
    fi

    echo ""
    echo "  ─────────────────────────────────────"
    echo "  Distro:  $DISTRO"
    echo "  Size:    ${SIZE_MB}MB"
    echo "  Output:  $OUTPUT_DIR"
    echo "  ─────────────────────────────────────"
    echo ""
    printf "  Proceed? [Y/n]: "
    read -r CONFIRM < /dev/tty
    case "$CONFIRM" in
        n|N|no|No) echo "  Aborted."; exit 0 ;;
    esac
    echo ""
}

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --distro) DISTRO="$2"; shift ;;
        --size) SIZE_MB="$2"; shift ;;
        --out) OUTPUT_DIR="$2"; shift ;;
        --rootfs-url) ROOTFS_URL="$2"; shift ;;
        --rootfs-file) ROOTFS_FILE="$2"; shift ;;
        --debian-release) DEBIAN_RELEASE="$2"; shift ;;
        --alpine-release) ALPINE_RELEASE="$2"; shift ;;
        -h|--help) usage ;;
        *) echo "Unknown parameter: $1"; usage ;;
    esac
    shift
done

if [ -z "$DISTRO" ]; then
    interactive_menu
fi

[ -z "$SIZE_MB" ] && SIZE_MB=1024

if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run with sudo/root privileges."
    exit 1
fi

echo "[*] Checking host dependencies..."
for cmd in truncate mkfs.ext3 qemu-arm-static; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Error: Required host dependency '$cmd' is missing. Please install it."
        exit 1
    fi
done

IMG_NAME="${DISTRO}.ext3"
IMG_PATH="${OUTPUT_DIR}/${IMG_NAME}"
MNT_DIR="/tmp/kindle-chroot-build"

fetch() {
    local url="$1" out="$2"
    rm -f "$out"
    echo "[*] Downloading: $url"
    if command -v curl >/dev/null 2>&1; then
        curl -fSL -o "$out" "$url"
    else
        wget -O "$out" "$url"
    fi
}

# Install the shared Kindle chroot profile into a rootfs.
# $1 = ANSI color code for PS1 (e.g. "1", "1;32")
# $2 = hostname shown in the prompt
# $3 = command used to install dropbear on this distro
# $4 = distro display name (used in /info output)
install_kindle_profile() {
    local color="$1" host="$2" pkg_install="$3" distro_name="$4"
    mkdir -p "$MNT_DIR/etc/profile.d"
    local ps1="\\[\\033[${color}m\\]root@${host}:\\w# \\[\\033[0m\\]"
    {
        printf 'export LANG=C.UTF-8\nexport LC_ALL=C.UTF-8\n'
        printf "export PS1='%s'\n" "$ps1"
        echo ''
        cat << 'EOF'
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
    echo "=== Kindle Commands ==="
    echo "  /exit, quit - exit chroot"
    echo "  /landscape  - rotate to landscape"
    echo "  /portrait   - rotate to portrait"
    echo "  /rotate     - toggle rotation"
    echo "  /info       - system info"
    echo "  /wifi       - show WiFi IP"
    echo "  /ssh        - start SSH server"
    echo "  /help       - this help"
    echo "======================="
}

/info() {
    echo "=== Kindle __DISTRO_NAME__ ==="
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
        __PKG_INSTALL__
        /ssh
    fi
}

echo "Connected. Type /help for available commands."
EOF
    } > "$MNT_DIR/etc/profile.d/kindle.sh"
    local esc_pkg esc_name
    esc_pkg=$(printf '%s' "$pkg_install" | sed 's/[\\&|]/\\&/g')
    esc_name=$(printf '%s' "$distro_name" | sed 's/[\\&|]/\\&/g')
    sed -i "s|__PKG_INSTALL__|$esc_pkg|" "$MNT_DIR/etc/profile.d/kindle.sh"
    sed -i "s|__DISTRO_NAME__|$esc_name|" "$MNT_DIR/etc/profile.d/kindle.sh"
}

echo "=============================================="
echo " Building Kindle Linux Chroot Image"
echo " Distribution: $DISTRO"
echo " Size:         $SIZE_MB MB"
echo " Destination:  $IMG_PATH"
echo "=============================================="
echo ""

cat << 'BANNER'

▗▖ ▄▖  █          ▗▖▗▄▖              ▄▄ ▗▖
▐▌▐▛   ▀          ▐▌▝▜▌             █▀▀▌▐▌                   ▐▌
▐▙█   ██  ▐▙██▖ ▟█▟▌ ▐▌   ▟█▙      ▐▛   ▐▙██▖ █▟█▌ ▟█▙  ▟█▙ ▐███
▐██    █  ▐▛ ▐▌▐▛ ▜▌ ▐▌  ▐▙▄▟▌     ▐▌   ▐▛ ▐▌ █▘  ▐▛ ▜▌▐▛ ▜▌ ▐▌
▐▌▐▙   █  ▐▌ ▐▌▐▌ ▐▌ ▐▌  ▐▛▀▀▘     ▐▙   ▐▌ ▐▌ █   ▐▌ ▐▌▐▌ ▐▌ ▐▌
▐▌ █▖▗▄█▄▖▐▌ ▐▌▝█▄█▌ ▐▙▄ ▝█▄▄▌      █▄▄▌▐▌ ▐▌ █   ▝█▄█▘▝█▄█▘ ▐▙▄
▝▘ ▝▘▝▀▀▀▘▝▘ ▝▘ ▝▀▝▘  ▀▀  ▝▀▀        ▀▀ ▝▘ ▝▘ ▀    ▝▀▘  ▝▀▘   ▀▀

BANNER
echo ""

echo "[*] Allocating sparse image..."
truncate -s "${SIZE_MB}M" "$IMG_PATH"
echo "[*] Formatting as ext3..."
mkfs.ext3 -F "$IMG_PATH"

echo "[*] Mounting image to temporary path..."
mkdir -p "$MNT_DIR"
mount -o loop "$IMG_PATH" "$MNT_DIR"

cleanup() {
    echo "[*] Cleaning up mounts..."
    umount "$MNT_DIR" 2>/dev/null || true
    rmdir "$MNT_DIR" 2>/dev/null || true
}
trap cleanup EXIT

if [ "$DISTRO" = "debian" ]; then
    if ! command -v debootstrap >/dev/null 2>&1; then
        echo "Error: 'debootstrap' is required for Debian. Install it first."
        exit 1
    fi
    echo "[*] Bootstrapping Debian $DEBIAN_RELEASE Stage 1 (armhf)..."
    debootstrap --arch=armhf --foreign "$DEBIAN_RELEASE" "$MNT_DIR" http://deb.debian.org/debian
    
    echo "[*] Copying qemu-arm-static..."
    cp "$(which qemu-arm-static)" "$MNT_DIR/usr/bin/"
    
    echo "[*] Running Debian Stage 2 (Second Stage)..."
    chroot "$MNT_DIR" /debootstrap/debootstrap --second-stage
    
    echo "nameserver 8.8.8.8" > "$MNT_DIR/etc/resolv.conf"
    echo "kindle" > "$MNT_DIR/etc/hostname"
    cat > "$MNT_DIR/etc/apt/sources.list" << EOF
deb http://deb.debian.org/debian $DEBIAN_RELEASE main
deb http://deb.debian.org/debian $DEBIAN_RELEASE-updates main
deb http://security.debian.org/debian-security $DEBIAN_RELEASE-security main
EOF
    
    echo "[*] Setting root password to 'kindle'..."
    chroot "$MNT_DIR" /usr/sbin/chpasswd <<< "root:kindle"

    echo "[*] Installing chroot profile..."
    install_kindle_profile "1" "kindle" "apt-get update -qq && apt-get install -y -qq dropbear" "Debian"

elif [ "$DISTRO" = "alpine" ]; then
    echo "[*] Bootstrapping Alpine Linux $ALPINE_RELEASE (armhf)..."
    APK_DIR="/tmp/apk-tools-static"
    rm -rf "$APK_DIR"
    mkdir -p "$APK_DIR"
    BASE_URL="http://dl-cdn.alpinelinux.org/alpine/${ALPINE_RELEASE}/main/armhf"
    echo "[*] Downloading apk-tools-static from $BASE_URL..."
    APK_PKG=$(curl -sSL "$BASE_URL/" | grep -o 'apk-tools-static-[0-9][^"]*\.apk' | sort -u | tail -n1)
    if [ -z "$APK_PKG" ]; then
        echo "Error: could not find apk-tools-static package for alpine $ALPINE_RELEASE armhf."
        echo "       Check the release version with: curl $BASE_URL/"
        exit 1
    fi
    echo "[*] Found: $APK_PKG"
    curl -sSL -o "$APK_DIR/apk-tools-static.apk" "$BASE_URL/$APK_PKG"
    tar -xzf "$APK_DIR/apk-tools-static.apk" -C "$APK_DIR"
    APK_STATIC="$APK_DIR/sbin/apk.static"
    chmod +x "$APK_STATIC"
    
    "$APK_STATIC" --repository "http://dl-cdn.alpinelinux.org/alpine/${ALPINE_RELEASE}/main" \
                  --update-cache \
                  --allow-untrusted \
                  --arch armhf \
                  --root "$MNT_DIR" \
                  init \
                  alpine-base alpine-keys apk-tools-static
                  
    echo "nameserver 8.8.8.8" > "$MNT_DIR/etc/resolv.conf"
    echo "http://dl-cdn.alpinelinux.org/alpine/${ALPINE_RELEASE}/main" > "$MNT_DIR/etc/apk/repositories"
    echo "http://dl-cdn.alpinelinux.org/alpine/${ALPINE_RELEASE}/community" >> "$MNT_DIR/etc/apk/repositories"
    
    echo "root:kindle" | chroot "$MNT_DIR" chpasswd
    
    echo "[*] Installing chroot ash profile..."
    install_kindle_profile "1;32" "alpine" "apk update -q && apk add dropbear" "Alpine"

elif [ "$DISTRO" = "arch" ]; then
    echo "[*] Bootstrapping Arch Linux ARM (armv7)..."
    TARBALL="/tmp/ArchLinuxARM-armv7-latest.tar.gz"
    
    if [ ! -f "$TARBALL" ]; then
        fetch http://os.archlinuxarm.org/os/ArchLinuxARM-armv7-latest.tar.gz "$TARBALL"
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

    echo "[*] Installing chroot profile..."
    install_kindle_profile "1;34" "kindle" "pacman -Sy --noconfirm dropbear" "Arch"

elif [ "$DISTRO" = "void" ]; then
    echo "[*] Bootstrapping Void Linux (armv7l)..."
    VOID_DIR="http://repo-default.voidlinux.org/live/current/"
    VOID_PKG=$(curl -sSL "$VOID_DIR" | grep -o 'void-armv7l-ROOTFS-[0-9]*\.tar\.xz' | sort -u | tail -n1)
    if [ -z "$VOID_PKG" ]; then
        echo "Error: could not find void-armv7l-ROOTFS tarball."
        echo "       Check the listing: $VOID_DIR"
        exit 1
    fi
    TARBALL="/tmp/${VOID_PKG}"
    if [ ! -f "$TARBALL" ]; then
        fetch "$VOID_DIR/$VOID_PKG" "$TARBALL"
    fi
    echo "[*] Found: $VOID_PKG"

    echo "[*] Extracting rootfs (this may take a few minutes)..."
    set +e
    tar -xpf "$TARBALL" -C "$MNT_DIR" --numeric-owner 2>/dev/null
    set -e
    if [ ! -d "$MNT_DIR/etc" ]; then
        echo "Error: extraction failed, rootfs looks empty."
        exit 1
    fi

    rm -f "$MNT_DIR/etc/resolv.conf" 2>/dev/null
    echo "nameserver 8.8.8.8" > "$MNT_DIR/etc/resolv.conf"
    echo "kindle" > "$MNT_DIR/etc/hostname"

    echo "[*] Setting root password to 'kindle'..."
    cp "$(which qemu-arm-static)" "$MNT_DIR/usr/bin/" 2>/dev/null
    chroot "$MNT_DIR" bash -c 'echo "root:kindle" | chpasswd' 2>/dev/null || \
    chroot "$MNT_DIR" chpasswd <<< "root:kindle"

    echo "[*] Installing chroot profile..."
    install_kindle_profile "1;33" "void" "xbps-install -S dropbear" "Void"

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
            fetch "$ROOTFS_URL" "$TARBALL"
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

    echo "[*] Installing chroot profile..."
    install_kindle_profile "1;35" "kindle" "echo \"Run your package manager to install dropbear\"" "Custom"

else
    echo "Error: Unsupported distribution '$DISTRO'."
    echo "Supported: debian, alpine, arch, void, custom"
    echo "For any other distro, use: --distro custom --rootfs-url <URL>"
    exit 1
fi

echo "[*] Success! Image has been created."
echo "    File: $IMG_PATH"
echo "    Size: $(du -h "$IMG_PATH" | cut -f1)"
echo "=============================================="

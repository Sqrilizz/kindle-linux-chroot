#!/bin/sh
# Start SSH server inside Linux chroot on Kindle
# Usage: sh /mnt/us/start-ssh.sh [debian|alpine]
# Run from kterm or via KUAL

DISTRO="${1:-debian}"
IMG="/mnt/us/${DISTRO}.ext3"
MNT="/tmp/${DISTRO}"

echo "[*] Mounting ${DISTRO}..."
if ! mount | grep -q "$MNT"; then
    mkdir -p "$MNT"
    mount -o loop,noatime -t ext3 "$IMG" "$MNT" || {
        echo "[FAIL] Cannot mount ${IMG}"
        exit 1
    }
    mount -o bind /dev      "$MNT/dev"
    mount -o bind /dev/pts  "$MNT/dev/pts"
    mount -o bind /proc     "$MNT/proc"
    mount -o bind /sys      "$MNT/sys"
    cp /etc/resolv.conf "$MNT/etc/resolv.conf" 2>/dev/null
fi
echo "[OK] ${DISTRO} mounted at ${MNT}"

echo "[*] Starting SSH server..."
if [ "$DISTRO" = "alpine" ]; then
    chroot "$MNT" /bin/sh -c '
        apk update 2>/dev/null
        apk add dropbear 2>/dev/null
        mkdir -p /etc/dropbear
        [ ! -f /etc/dropbear/dropbear_rsa_host_key ] && dropbearkey -t rsa -f /etc/dropbear/dropbear_rsa_host_key
        killall dropbear 2>/dev/null
        dropbear -R -p 0.0.0.0:2222 -B
        echo "[OK] Dropbear SSH running on port 2222"
    '
else
    chroot "$MNT" /bin/bash -c '
        if ! command -v dropbear >/dev/null 2>&1; then
            apt-get update -qq
            apt-get install -y -qq dropbear
        fi
        killall dropbear 2>/dev/null
        dropbear -R -p 0.0.0.0:2222 -B 2>/dev/null || /usr/sbin/dropbear -R -p 0.0.0.0:2222 -B
        echo "[OK] Dropbear SSH running on port 2222"
    '
fi

echo ""
echo "=== Connection Info ==="
WIFI_IP="$(ip addr show wlan0 2>/dev/null | awk '/inet / {print $2}' | cut -d/ -f1)"
[ -n "$WIFI_IP" ] && echo "  ssh root@${WIFI_IP} -p 2222"
[ -z "$WIFI_IP" ] && echo "  [!] No Wi-Fi IP found. Connect to Wi-Fi first."
echo "  Password: kindle"
echo "========================"

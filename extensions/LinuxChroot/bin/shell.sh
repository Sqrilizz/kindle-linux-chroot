#!/bin/sh
# Mount Linux chroot and open kterm inside it
# Automatically detects which distro image is available

KTERM=/mnt/us/extensions/kterm

# Auto-detect distro: prefer debian, fallback to alpine
if [ -f /mnt/us/debian.ext3 ]; then
    IMG=/mnt/us/debian.ext3
    MNT=/tmp/debian
    SHELL_CMD="/bin/bash -l"
elif [ -f /mnt/us/alpine.ext3 ]; then
    IMG=/mnt/us/alpine.ext3
    MNT=/tmp/alpine
    SHELL_CMD="/bin/sh -l"
else
    echo "No rootfs image found! Place debian.ext3 or alpine.ext3 in /mnt/us/"
    exit 1
fi

# Mount if not already mounted
if ! mount | grep -q "$MNT"; then
    mkdir -p "$MNT"
    mount -o loop,noatime -t ext3 "$IMG" "$MNT" || {
        echo "Failed to mount $IMG"
        exit 1
    }
    mount -o bind /dev "$MNT/dev"
    mount -o bind /dev/pts "$MNT/dev/pts"
    mount -o bind /proc "$MNT/proc"
    mount -o bind /sys "$MNT/sys"
    mkdir -p "$MNT/run/dbus"
    mount -o bind /var/run/dbus/ "$MNT/run/dbus/" 2>/dev/null
    cp /etc/resolv.conf "$MNT/etc/resolv.conf" 2>/dev/null
fi

# Get DPI for keyboard layout
DPI=$(cat /var/log/Xorg.0.log 2>/dev/null | grep DPI | sed -n 's/.*(\([0-9]\+\), [0-9]\+).*/\1/p')
PARAM=""
if [ -n "$DPI" ] && [ "$DPI" -gt 290 ] 2>/dev/null; then
    PARAM="-l ${KTERM}/layouts/keyboard-300dpi.xml"
elif [ -n "$DPI" ] && [ "$DPI" -gt 200 ] 2>/dev/null; then
    PARAM="-l ${KTERM}/layouts/keyboard-200dpi.xml"
fi

export TERM=xterm
export TERMINFO=${KTERM}/vte/terminfo

${KTERM}/bin/kterm ${PARAM} -e "chroot $MNT $SHELL_CMD" &

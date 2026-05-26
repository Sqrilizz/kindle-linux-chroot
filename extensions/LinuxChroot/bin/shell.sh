#!/bin/sh

KTERM=/mnt/us/extensions/kterm

IMG=""
for candidate in debian arch alpine ubuntu void custom; do
    if [ -f "/mnt/us/${candidate}.ext3" ]; then
        IMG="/mnt/us/${candidate}.ext3"
        MNT="/tmp/${candidate}"
        break
    fi
done

if [ -z "$IMG" ]; then
    IMG=$(find /mnt/us -maxdepth 1 -name "*.ext3" | head -1)
    if [ -n "$IMG" ]; then
        NAME=$(basename "$IMG" .ext3)
        MNT="/tmp/${NAME}"
    fi
fi

if [ -z "$IMG" ]; then
    echo "No rootfs image found! Place <distro>.ext3 in /mnt/us/"
    exit 1
fi

if [ -f "$MNT/bin/bash" ] || [ -f "$MNT/usr/bin/bash" ] 2>/dev/null; then
    SHELL_CMD="/bin/bash -l"
else
    SHELL_CMD="/bin/sh -l"
fi

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

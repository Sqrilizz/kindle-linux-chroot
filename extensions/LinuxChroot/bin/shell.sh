#!/bin/sh

KTERM=/mnt/us/extensions/kterm

IMAGES=""
COUNT=0
for f in /mnt/us/*.ext3; do
    [ -f "$f" ] || continue
    COUNT=$((COUNT + 1))
    IMAGES="${IMAGES} ${f}"
done

if [ "$COUNT" -eq 0 ]; then
    echo "No rootfs image found! Place <distro>.ext3 in /mnt/us/"
    exit 1
elif [ "$COUNT" -eq 1 ]; then
    IMG=$(echo "$IMAGES" | tr -s ' ' | cut -d' ' -f2)
    NAME=$(basename "$IMG" .ext3)
    MNT="/tmp/${NAME}"
else
    echo "=== Select distro ==="
    I=1
    for f in $IMAGES; do
        NAME=$(basename "$f" .ext3)
        echo "  ${I}) ${NAME}"
        I=$((I + 1))
    done
    echo "====================="
    printf "Choice [1]: "
    read CHOICE
    [ -z "$CHOICE" ] && CHOICE=1
    IMG=$(echo "$IMAGES" | tr -s ' ' | cut -d' ' -f$((CHOICE + 1)))
    NAME=$(basename "$IMG" .ext3)
    MNT="/tmp/${NAME}"
fi

if [ -z "$IMG" ] || [ ! -f "$IMG" ]; then
    echo "Invalid selection"
    exit 1
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

if [ -f "$MNT/bin/bash" ] || [ -f "$MNT/usr/bin/bash" ]; then
    SHELL_CMD="/bin/bash -l"
else
    SHELL_CMD="/bin/sh -l"
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

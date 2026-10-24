#!/bin/sh

KTERM=/mnt/us/extensions/kterm

# Print the Nth .ext3 file found in /mnt/us/ (portable, tolerates spaces)
pick_image() {
    N=0
    for f in /mnt/us/*.ext3; do
        [ -f "$f" ] || continue
        N=$((N + 1))
        if [ "$N" -eq "$1" ]; then
            echo "$f"
            return
        fi
    done
}

COUNT=0
for f in /mnt/us/*.ext3; do
    [ -f "$f" ] || continue
    COUNT=$((COUNT + 1))
done

# Optional argument from the KUAL menu: the exact image path
if [ -n "$1" ] && [ -f "$1" ] && case "$1" in *.ext3) true ;; *) false ;; esac; then
    IMG="$1"
elif [ "$COUNT" -eq 0 ]; then
    echo "No rootfs image found! Place <distro>.ext3 in /mnt/us/"
    exit 1
elif [ "$COUNT" -eq 1 ]; then
    IMG=$(pick_image 1)
else
    echo "=== Select distro ==="
    I=1
    for f in /mnt/us/*.ext3; do
        [ -f "$f" ] || continue
        NAME=$(basename "$f" .ext3)
        echo "  ${I}) ${NAME}"
        I=$((I + 1))
    done
    echo "====================="
    printf "Choice [1]: "
    read -r CHOICE
    [ -z "$CHOICE" ] && CHOICE=1
    case "$CHOICE" in
        *[!0-9]*) CHOICE=1 ;;
    esac
    [ "$CHOICE" -gt "$COUNT" ] && CHOICE=1
    IMG=$(pick_image "$CHOICE")
fi

if [ -z "$IMG" ] || [ ! -f "$IMG" ]; then
    echo "Invalid selection"
    exit 1
fi

NAME=$(basename "$IMG" .ext3)
MNT="/tmp/${NAME}"

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

DPI=$(grep DPI /var/log/Xorg.0.log 2>/dev/null | sed -n 's/.*(\([0-9]\+\), [0-9]\+).*/\1/p')
PARAM=""
if [ -n "$DPI" ] && [ "$DPI" -gt 290 ] 2>/dev/null; then
    PARAM="-l ${KTERM}/layouts/keyboard-300dpi.xml"
elif [ -n "$DPI" ] && [ "$DPI" -gt 200 ] 2>/dev/null; then
    PARAM="-l ${KTERM}/layouts/keyboard-200dpi.xml"
fi

export TERM=xterm
export TERMINFO=${KTERM}/vte/terminfo

# Unquoted ${PARAM} is intentional: when empty it must disappear completely,
# kterm would otherwise receive an empty argument and fail.
# shellcheck disable=SC2086
${KTERM}/bin/kterm ${PARAM} -e "chroot $MNT $SHELL_CMD" &

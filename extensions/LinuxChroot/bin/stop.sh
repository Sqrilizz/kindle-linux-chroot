#!/bin/sh
# Stop and unmount all Linux chroots

unmount_chroot() {
    MNT="$1"
    if mount | grep -q "$MNT"; then
        echo "Stopping $MNT..."
        kill -9 $(lsof -t "$MNT/" 2>/dev/null) 2>/dev/null
        umount "$MNT/run/dbus/" 2>/dev/null
        umount "$MNT/sys" 2>/dev/null
        umount "$MNT/proc" 2>/dev/null
        umount "$MNT/dev/pts" 2>/dev/null
        umount "$MNT/dev" 2>/dev/null
        sync
        umount "$MNT" 2>/dev/null
        echo "$MNT unmounted."
    fi
}

unmount_chroot /tmp/debian
unmount_chroot /tmp/alpine
echo "All chroots stopped."

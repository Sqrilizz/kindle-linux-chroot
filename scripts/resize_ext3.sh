#!/bin/bash
set -e

# Resize an ext2/ext3/ext4 image file (e.g. *.ext3 rootfs images for Kindle).
#
# Usage:
#   sudo ./resize_ext3.sh <image> <new_size_mb>
#
# Examples:
#   sudo ./resize_ext3.sh debian.ext3 2048    # grow or shrink to 2GB
#
# Notes:
#   - Image must NOT be mounted or attached to a loop device
#   - Growing is non-destructive; shrinking requires free space inside the fs
#     (resize2fs refuses beforehand if data would be lost)
#   - Always keep a backup copy when shrinking

usage() {
    echo "Usage: sudo $0 <image.ext3> <new_size_mb>"
    exit 1
}

[ $# -ne 2 ] && usage

IMG="$1"
NEW_MB="$2"

[ -f "$IMG" ] || { echo "Error: file not found: $IMG"; exit 1; }
case "$NEW_MB" in
    ''|*[!0-9]*) echo "Error: new size must be a number of MB"; exit 1 ;;
esac

if [ "$EUID" -ne 0 ]; then
    echo "Error: this script must be run with sudo/root privileges."
    exit 1
fi

for cmd in truncate stat e2fsck resize2fs losetup; do
    command -v "$cmd" >/dev/null 2>&1 || {
        echo "Error: required command '$cmd' is missing. Install e2fsprogs."
        exit 1
    }
done

if losetup -j "$IMG" 2>/dev/null | grep -q .; then
    echo "Error: image is attached to a loop device."
    echo "Detach it first with: sudo losetup -d <loopdev>"
    exit 1
fi

if mount | grep -F "$IMG" >/dev/null 2>&1; then
    echo "Error: image appears to be mounted. Unmount it first."
    exit 1
fi

CUR_BYTES=$(stat -c%s "$IMG")
CUR_MB=$(( CUR_BYTES / 1048576 ))
TSIZE=$(tune2fs -l "$IMG" 2>/dev/null | awk '/Block count:/ {print $3}')
BSIZE=$(tune2fs -l "$IMG" 2>/dev/null | awk '/Block size:/ {print $3}')
FS_MB=$(( TSIZE * BSIZE / 1048576 ))
echo "Image:        $IMG"
echo "File size:    ${CUR_MB} MB"
echo "FS size:      ${FS_MB} MB"
echo "Target size:  ${NEW_MB} MB"
echo ""
CAUSE=$(if [ "$NEW_MB" -gt "$CUR_MB" ]; then echo "grow"; elif [ "$NEW_MB" -lt "$CUR_MB" ]; then echo "shrink"; else echo "no change"; fi)

if [ "$CAUSE" = "no change" ]; then
    echo "Nothing to do: target size equals current file size."
    exit 0
fi

if [ "$CAUSE" = "shrink" ] && [ "$NEW_MB" -gt "$FS_MB" ]; then
    echo "Wrong direction: file is bigger than fs (${CUR_MB}MB file, ${FS_MB}MB fs)."
    echo "Run with: sudo $0 $IMG $FS_MB     # to trim the file, or a smaller size to shrink fs+file"
    exit 1
fi

printf "Proceed? '[y]es/N' : "
read -r CONFIRM < /dev/tty 2>/dev/null || read -r CONFIRM
case "$CONFIRM" in y|Y|yes|Yes) ;; *) echo "Aborted."; exit 0;; esac

# 1. Make the file the right size
if [ "$CAUSE" = "grow" ]; then
    echo "[*] Growing file to ${NEW_MB} MB..."
    truncate -s "${NEW_MB}M" "$IMG"
fi

# 2. fsck before resizing (resize2fs requires a clean, checked fs)
echo "[*] Running fsck..."
e2fsck -fp "$IMG" || {
    echo "Error: fsck failed with code $?. The image may be damaged - run: e2fsck -y $IMG"
    exit 1
}

# 3. Resize the filesystem inside
echo "[*] Resizing filesystem..."
if [ "$CAUSE" = "grow" ]; then
    resize2fs "$IMG"
else
    if ! resize2fs "$IMG" "${NEW_MB}M"; then
        echo "Error: could not shrink the filesystem to ${NEW_MB} MB. Image was NOT changed."
        exit 1
    fi
    # 5. Shrink the file to match the fs
    echo "[*] Shrinking file to the new filesystem size..."
    FS_BYTES=$(tune2fs -l "$IMG" 2>/dev/null | awk -v b="$BSIZE" '/Block count:/ {print $3 * b}')
    truncate -s "$(( (FS_BYTES + 1048575) / 1048576 ))M" "$IMG"
fi

echo "[*] Verifying..."
e2fsck -fp "$IMG" || {
    echo "Warning: post-resize fsck returned issues - run 'e2fsck -y $IMG' before use."
}
echo "[*] Success! New file size: $(du -h "$IMG" | cut -f1)"

#!/bin/bash
set -e

# Container entrypoint. qemu-user-static is installed at run time on purpose:
# its postinst registers arm binfmt handlers, which only works in a
# privileged container (at build time those registration attempts would fail).
if ! grep -q 'qemu-arm' /proc/sys/fs/binfmt_misc 2>/dev/null; then
    echo "Docker wrapper: registering armhf binfmt handlers..."
    apt-get update -qq
    apt-get install -y -qq qemu-user-static >/dev/null
fi

exec bash scripts/build_rootfs.sh "$@"

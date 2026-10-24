#!/usr/bin/env bash
set -e

# Run build_rootfs.sh inside Docker: works on Linux, macOS and Windows.
# Usage is identical to build_rootfs.sh:
#
#   ./build_docker.sh --distro debian --size 1024
#   ./build_docker.sh --distro alpine --size 256
#
# The resulting *.ext3 file appears in the repo directory (mount = repo).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
IMAGE="kindle-linux-chroot-builder"

command -v docker >/dev/null 2>&1 || {
    echo "Error: docker is not installed. See https://docs.docker.com/get-docker/"
    exit 1
}

echo "[*] Building container image (${IMAGE})..."
docker build -t "$IMAGE" "$REPO_DIR"

echo "[*] Building rootfs container..."
# --privileged is required for loop mounts and binfmt registration
docker run --rm --privileged -v "$REPO_DIR":/work -w /work "$IMAGE" "$@"

# Files are created as root inside the container - give them back to the user.
# Only top-level *.ext3 images are touched, nothing else is chowned.
docker run --rm -v "$REPO_DIR":/chown alpine sh -c \
    "chown '$(id -u):$(id -g)' /chown/*.ext3 2>/dev/null || true"

echo "[*] Done. Image(s) ready in ${REPO_DIR}"

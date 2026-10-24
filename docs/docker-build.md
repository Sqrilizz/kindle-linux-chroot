# Building with Docker (macOS / Windows / Linux)

This is for hosts that cannot run the native `build_rootfs.sh` — most live on macOS, Windows, or Linux distros without debootstrap/qemu packages.

## Requirements

- Docker Desktop or docker engine with `--privileged` support (default everywhere)
- ~2 GB free disk space per image

## Quick start

```bash
git clone https://github.com/Sqrilizz/kindle-linux-chroot.git
cd kindle-linux-chroot/scripts

# Debian build (works out of the box)
./build_docker.sh --distro debian --size 1024

# Alpine build
./build_docker.sh --distro alpine --size 256

# Arch build
./build_docker.sh --distro arch --size 2048

# Void build
./build_docker.sh --distro void --size 1024
```

Without arguments the interactive menu is used:

```bash
./build_docker.sh
```

The built `.ext3` image lands in the repo directory. Interactive `read` prompts (when running without arguments) require a TTY — on macOS/Windows run the resulting command in a normal terminal, not CI.

## Why --privileged?

The builder needs two things that only a privileged container can do:

1. Mount the new `.ext3` file as a loop device
2. Register the ARM binfmt handlers (via `qemu-user-static`, installed at container run time) so the armhf `debootstrap` second stage can run

## Troubleshooting

**`operation not permitted`** — the Docker daemon cannot start privileged containers. Docker Desktop must be installed natively for your platform (e.g. Docker Desktop for macOS, not just remote docker CLI).

**No files on the host** — the image is written into the repo mount (`/work`). If you passed a custom `--out`, it must point inside the repo directory mounted in the container.

**Files owned by root** — `build_docker.sh` automatically chowns the created `.ext3` image; if you passed a custom `--out`, fix ownership with `sudo chown $USER:$(id -g) <image>`.

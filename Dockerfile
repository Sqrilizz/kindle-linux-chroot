# Container used to build Kindle rootfs images on any host with Docker,
# including macOS and Windows (binfmt for armhf is registered at run time,
# which requires a privileged container).
FROM debian:trixie-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    debootstrap \
    e2fsprogs \
    curl \
    wget \
    ca-certificates \
    xz-utils \
    bzip2 \
    bash \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /work
ENTRYPOINT ["bash", "scripts/docker_entrypoint.sh"]

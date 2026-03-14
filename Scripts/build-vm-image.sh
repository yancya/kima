#!/usr/bin/env bash
set -euo pipefail

# Build Alpine Linux aarch64 rootfs with podman pre-installed
# Kernel and initrd are extracted from the rootfs to ensure version consistency.
# Requires: podman (or Docker-compatible runtime)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="${PROJECT_DIR}/Resources"
ALPINE_VERSION="3.21"
ROOTFS_SIZE_MB=2048

mkdir -p "${OUTPUT_DIR}/kernel" "${OUTPUT_DIR}/rootfs"

echo "=== Building rootfs via podman ==="

# Build context: Dockerfile that creates the rootfs
TMPDIR=$(mktemp -d)
trap "rm -rf ${TMPDIR}" EXIT

cat > "${TMPDIR}/Dockerfile" <<'DOCKERFILE'
FROM alpine:3.21 AS builder

# Install packages needed in the guest VM
# linux-virt provides kernel + initrd (version-matched)
RUN apk add --no-cache \
    linux-virt \
    podman \
    crun \
    conmon \
    iptables \
    ip6tables \
    fuse-overlayfs \
    slirp4netns \
    openrc \
    e2fsprogs \
    shadow \
    && rc-update add cgroups default

# Configure podman for rootless operation
RUN echo "unqualified-search-registries = ['podman.io']" > /etc/containers/registries.conf.d/00-unqualified.conf

# Copy kernel and initrd to /output for extraction
RUN mkdir -p /output \
    && cp /boot/vmlinuz-virt /output/vmlinuz \
    && cp /boot/initramfs-virt /output/initrd

# Build the ext4 rootfs image
FROM alpine:3.21 AS imager
RUN apk add --no-cache e2fsprogs
COPY --from=builder / /rootfs-content/
# Remove Docker-specific artifacts and /output (not part of rootfs)
RUN rm -f /rootfs-content/.podmanenv \
    && rm -rf /rootfs-content/output
RUN mkdir -p /output
# Copy kernel files to output
COPY --from=builder /output/vmlinuz /output/vmlinuz
COPY --from=builder /output/initrd /output/initrd
ARG ROOTFS_SIZE_MB=2048
RUN dd if=/dev/zero of=/output/rootfs.img bs=1M count=0 seek=${ROOTFS_SIZE_MB} \
    && mkfs.ext4 -d /rootfs-content /output/rootfs.img
DOCKERFILE

# Build for linux/arm64
podman build \
    --platform linux/arm64 \
    --build-arg ROOTFS_SIZE_MB="${ROOTFS_SIZE_MB}" \
    -t kima-rootfs-builder \
    "${TMPDIR}"

# Extract rootfs image, kernel, and initrd
CONTAINER_ID=$(podman create --platform linux/arm64 kima-rootfs-builder)
podman cp "${CONTAINER_ID}:/output/rootfs.img" "${OUTPUT_DIR}/rootfs/rootfs.img"
podman cp "${CONTAINER_ID}:/output/vmlinuz" "${OUTPUT_DIR}/kernel/vmlinuz"
podman cp "${CONTAINER_ID}:/output/initrd" "${OUTPUT_DIR}/kernel/initrd"
podman rm "${CONTAINER_ID}"

echo "=== Build complete ==="
echo "Kernel: ${OUTPUT_DIR}/kernel/vmlinuz"
echo "Initrd: ${OUTPUT_DIR}/kernel/initrd"
echo "Rootfs: ${OUTPUT_DIR}/rootfs/rootfs.img"
echo ""
echo "Copy these to the machine directory:"
echo "  cp ${OUTPUT_DIR}/kernel/vmlinuz ~/Library/Application\\ Support/kima/machines/default/"
echo "  cp ${OUTPUT_DIR}/kernel/initrd ~/Library/Application\\ Support/kima/machines/default/"
echo "  cp ${OUTPUT_DIR}/rootfs/rootfs.img ~/Library/Application\\ Support/kima/machines/default/"

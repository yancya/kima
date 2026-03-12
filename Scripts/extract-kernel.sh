#!/usr/bin/env bash
set -euo pipefail

# Extract uncompressed ARM64 kernel Image from Alpine linux-virt package

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="${PROJECT_DIR}/Resources/kernel"
MACHINE_DIR="$HOME/Library/Application Support/kima/machines/default"

mkdir -p "${OUTPUT_DIR}"

echo "=== Extracting uncompressed kernel from Alpine linux-virt ==="

podman run --rm --platform linux/arm64 \
    -v "${OUTPUT_DIR}:/output" \
    alpine:3.21 sh -c '
apk add --no-cache linux-virt binutils gzip > /dev/null 2>&1

VMLINUZ=/boot/vmlinuz-virt

# Method 1: objcopy to extract .linux section (EFI stub kernel)
if objcopy -O binary -j .linux ${VMLINUZ} /tmp/vmlinux.gz 2>/dev/null && [ -s /tmp/vmlinux.gz ]; then
    echo "Extracted .linux section via objcopy"
    gunzip -c /tmp/vmlinux.gz > /output/Image 2>/dev/null || mv /tmp/vmlinux.gz /output/Image
    if [ -s /output/Image ]; then
        echo "Decompressed kernel: $(wc -c < /output/Image) bytes"
    fi
fi

# Method 2: if method 1 failed, try extracting raw gzip stream
if [ ! -s /output/Image ]; then
    echo "objcopy failed, trying raw gzip extraction..."
    # Use a C program to find the gzip magic bytes
    cat > /tmp/find_gz.c <<CEOF
#include <stdio.h>
#include <stdlib.h>
int main(int argc, char *argv[]) {
    FILE *f = fopen(argv[1], "rb");
    if (!f) return 1;
    int c, prev = -1, pprev = -1;
    long offset = 0;
    while ((c = fgetc(f)) != EOF) {
        if (pprev == 0x1f && prev == 0x8b && c == 0x08) {
            printf("%ld\n", offset - 2);
            fclose(f);
            return 0;
        }
        pprev = prev;
        prev = c;
        offset++;
    }
    fclose(f);
    return 1;
}
CEOF
    apk add --no-cache gcc musl-dev > /dev/null 2>&1
    gcc -o /tmp/find_gz /tmp/find_gz.c
    OFFSET=$(/tmp/find_gz ${VMLINUZ})
    if [ -n "${OFFSET}" ]; then
        echo "Found gzip at offset ${OFFSET}"
        tail -c +$((OFFSET + 1)) ${VMLINUZ} | gunzip > /output/Image 2>/dev/null
    fi
fi

if [ ! -s /output/Image ]; then
    echo "ERROR: Failed to extract kernel"
    exit 1
fi

echo "Kernel extracted: $(wc -c < /output/Image) bytes"
file /output/Image || true
cp /boot/initramfs-virt /output/initrd-virt
echo "Done!"
'

echo "=== Copying to machine directory ==="
cp "${OUTPUT_DIR}/Image" "${MACHINE_DIR}/vmlinuz"
[ -f "${OUTPUT_DIR}/initrd-virt" ] && cp "${OUTPUT_DIR}/initrd-virt" "${MACHINE_DIR}/initrd"

ls -lh "${MACHINE_DIR}/vmlinuz"
file "${MACHINE_DIR}/vmlinuz"

#!/usr/bin/env bash
set -euo pipefail

# Inject kima-agent binary into the rootfs image
# Uses debugfs (ext2/3/4 tool) to write files without mounting

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
AGENT_BINARY="${PROJECT_DIR}/.build/aarch64-swift-linux-musl/release/kima-agent"
ROOTFS_IMG="$HOME/Library/Application Support/kima/machines/default/rootfs.img"

if [ ! -f "${AGENT_BINARY}" ]; then
    echo "Error: kima-agent binary not found"
    exit 1
fi

if [ ! -f "${ROOTFS_IMG}" ]; then
    echo "Error: rootfs.img not found"
    exit 1
fi

echo "=== Injecting kima-agent into rootfs ==="

# Prepare files to inject
TMPDIR=$(mktemp -d)
trap "rm -rf ${TMPDIR}" EXIT

cp "${AGENT_BINARY}" "${TMPDIR}/kima-agent"

# OpenRC init script
cat > "${TMPDIR}/kima-agent-init" <<'EOF'
#!/sbin/openrc-run
name="kima-agent"
description="Kima Guest Agent"
command="/usr/local/bin/kima-agent"
command_background=true
pidfile="/run/${RC_SVCNAME}.pid"
output_log="/var/log/kima-agent.log"
error_log="/var/log/kima-agent.log"

depend() {
    need localmount modules
    after networking
}
EOF

# Network interfaces (static IP — VZ NAT doesn't support AF_PACKET for DHCP)
cat > "${TMPDIR}/interfaces" <<'EOF'
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet static
    address 192.168.64.4
    netmask 255.255.255.0
    gateway 192.168.64.1
EOF

# Hostname
echo "kima" > "${TMPDIR}/hostname"

# DNS
echo "nameserver 8.8.8.8" > "${TMPDIR}/resolv.conf"

# inittab addition for hvc0
echo "hvc0::respawn:/sbin/getty 38400 hvc0" > "${TMPDIR}/hvc0-inittab-line"

# Kernel modules to load early (vsock needed before kima-agent starts)
cat > "${TMPDIR}/modules" <<'EOF'
vsock
vmw_vsock_virtio_transport
virtio_net
EOF

# Use podman to run debugfs (since we need Linux tools for ext4)
podman run --rm \
    --platform linux/arm64 \
    -v "${ROOTFS_IMG}:/work/rootfs.img" \
    -v "${TMPDIR}:/inject:ro" \
    alpine:3.21 sh -c '
apk add --no-cache e2fsprogs e2fsprogs-extra > /dev/null 2>&1

# Use debugfs to write files into the ext4 image
# rm before write to handle re-injection (debugfs write fails on existing files)
debugfs -w /work/rootfs.img <<DEBUGFS_CMDS
cd /usr/local/bin
rm kima-agent
write /inject/kima-agent kima-agent
set_inode_field kima-agent mode 0100755

cd /etc/init.d
rm kima-agent
write /inject/kima-agent-init kima-agent
set_inode_field kima-agent mode 0100755

cd /etc/runlevels/default
rm kima-agent
symlink kima-agent /etc/init.d/kima-agent

mkdir /etc/network
cd /etc/network
rm interfaces
write /inject/interfaces interfaces

cd /etc
rm hostname
write /inject/hostname hostname
rm resolv.conf
write /inject/resolv.conf resolv.conf
rm modules
write /inject/modules modules

cd /etc/runlevels/default
rm networking
symlink networking /etc/init.d/networking
rm modules
symlink modules /etc/init.d/modules
DEBUGFS_CMDS

echo "Done!"
'

echo "=== Agent injected into rootfs ==="

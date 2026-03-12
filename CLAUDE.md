# Kima - Development Guide

## Build

```bash
# Host CLI (macOS) — requires Xcode
swift build
codesign --entitlements kima.entitlements --force -s - .build/debug/kima

# Guest Agent (Linux arm64) — requires swiftly toolchain + static Linux SDK
source ~/.swiftly/env.sh
swift build --product kima-agent --swift-sdk aarch64-swift-linux-musl -c release
```

## Toolchain

- **Host (kima)**: Apple Swift or swift.org Swift — both work for macOS builds
- **Guest Agent (kima-agent)**: Must use **swift.org toolchain** (via `swiftly`) for cross-compilation. Apple's Xcode Swift and swift.org Swift have incompatible `.swiftmodule` formats, so the static Linux SDK only works with the swift.org toolchain.
- **Swift SDK**: `swift-6.2.4-RELEASE_static-linux-0.1.0` installed via `swift sdk install`
- **swiftly**: Swift version manager, installed via `brew install swiftly && swiftly init`

## Test

```bash
swift test  # requires Xcode (not just CommandLineTools) for XCTest
```

## VM Image Build

```bash
# Build Alpine rootfs (requires podman with machine running)
podman machine start
./Scripts/build-vm-image.sh

# Extract uncompressed kernel (VZLinuxBootLoader needs raw ARM64 Image, not PE/EFI vmlinuz)
./Scripts/extract-kernel.sh

# Inject kima-agent into rootfs
./Scripts/inject-agent.sh
```

## Architecture

```
Sources/
├── kima/           # CLI executable (swift-argument-parser)
│   ├── Kima.swift  # @main, subcommand registration
│   └── Commands/   # machine, run, ps, stop, rm, pull, images, _daemon
├── kima-agent/     # Guest agent (runs inside Linux VM)
│   ├── Main.swift  # vsock/TCP listener
│   ├── RPCHandler.swift   # JSON-RPC dispatch
│   ├── PodmanClient.swift # podman CLI wrapper
│   └── Networking.swift   # vsock + TCP socket abstractions
├── KimaCore/       # Host library (Virtualization.framework)
│   ├── VM/         # VZVirtualMachine wrapper, config builder, lifecycle
│   ├── Config/     # MachineConfig, Paths (~Library/Application Support/kima/)
│   ├── Storage/    # DiskImage (sparse raw via ftruncate)
│   ├── Guest/      # GuestAgentClient (vsock), DaemonClient (Unix socket)
│   └── Network/    # PortForwarding (host TCP → vsock)
└── KimaKit/        # Shared types (both host and guest)
    ├── Protocol.swift     # JSONRPCRequest/Response, RPCMethod constants
    └── MachineState.swift # ContainerInfo, ImageInfo, MachineState
```

## Key Design Notes

- `VZVirtualMachine` requires `@MainActor` isolation
- `kima machine start` forks `kima _daemon` which holds the VM process
- Daemon writes PID to `daemon.pid`, CLI checks it for status
- Communication: CLI → daemon.sock (Unix socket) → vsock → guest agent → podman
- URL `.path()` returns percent-encoded strings — always use `.path(percentEncoded: false)`
- Alpine netboot vmlinuz is PE/EFI format; `VZLinuxBootLoader` needs uncompressed ARM64 Image — `extract-kernel.sh` handles this
- Kernel cmdline: `console=hvc0 root=/dev/vda rootfstype=ext4 rw modules=virtio_blk`
- rootfs is ext4, built via podman (macOS can't mount ext4); file injection uses `debugfs`

## Current Status

- VM boots Alpine Linux successfully (kernel + initrd + rootfs)
- kima-agent installed in rootfs as OpenRC service
- Networking (eth0 DHCP) fails — AF_PACKET not supported in Virtualization.framework NAT
- Port forwarding TODO: bidirectional relay implementation
- Rosetta x86_64 support intentionally excluded (Rosetta 2 EOL expected)

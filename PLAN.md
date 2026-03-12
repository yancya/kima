# Kima - macOS Native Container Management Tool

macOS (Apple Silicon) 向けのネイティブコンテナ管理 CLI ツール。
Swift + Virtualization.framework で Linux VM を直接管理し、VM 内の podman でコンテナを実行する。

## Architecture

```
Host (macOS/Swift)              VM (Alpine Linux)
┌──────────────────┐           ┌──────────────────┐
│  kima CLI         │           │  Guest Agent (Go) │
│  (swift-argument- │◄─vsock──►│  └─ podman/crun   │
│   parser)         │           │                    │
│  KimaCore         │           └──────────────────┘
│  └─ Virtualization.framework
└──────────────────┘
```

## Design Decisions

- **Virtualization.framework 直叩き**: vfkit (Podman) や QEMU を介さず Swift から直接呼ぶ
- **VM 内は Alpine Linux + podman**: コンテナ管理を再実装せず、podman に委譲する
- **Guest Agent は Go**: Linux 向けクロスコンパイルが容易、コンテナ系ライブラリが豊富
- **通信は vsock**: SSH より低レイテンシ、鍵管理不要
- **ディスクは raw image**: APFS スパースファイルで薄いプロビジョニング
- **カーネル管理**: `kima machine upgrade` でホスト側差し替え (VZLinuxBootLoader 方式、EFI ブートではない)

## Project Structure

```
kima/
├── Package.swift
├── Sources/
│   ├── kima/                    # CLI executable (swift-argument-parser)
│   │   └── main.swift
│   ├── KimaCore/                # Library: VM lifecycle, storage, network
│   │   ├── VM/
│   │   │   ├── VirtualMachine.swift
│   │   │   ├── VMConfiguration.swift
│   │   │   ├── VMLifecycle.swift
│   │   │   └── VMBootloader.swift
│   │   ├── Storage/
│   │   │   ├── DiskImage.swift
│   │   │   └── FileSharing.swift
│   │   ├── Network/
│   │   │   ├── NetworkConfig.swift
│   │   │   └── PortForwarding.swift
│   │   ├── Guest/
│   │   │   ├── GuestAgent.swift
│   │   │   ├── GuestProvisioner.swift
│   │   │   └── SSHClient.swift
│   │   ├── Container/
│   │   │   ├── ContainerEngine.swift
│   │   │   ├── ImageManager.swift
│   │   │   └── ContainerSpec.swift
│   │   └── Config/
│   │       ├── MachineConfig.swift
│   │       └── Paths.swift
│   └── KimaKit/                 # Shared models/protocols
│       ├── Models.swift
│       └── Protocol.swift
├── GuestAgent/                  # Go project: runs inside the Linux VM
├── Resources/
│   ├── kernel/
│   ├── initrd/
│   └── rootfs/
├── Scripts/
│   ├── build-kernel.sh
│   ├── build-rootfs.sh
│   └── package.sh
└── Tests/
```

## Virtualization.framework APIs

| Purpose | API |
|---|---|
| VM object | `VZVirtualMachine` |
| Configuration | `VZVirtualMachineConfiguration` |
| Boot | `VZLinuxBootLoader` |
| Storage | `VZVirtioBlockDeviceConfiguration` + `VZDiskImageStorageDeviceAttachment` |
| Networking | `VZVirtioNetworkDeviceConfiguration` + `VZNATNetworkDeviceAttachment` |
| File sharing | `VZVirtioFileSystemDeviceConfiguration` + `VZSharedDirectory` |
| Console | `VZVirtioConsoleDeviceConfiguration` |
| Host-guest comms | `VZVirtioSocketDeviceConfiguration` (vsock) |
| Rosetta (optional) | `VZLinuxRosettaDirectoryShare` |

## CLI Commands

### MVP (Phase 1)

```
kima machine create [--cpus N] [--memory SIZE] [--disk SIZE]
kima machine start
kima machine stop
kima machine status
kima machine upgrade

kima run [-p HOST:CONTAINER] IMAGE [COMMAND]
kima ps [--all]
kima stop CONTAINER
kima rm CONTAINER
kima pull IMAGE
kima images
```

### Phase 2

- `kima exec [-it] CONTAINER COMMAND`
- `kima logs [-f] CONTAINER`
- `kima build -f Dockerfile .`
- `kima machine ssh`
- Bind mounts (`-v`) via virtiofs
- Rosetta x86_64 container support

### Phase 3

- `kima compose up/down`
- Named volumes
- Container networking (bridge)
- Resource limits (CPU, memory)

### Phase 4

- SwiftUI menu bar GUI
- Homebrew formula distribution

## Host-Guest Communication Flow

```
1. User: kima run -p 8080:80 nginx
2. CLI (Swift) connects to VM's vsock
3. Sends JSON-RPC: {"method": "container.run", "params": {"image": "nginx", "ports": ["8080:80"]}}
4. Guest Agent runs: podman run -d -p 80:80 nginx
5. Guest Agent responds: {"id": "abc123", "status": "running"}
6. Port forwarding: host:8080 -> vsock -> guest agent -> container:80
```

## Dependencies

### Swift (Host)

- `apple/swift-argument-parser` - CLI
- `apple/swift-log` - Logging
- `Virtualization.framework` - VM management
- Platform: `.macOS(.v13)` minimum

### Go (Guest Agent)

- Minimal, static binary for linux/arm64
- JSON-RPC over vsock

### VM Image

- Alpine Linux (arm64) - ~50 MB rootfs
- Pre-installed: podman, crun, conmon
- Linux kernel 6.x (arm64, virtio drivers, cgroups v2)

## Build

```bash
swift build -c release
codesign --entitlements kima.entitlements --force -s - .build/release/kima
```

Entitlements required:
- `com.apple.security.virtualization`

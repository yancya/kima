# kima

macOS (Apple Silicon) native container management CLI.

Swift + Virtualization.framework で Linux VM を直接管理し、VM 内の podman でコンテナを実行する。Docker Desktop の代替を目指す軽量ツール。

## Features

- Virtualization.framework 直叩き（QEMU/vfkit 不要）
- vsock によるホスト-ゲスト通信（SSH 不要）
- プロジェクト全体が Swift（ホスト CLI もゲストエージェントも）
- Alpine Linux ベースの軽量 VM

## Requirements

- macOS 15 (Sequoia) + Apple Silicon
- Xcode (ビルド・テスト用)
- podman (VM イメージビルド用)
- swiftly + Swift static Linux SDK (ゲストエージェントのクロスコンパイル用)

## Quick Start

```bash
# ビルド
swift build
codesign --entitlements kima.entitlements --force -s - .build/debug/kima

# VM イメージ準備
podman machine start
./Scripts/build-vm-image.sh
./Scripts/extract-kernel.sh
./Scripts/inject-agent.sh

# 使う
kima machine create --cpus 2 --memory 2048 --disk 20
kima machine start
kima machine status
kima run -p 8080:80 nginx   # (実装中)
kima ps
kima machine stop
```

## CLI Commands

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

## Architecture

```
Host (macOS/Swift)               VM (Alpine Linux)
┌──────────────────┐            ┌──────────────────────┐
│  kima CLI         │            │  kima-agent (Swift)   │
│  (ArgumentParser) │◄─vsock───►│  └─ podman/crun       │
│  KimaCore         │            │                       │
│  └─ Virtualization.framework   └──────────────────────┘
└──────────────────┘
```

## License

[WTFPL](LICENSE) — Do What The Fuck You Want To Public License

See [DISCLAIMER](DISCLAIMER) for warranty information.

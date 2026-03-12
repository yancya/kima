// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "kima",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "kima", targets: ["kima"]),
        .executable(name: "kima-agent", targets: ["kima-agent"]),
        .library(name: "KimaCore", targets: ["KimaCore"]),
        .library(name: "KimaKit", targets: ["KimaKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "kima",
            dependencies: [
                "KimaCore",
                "KimaKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Logging", package: "swift-log"),
            ]
        ),
        .executableTarget(
            name: "kima-agent",
            dependencies: [
                "KimaKit",
                .product(name: "Logging", package: "swift-log"),
            ]
        ),
        .target(
            name: "KimaCore",
            dependencies: [
                "KimaKit",
                .product(name: "Logging", package: "swift-log"),
            ],
            linkerSettings: [
                .linkedFramework("Virtualization"),
            ]
        ),
        .target(
            name: "KimaKit",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
            ]
        ),
        .testTarget(
            name: "KimaCoreTests",
            dependencies: ["KimaCore", "KimaKit"]
        ),
    ]
)

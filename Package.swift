// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AudioBar",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "AudioBar", targets: ["AudioBar"]),
        .library(name: "AudioBarCore", targets: ["AudioBarCore"])
    ],
    targets: [
        .executableTarget(
            name: "AudioBar",
            dependencies: ["AudioBarCore"]
        ),
        .target(
            name: "AudioBarCore",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreAudio")
            ]
        ),
        .testTarget(
            name: "AudioBarCoreTests",
            dependencies: ["AudioBarCore"]
        )
    ]
)

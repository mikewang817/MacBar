// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "MacBar",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "MacBar",
            targets: ["MacBar"]
        )
    ],
    targets: [
        .executableTarget(
            name: "MacBar",
            resources: [
                .process("Resources")
            ]
        )
    ]
)

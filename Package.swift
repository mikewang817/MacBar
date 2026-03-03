// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "MacBar",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "MacBar",
            targets: ["MacBar"]
        )
    ],
    targets: [
        .executableTarget(
            name: "MacBar"
        )
    ]
)

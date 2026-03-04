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
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", revision: "e33eba8513595bde535719c48fedcb10ade5af57")
    ],
    targets: [
        .executableTarget(
            name: "MacBar",
            dependencies: [
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm")
            ],
            resources: [
                .process("Resources")
            ]
        )
    ]
)

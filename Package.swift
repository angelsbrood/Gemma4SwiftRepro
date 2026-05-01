// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "Gemma4SwiftRepro",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift-lm.git",
                 .upToNextMajor(from: "3.31.3")),
        .package(url: "https://github.com/ml-explore/mlx-swift.git",
                 .upToNextMajor(from: "0.31.3")),
        .package(url: "https://github.com/huggingface/swift-transformers.git",
                 .upToNextMajor(from: "1.3.0")),
    ],
    targets: [
        .executableTarget(
            name: "Gemma4SwiftRepro",
            dependencies: [
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "MLXVLM", package: "mlx-swift-lm"),
                .product(name: "MLXHuggingFace", package: "mlx-swift-lm"),
                .product(name: "Transformers", package: "swift-transformers"),
            ]
        ),
    ]
)

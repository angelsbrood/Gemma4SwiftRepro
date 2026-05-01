// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "Gemma4SwiftRepro",
    platforms: [.macOS(.v14)],
    dependencies: [
        // mlx-swift-lm pinned to branch:"main" because swift-lm-response-parser 0.1.0 pins
        // it the same way; SPM rejects a mixed stable+branch graph for the same package.
        .package(url: "https://github.com/ml-explore/mlx-swift-lm.git",
                 branch: "main"),
        .package(url: "https://github.com/ml-explore/mlx-swift.git",
                 .upToNextMajor(from: "0.31.3")),
        .package(url: "https://github.com/huggingface/swift-transformers.git",
                 .upToNextMajor(from: "1.3.0")),
        // 0.1.0 ships with branch:"main" deps internally, which forces unstable resolution
        // here as well. Pinned to its tag commit for reproducibility.
        .package(url: "https://github.com/DePasqualeOrg/swift-lm-response-parser.git",
                 revision: "d6f2cad458762111e5b73579f4acc29afe530c3c"),
    ],
    targets: [
        .executableTarget(
            name: "Gemma4SwiftRepro",
            dependencies: [
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXVLM", package: "mlx-swift-lm"),
                .product(name: "MLXHuggingFace", package: "mlx-swift-lm"),
                .product(name: "Transformers", package: "swift-transformers"),
                .product(name: "LMResponseParser", package: "swift-lm-response-parser"),
                .product(name: "LMResponseParserMLX", package: "swift-lm-response-parser"),
            ]
        ),
    ]
)

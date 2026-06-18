// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HexCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "HexCore", targets: ["HexCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/Clipy/Sauce", branch: "master"),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.11.0"),
        .package(url: "https://github.com/apple/swift-log", from: "1.9.1"),
        // Qwen3-ASR on-device transcription (MLX). Pinned to a specific revision;
        // note its transitive mlx-swift / mlx-swift-lm deps are branch-pinned upstream
        // (reproducibility risk to vendor/pin before release).
        .package(url: "https://github.com/ontypehq/mlx-swift-asr", revision: "f8ea5e6e76824eae903580fcfab0ef15e207b479"),
    ],
    targets: [
	    .target(
	        name: "HexCore",
	        dependencies: [
	            "Sauce",
	            .product(name: "Dependencies", package: "swift-dependencies"),
	            .product(name: "DependenciesMacros", package: "swift-dependencies"),
	            .product(name: "Logging", package: "swift-log"),
	            .product(name: "MLXASR", package: "mlx-swift-asr"),
	        ],
	        path: "Sources/HexCore",
	        resources: [
	            // Qwen3-ASR ships only vocab.json+merges.txt upstream; bundle the
	            // (shared) tokenizer.json so the MLX tokenizer can load offline.
	            .copy("Resources/qwen3-asr-tokenizer.json"),
	        ],
	        linkerSettings: [
	            .linkedFramework("IOKit")
	        ]
	    ),
        .testTarget(
            name: "HexCoreTests",
            dependencies: ["HexCore"],
            path: "Tests/HexCoreTests",
            resources: [
                .copy("Fixtures")
            ]
        ),
    ]
)

// swift-tools-version: 5.9
import PackageDescription

// MonstroSim — GPU-batched headless training engine for the Monstro Shooter game.
// MonstroSim   : shared infra (seedable RNG, constants, map/unit-config loaders).
// MonstroSimGPU: the engine (BatchWorld + on-device player policy + Evolution Strategies),
//                MLX-Swift (Metal); + a Core ML/ANE inference connector.
// MetalGame    : the playable GPU game (full loop in Metal compute, no SpriteKit).
// Python is NOT used; the JAX scale-training port lives separately in ../brax.
let package = Package(
    name: "MonstroSim",
    platforms: [.macOS(.v14)],   // mlx-swift requires macOS 14+
    products: [
        .library(name: "MonstroSim", targets: ["MonstroSim"]),
        .library(name: "MonstroSimGPU", targets: ["MonstroSimGPU"]),
        // CLI: gputrain / gpueval / gprun / aneinfer / gpubench / gpuprofile.
        .executable(name: "monstrosim", targets: ["MonstroCLI"]),
        // Track A: the GPU game — full loop in Metal compute, instanced sprites (no SpriteKit).
        .executable(name: "monstro-game", targets: ["MetalGame"]),
    ],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift", from: "0.31.0"),
    ],
    targets: [
        .target(name: "MonstroSim"),
        .target(name: "MonstroSimGPU", dependencies: [
            "MonstroSim",
            .product(name: "MLX", package: "mlx-swift"),
            .product(name: "MLXRandom", package: "mlx-swift"),
        ]),
        .executableTarget(name: "MonstroCLI", dependencies: ["MonstroSim", "MonstroSimGPU"]),
        .executableTarget(name: "MetalGame"),
        .testTarget(name: "MonstroSimTests", dependencies: ["MonstroSim"]),
    ]
)

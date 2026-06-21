// swift-tools-version: 5.9
import PackageDescription

// MonstroSim — headless, dependency-free simulation of the Monstro Shooter game.
// Used for: automated playtesting, map-difficulty evaluation, training an ML
// player agent (pure-Swift Evolution Strategies), and procedural map generation
// (autoconfig) that uses the agent/policy as the fitness function.
//
// 100% Swift, no Python. The CPU sim/agent/generator have zero dependencies; only the
// optional GPU-batched sim target (MonstroSimGPU) pulls Apple's MLX-Swift (Metal).
let package = Package(
    name: "MonstroSim",
    platforms: [.macOS(.v14)],   // mlx-swift requires macOS 14+
    products: [
        .library(name: "MonstroSim", targets: ["MonstroSim"]),
        .library(name: "MonstroSimGPU", targets: ["MonstroSimGPU"]),
        // CLI: eval / train / autoconfig / parity / bench.
        .executable(name: "monstrosim", targets: ["MonstroCLI"]),
        // Track A: state-buffer -> compute tick -> instanced sprite render (no SpriteKit).
        .executable(name: "monstro-render", targets: ["MetalRender"]),
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
        .executableTarget(name: "MetalRender"),
        .testTarget(name: "MonstroSimTests", dependencies: ["MonstroSim", "MonstroSimGPU"]),
    ]
)

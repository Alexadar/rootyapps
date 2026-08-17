// swift-tools-version: 5.9
import PackageDescription

// FroggoSim — the ONE ruleset, as a loop-less batched program.
//
// Every tensor carries a leading [N] dimension: N = parallel matches. The playable game is this
// program at N = 1; the block generator is the same program at N = 4096. There is no separate
// single-game engine, and the renderer owns no rules.
//
// This is the MonstroSim/GridSim pattern (../../../monstro_shooter.swift/MonstroSim) applied to a
// ballistic jumper. mlx-swift is pinned to 0.31.4 — the exact version MonstroSim resolved and proved.
let package = Package(
    name: "FroggoSim",
    platforms: [.macOS(.v14), .iOS(.v17), .tvOS(.v17), .visionOS(.v1)],
    products: [
        .library(name: "FroggoSim", targets: ["FroggoSim"]),
    ],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift", exact: "0.31.4"),
        .package(path: "../../Reachability/ReachabilityKit"),
    ],
    targets: [
        .target(name: "FroggoSim", dependencies: [
            .product(name: "MLX", package: "mlx-swift"),
            "ReachabilityKit",
        ]),
        .testTarget(name: "FroggoSimTests", dependencies: ["FroggoSim", "ReachabilityKit"]),
    ]
)

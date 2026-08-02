// swift-tools-version: 5.9
import PackageDescription

// MonstroSim — the Monstro Shooter GPU game on Metal. One batched MLX sim (GridSim) drives the playable
// window (N=1), the 3x3 grid (N=9), the headless demo, and torch-parity replay. Models are trained in
// ../torchsim (Python) and loaded as {sizes,w,b} JSON. (The old MLX-Swift ES trainer was retired —
// training lives in torchsim.)
let package = Package(
    name: "MonstroSim",
    platforms: [.macOS(.v14)],   // mlx-swift requires macOS 14+
    products: [
        .executable(name: "monstro-game", targets: ["MetalGame"]),
    ],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift", from: "0.31.0"),
    ],
    targets: [
        .executableTarget(name: "MetalGame", dependencies: [
            .product(name: "MLX", package: "mlx-swift"),
        ]),
    ]
)

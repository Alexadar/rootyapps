// swift-tools-version: 5.9
import PackageDescription

// RelativityKit — the physics core. The world's geometry, not a picture of it.
//
// Foundation + TensorKit + DetMathKit. **No Metal, no SwiftUI, no SpriteKit** — and that exclusion
// is enforced here, in the manifest, rather than by anybody remembering. It is what makes the
// core→presentation boundary structural: a package that cannot import Metal cannot make the GPU
// authoritative, and a package that cannot import SwiftUI cannot let a frame time leak into the
// simulation. Chaos, shimmer and particle jitter live on the other side of this line and never
// feed back across it.
//
// Everything is elementwise over Tensors of matching shape. The Kit is deliberately shape-agnostic:
// hand it [1] and it solves one trajectory, hand it [N, R] and it solves a sweep, and it is the
// same code either way.
let package = Package(
    name: "RelativityKit",
    platforms: [.macOS(.v13), .iOS(.v16), .tvOS(.v16), .watchOS(.v9), .visionOS(.v1)],
    products: [
        .library(name: "RelativityKit", targets: ["RelativityKit"]),
    ],
    dependencies: [
        .package(path: "../../Tensor/TensorKit"),
        .package(path: "../../DetMath/DetMathKit"),
    ],
    targets: [
        .target(name: "RelativityKit", dependencies: [
            .product(name: "TensorKit", package: "TensorKit"),
            .product(name: "DetMathKit", package: "DetMathKit"),
        ]),
        .testTarget(name: "RelativityKitTests", dependencies: ["RelativityKit"]),
    ]
)

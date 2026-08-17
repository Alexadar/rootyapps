// swift-tools-version: 5.9
import PackageDescription

// TensorKit — the vector engine.
//
// Foundation only. No Accelerate, no simd, no Metal, no MLX. That is enforced by this manifest
// rather than by convention, and it is what makes the determinism contract checkable: a package
// that cannot import Metal cannot accidentally make the GPU authoritative, and a package that
// cannot import SwiftUI cannot let a frame time leak into the simulation.
//
// The type itself is lifted from froggo2's ReachabilityKit/Tensor.swift, generalised from its
// rooftop shapes to the ones this game needs. It is the same discipline
// `monstro_shooter.swift/torchsim/env_torch.py` follows: one ruleset, expressed once as a
// loop-less batched program over a leading [N], where the playable game is that program at N = 1.
// It depends on DetMathKit, and the direction matters. DetMathKit is the *scalar kernel* layer —
// a polynomial evaluation is inherently per-element, so `Tensor.map` has to have something to map.
// TensorKit wraps those kernels and exposes the vector forms, so domain code imports TensorKit,
// writes `theta.sin`, and never sees a scalar. `DetMath.sin(Double)` remains reachable but is a
// kernel, and VectorDisciplineTests fails any domain call to it.
let package = Package(
    name: "TensorKit",
    platforms: [.macOS(.v13), .iOS(.v16), .tvOS(.v16), .watchOS(.v9), .visionOS(.v1)],
    products: [
        .library(name: "TensorKit", targets: ["TensorKit"]),
    ],
    dependencies: [
        .package(path: "../../DetMath/DetMathKit"),
    ],
    targets: [
        .target(name: "TensorKit", dependencies: [.product(name: "DetMathKit", package: "DetMathKit")]),
        .testTarget(name: "TensorKitTests", dependencies: ["TensorKit"]),
    ]
)

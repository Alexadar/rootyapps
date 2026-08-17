// swift-tools-version: 5.9
import PackageDescription

// ReachabilityKit — the scalar, closed-form reference implementation and the oracle.
//
// Foundation only. No UIKit, no SwiftUI, no RealityKit, no MLX. That is enforced by this manifest,
// not by convention, and it is what lets the future watchOS companion consume the same ballistics
// (MLX has no watchOS).
//
// Its relationship to FroggoSim is the point: two genuinely different mathematics — a closed-form
// inverse here, batched forward tensor algebra there — that must agree. That agreement is the
// strongest oracle available without a second language, and it is the Swift-side analogue of
// ../../../monstro_shooter.swift/torchsim/parity_diff.py.
let package = Package(
    name: "ReachabilityKit",
    platforms: [.macOS(.v13), .iOS(.v16), .tvOS(.v16), .watchOS(.v9), .visionOS(.v1)],
    products: [
        .library(name: "ReachabilityKit", targets: ["ReachabilityKit"]),
    ],
    targets: [
        .target(name: "ReachabilityKit"),
        .testTarget(name: "ReachabilityKitTests", dependencies: ["ReachabilityKit"]),
    ]
)

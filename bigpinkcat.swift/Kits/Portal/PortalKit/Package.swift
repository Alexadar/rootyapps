// swift-tools-version: 5.9
import PackageDescription

// PortalKit — portal algebra, crossing detection and holonomy.
//
// Foundation + TensorKit + DetMathKit. No Metal: the recursive stencil *renderer* lives in the app
// target, and everything here is the maths it draws. That split is what lets the portal round-trip
// identity be a `swift test` rather than something you check by looking.
//
// A portal here is not only a game conceit. The same 4×4 transform machinery carries an
// Einstein–Rosen bridge, where the transform comes from the metric rather than from placement —
// which is the one portal in games with a citation behind it.
let package = Package(
    name: "PortalKit",
    platforms: [.macOS(.v13), .iOS(.v16), .tvOS(.v16), .watchOS(.v9), .visionOS(.v1)],
    products: [
        .library(name: "PortalKit", targets: ["PortalKit"]),
    ],
    dependencies: [
        .package(path: "../../Tensor/TensorKit"),
        .package(path: "../../DetMath/DetMathKit"),
    ],
    targets: [
        .target(name: "PortalKit", dependencies: [
            .product(name: "TensorKit", package: "TensorKit"),
            .product(name: "DetMathKit", package: "DetMathKit"),
        ]),
        .testTarget(name: "PortalKitTests", dependencies: ["PortalKit"]),
    ]
)

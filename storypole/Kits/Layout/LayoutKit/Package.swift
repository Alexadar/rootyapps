// swift-tools-version: 5.9
import PackageDescription

// LayoutKit is the one Kit that takes a dependency. Marks must be EXACT feet-inch-fractions —
// a layout whose bays do not sum to the span is the defect this app exists to prevent — so it
// uses DimensionKit's `Rational`/`FeetInch` rather than forking the most correctness-critical
// type in the project.
let package = Package(
    name: "LayoutKit",
    platforms: [.macOS(.v13), .iOS(.v16), .watchOS(.v9)],
    products: [.library(name: "LayoutKit", targets: ["LayoutKit"])],
    dependencies: [.package(path: "../../Dimension/DimensionKit")],
    targets: [
        .target(name: "LayoutKit", dependencies: ["DimensionKit"]),
        .testTarget(name: "LayoutKitTests", dependencies: ["LayoutKit", "DimensionKit"]),
    ]
)

// swift-tools-version: 5.9
import PackageDescription

// Foundation only, on purpose. MeasureKit must NEVER import MusicUnderstanding: it is linked by the
// watch target too, and by builds on a released SDK where that framework does not exist. The
// framework-facing adapter lives in the app, behind #if canImport — see DESIGN_GUIDELINES §10.
let package = Package(
    name: "MeasureKit",
    platforms: [.macOS(.v13), .iOS(.v16), .watchOS(.v9)],
    products: [.library(name: "MeasureKit", targets: ["MeasureKit"])],
    targets: [
        .target(name: "MeasureKit"),
        .testTarget(name: "MeasureKitTests", dependencies: ["MeasureKit"]),
    ]
)

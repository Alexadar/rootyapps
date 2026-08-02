// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CelestialNavKit",
    platforms: [.macOS(.v13), .iOS(.v16), .watchOS(.v10)],
    products: [.library(name: "CelestialNavKit", targets: ["CelestialNavKit"])],
    targets: [
        .target(name: "CelestialNavKit"),
        .testTarget(name: "CelestialNavKitTests", dependencies: ["CelestialNavKit"]),
    ]
)

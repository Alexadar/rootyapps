// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DimensionKit",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [.library(name: "DimensionKit", targets: ["DimensionKit"])],
    targets: [
        .target(name: "DimensionKit"),
        .testTarget(name: "DimensionKitTests", dependencies: ["DimensionKit"]),
    ]
)

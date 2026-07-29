// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DimensionKit",
    platforms: [.macOS(.v13), .iOS(.v16), .watchOS(.v9)],
    products: [.library(name: "DimensionKit", targets: ["DimensionKit"])],
    targets: [
        .target(name: "DimensionKit"),
        .testTarget(name: "DimensionKitTests", dependencies: ["DimensionKit"]),
    ]
)

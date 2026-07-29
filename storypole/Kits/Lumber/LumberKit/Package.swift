// swift-tools-version: 5.9
import PackageDescription

// Depends on DimensionKit so dressed sizes are exact feet-inch values rather than decimals.
let package = Package(
    name: "LumberKit",
    platforms: [.macOS(.v13), .iOS(.v16), .watchOS(.v9)],
    products: [.library(name: "LumberKit", targets: ["LumberKit"])],
    dependencies: [.package(path: "../../Dimension/DimensionKit")],
    targets: [
        .target(name: "LumberKit", dependencies: ["DimensionKit"]),
        .testTarget(name: "LumberKitTests", dependencies: ["LumberKit", "DimensionKit"]),
    ]
)

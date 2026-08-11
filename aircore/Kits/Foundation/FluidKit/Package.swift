// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FluidKit",
    platforms: [.macOS(.v14), .iOS(.v17), .watchOS(.v10)],
    products: [.library(name: "FluidKit", targets: ["FluidKit"])],
    targets: [
        .target(name: "FluidKit"),
        .testTarget(name: "FluidKitTests", dependencies: ["FluidKit"]),
    ]
)

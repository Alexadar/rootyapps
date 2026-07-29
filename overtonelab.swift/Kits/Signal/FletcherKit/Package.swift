// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FletcherKit",
    platforms: [.macOS(.v13), .iOS(.v16), .watchOS(.v9)],
    products: [.library(name: "FletcherKit", targets: ["FletcherKit"])],
    targets: [
        .target(name: "FletcherKit"),
        .testTarget(name: "FletcherKitTests", dependencies: ["FletcherKit"]),
    ]
)

// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FanKit",
    platforms: [.macOS(.v14), .iOS(.v17), .watchOS(.v10)],
    products: [.library(name: "FanKit", targets: ["FanKit"])],
    targets: [
        .target(name: "FanKit"),
        .testTarget(name: "FanKitTests", dependencies: ["FanKit"]),
    ]
)

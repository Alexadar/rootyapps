// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HeatKit",
    platforms: [.macOS(.v14), .iOS(.v17), .watchOS(.v10)],
    products: [.library(name: "HeatKit", targets: ["HeatKit"])],
    targets: [
        .target(name: "HeatKit"),
        .testTarget(name: "HeatKitTests", dependencies: ["HeatKit"]),
    ]
)

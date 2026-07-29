// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GaugeKit",
    platforms: [.macOS(.v13), .iOS(.v16), .watchOS(.v9)],
    products: [.library(name: "GaugeKit", targets: ["GaugeKit"])],
    targets: [
        .target(name: "GaugeKit"),
        .testTarget(name: "GaugeKitTests", dependencies: ["GaugeKit"]),
    ]
)

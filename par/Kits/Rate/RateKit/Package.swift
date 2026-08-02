// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "RateKit",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [.library(name: "RateKit", targets: ["RateKit"])],
    targets: [
        .target(name: "RateKit"),
        .testTarget(name: "RateKitTests", dependencies: ["RateKit"]),
    ]
)

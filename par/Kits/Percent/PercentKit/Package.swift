// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PercentKit",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [.library(name: "PercentKit", targets: ["PercentKit"])],
    targets: [
        .target(name: "PercentKit"),
        .testTarget(name: "PercentKitTests", dependencies: ["PercentKit"]),
    ]
)

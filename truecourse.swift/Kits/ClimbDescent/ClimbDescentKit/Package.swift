// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClimbDescentKit",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [.library(name: "ClimbDescentKit", targets: ["ClimbDescentKit"])],
    targets: [
        .target(name: "ClimbDescentKit"),
        .testTarget(name: "ClimbDescentKitTests", dependencies: ["ClimbDescentKit"]),
    ]
)

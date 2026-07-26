// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DynamicsKit",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [.library(name: "DynamicsKit", targets: ["DynamicsKit"])],
    targets: [
        .target(name: "DynamicsKit"),
        .testTarget(name: "DynamicsKitTests", dependencies: ["DynamicsKit"]),
    ]
)

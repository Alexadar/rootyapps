// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TimeKit",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [.library(name: "TimeKit", targets: ["TimeKit"])],
    targets: [
        .target(name: "TimeKit"),
        .testTarget(name: "TimeKitTests", dependencies: ["TimeKit"]),
    ]
)

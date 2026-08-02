// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BernoulliKit",
    platforms: [.macOS(.v13), .iOS(.v16), .watchOS(.v9)],
    products: [.library(name: "BernoulliKit", targets: ["BernoulliKit"])],
    targets: [
        .target(name: "BernoulliKit"),
        .testTarget(name: "BernoulliKitTests", dependencies: ["BernoulliKit"]),
    ]
)

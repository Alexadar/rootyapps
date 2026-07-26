// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "FramingKit",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [.library(name: "FramingKit", targets: ["FramingKit"])],
    targets: [
        .target(name: "FramingKit"),
        .testTarget(name: "FramingKitTests", dependencies: ["FramingKit"]),
    ]
)

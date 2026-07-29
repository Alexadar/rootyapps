// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AudioUtilKit",
    platforms: [.iOS(.v16), .macOS(.v13), .watchOS(.v9)],
    products: [.library(name: "AudioUtilKit", targets: ["AudioUtilKit"])],
    targets: [
        .target(name: "AudioUtilKit"),
        .testTarget(name: "AudioUtilKitTests", dependencies: ["AudioUtilKit"]),
    ]
)

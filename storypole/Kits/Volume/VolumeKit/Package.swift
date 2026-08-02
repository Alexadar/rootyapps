// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VolumeKit",
    platforms: [.macOS(.v13), .iOS(.v16), .watchOS(.v9)],
    products: [.library(name: "VolumeKit", targets: ["VolumeKit"])],
    targets: [
        .target(name: "VolumeKit"),
        .testTarget(name: "VolumeKitTests", dependencies: ["VolumeKit"]),
    ]
)

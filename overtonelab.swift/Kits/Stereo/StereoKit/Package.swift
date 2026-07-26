// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "StereoKit",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [.library(name: "StereoKit", targets: ["StereoKit"])],
    targets: [
        .target(name: "StereoKit"),
        .testTarget(name: "StereoKitTests", dependencies: ["StereoKit"]),
    ]
)

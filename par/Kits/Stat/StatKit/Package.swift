// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "StatKit",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [.library(name: "StatKit", targets: ["StatKit"])],
    targets: [
        .target(name: "StatKit"),
        .testTarget(name: "StatKitTests", dependencies: ["StatKit"]),
    ]
)

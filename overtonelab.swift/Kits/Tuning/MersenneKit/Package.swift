// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MersenneKit",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [.library(name: "MersenneKit", targets: ["MersenneKit"])],
    targets: [
        .target(name: "MersenneKit"),
        .testTarget(name: "MersenneKitTests", dependencies: ["MersenneKit"]),
    ]
)

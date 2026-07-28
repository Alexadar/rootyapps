// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TidesKit",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [.library(name: "TidesKit", targets: ["TidesKit"])],
    targets: [
        .target(name: "TidesKit"),
        .testTarget(name: "TidesKitTests", dependencies: ["TidesKit"]),
    ]
)

// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WindKit",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [.library(name: "WindKit", targets: ["WindKit"])],
    targets: [
        .target(name: "WindKit"),
        .testTarget(name: "WindKitTests", dependencies: ["WindKit"]),
    ]
)

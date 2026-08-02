// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DepKit",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [.library(name: "DepKit", targets: ["DepKit"])],
    targets: [
        .target(name: "DepKit"),
        .testTarget(name: "DepKitTests", dependencies: ["DepKit"]),
    ]
)

// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NavKit",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [.library(name: "NavKit", targets: ["NavKit"])],
    targets: [
        .target(name: "NavKit"),
        .testTarget(name: "NavKitTests", dependencies: ["NavKit"]),
    ]
)

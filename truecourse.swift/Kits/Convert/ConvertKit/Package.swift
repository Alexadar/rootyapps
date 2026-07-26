// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ConvertKit",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [.library(name: "ConvertKit", targets: ["ConvertKit"])],
    targets: [
        .target(name: "ConvertKit"),
        .testTarget(name: "ConvertKitTests", dependencies: ["ConvertKit"]),
    ]
)

// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WebsterKit",
    platforms: [.macOS(.v13), .iOS(.v16), .watchOS(.v9)],
    products: [.library(name: "WebsterKit", targets: ["WebsterKit"])],
    targets: [
        .target(name: "WebsterKit"),
        .testTarget(name: "WebsterKitTests", dependencies: ["WebsterKit"]),
    ]
)

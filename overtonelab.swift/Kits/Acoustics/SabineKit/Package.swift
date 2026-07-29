// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SabineKit",
    platforms: [.macOS(.v13), .iOS(.v16), .watchOS(.v9)],
    products: [.library(name: "SabineKit", targets: ["SabineKit"])],
    targets: [
        .target(name: "SabineKit"),
        .testTarget(name: "SabineKitTests", dependencies: ["SabineKit"]),
    ]
)

// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PartchKit",
    platforms: [.macOS(.v13), .iOS(.v16), .watchOS(.v9)],
    products: [.library(name: "PartchKit", targets: ["PartchKit"])],
    targets: [
        .target(name: "PartchKit"),
        .testTarget(name: "PartchKitTests", dependencies: ["PartchKit"]),
    ]
)

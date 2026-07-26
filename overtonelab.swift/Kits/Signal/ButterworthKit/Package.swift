// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ButterworthKit",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [.library(name: "ButterworthKit", targets: ["ButterworthKit"])],
    targets: [
        .target(name: "ButterworthKit"),
        .testTarget(name: "ButterworthKitTests", dependencies: ["ButterworthKit"]),
    ]
)

// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AmortKit",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [.library(name: "AmortKit", targets: ["AmortKit"])],
    targets: [
        .target(name: "AmortKit"),
        .testTarget(name: "AmortKitTests", dependencies: ["AmortKit"]),
    ]
)

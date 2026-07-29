// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BiquadKit",
    platforms: [.macOS(.v13), .iOS(.v16), .watchOS(.v9)],
    products: [.library(name: "BiquadKit", targets: ["BiquadKit"])],
    targets: [
        .target(name: "BiquadKit"),
        .testTarget(name: "BiquadKitTests", dependencies: ["BiquadKit"]),
    ]
)

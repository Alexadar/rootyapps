// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SPLKit",
    platforms: [.iOS(.v16), .macOS(.v13), .watchOS(.v9)],
    products: [.library(name: "SPLKit", targets: ["SPLKit"])],
    targets: [
        .target(name: "SPLKit"),
        .testTarget(name: "SPLKitTests", dependencies: ["SPLKit"]),
    ]
)

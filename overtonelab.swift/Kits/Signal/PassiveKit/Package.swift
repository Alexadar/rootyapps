// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PassiveKit",
    platforms: [.iOS(.v16), .macOS(.v13), .watchOS(.v9)],
    products: [.library(name: "PassiveKit", targets: ["PassiveKit"])],
    targets: [
        .target(name: "PassiveKit"),
        .testTarget(name: "PassiveKitTests", dependencies: ["PassiveKit"]),
    ]
)

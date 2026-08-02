// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ProducerKit",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [.library(name: "ProducerKit", targets: ["ProducerKit"])],
    targets: [
        .target(name: "ProducerKit", resources: [.process("Resources")]),
        .testTarget(name: "ProducerKitTests", dependencies: ["ProducerKit"]),
    ]
)

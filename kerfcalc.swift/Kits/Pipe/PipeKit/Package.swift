// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PipeKit",
    platforms: [.iOS(.v16), .macOS(.v13), .watchOS(.v9)],
    products: [.library(name: "PipeKit", targets: ["PipeKit"])],
    targets: [
        .target(name: "PipeKit"),
        .testTarget(name: "PipeKitTests", dependencies: ["PipeKit"]),
    ]
)

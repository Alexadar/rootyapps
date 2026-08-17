// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Airside",
    platforms: [.iOS(.v16), .macOS(.v13), .watchOS(.v9)],
    products: [
        .library(name: "AirsideKit", targets: ["AirsideKit"]),
        .library(name: "AirsideUI", targets: ["AirsideUI"])
    ],
    targets: [
        .target(name: "AirsideKit"),
        .target(name: "AirsideUI", dependencies: ["AirsideKit"]),
        .testTarget(name: "AirsideKitTests", dependencies: ["AirsideKit"])
    ]
)

// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ThieleKit",
    platforms: [.iOS(.v16), .macOS(.v13), .watchOS(.v9)],
    products: [.library(name: "ThieleKit", targets: ["ThieleKit"])],
    targets: [
        .target(name: "ThieleKit"),
        .testTarget(name: "ThieleKitTests", dependencies: ["ThieleKit"]),
    ]
)

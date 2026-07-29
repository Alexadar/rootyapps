// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CommaKit",
    platforms: [.macOS(.v13), .iOS(.v16), .watchOS(.v9)],
    products: [.library(name: "CommaKit", targets: ["CommaKit"])],
    targets: [
        .target(name: "CommaKit"),
        .testTarget(name: "CommaKitTests", dependencies: ["CommaKit"]),
    ]
)

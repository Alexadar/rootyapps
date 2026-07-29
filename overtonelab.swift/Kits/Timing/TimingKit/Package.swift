// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TimingKit",
    platforms: [.iOS(.v16), .macOS(.v13), .watchOS(.v9)],
    products: [.library(name: "TimingKit", targets: ["TimingKit"])],
    targets: [
        .target(name: "TimingKit"),
        .testTarget(name: "TimingKitTests", dependencies: ["TimingKit"]),
    ]
)

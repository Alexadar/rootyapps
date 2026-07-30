// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WeightBalanceKit",
    platforms: [.macOS(.v13), .iOS(.v16), .watchOS(.v10)],
    products: [.library(name: "WeightBalanceKit", targets: ["WeightBalanceKit"])],
    targets: [
        .target(name: "WeightBalanceKit"),
        .testTarget(name: "WeightBalanceKitTests", dependencies: ["WeightBalanceKit"]),
    ]
)

// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CashFlowKit",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [.library(name: "CashFlowKit", targets: ["CashFlowKit"])],
    targets: [
        .target(name: "CashFlowKit"),
        .testTarget(name: "CashFlowKitTests", dependencies: ["CashFlowKit"]),
    ]
)

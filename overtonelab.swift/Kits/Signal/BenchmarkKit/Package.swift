// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BenchmarkKit",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [.library(name: "BenchmarkKit", targets: ["BenchmarkKit"])],
    targets: [
        .target(name: "BenchmarkKit"),
        .testTarget(name: "BenchmarkKitTests", dependencies: ["BenchmarkKit"]),
    ]
)

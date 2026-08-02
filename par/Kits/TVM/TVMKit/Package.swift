// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TVMKit",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [.library(name: "TVMKit", targets: ["TVMKit"])],
    targets: [
        .target(name: "TVMKit"),
        .testTarget(name: "TVMKitTests", dependencies: ["TVMKit"]),
    ]
)

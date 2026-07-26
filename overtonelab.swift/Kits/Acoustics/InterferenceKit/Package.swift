// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "InterferenceKit",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [.library(name: "InterferenceKit", targets: ["InterferenceKit"])],
    targets: [
        .target(name: "InterferenceKit"),
        .testTarget(name: "InterferenceKitTests", dependencies: ["InterferenceKit"]),
    ]
)

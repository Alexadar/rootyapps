// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PitchKit",
    platforms: [.iOS(.v16), .macOS(.v13), .watchOS(.v9)],
    products: [.library(name: "PitchKit", targets: ["PitchKit"])],
    targets: [
        .target(name: "PitchKit"),
        .testTarget(name: "PitchKitTests", dependencies: ["PitchKit"]),
    ]
)

// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AltitudeKit",
    platforms: [.macOS(.v14), .iOS(.v17), .watchOS(.v10)],
    products: [.library(name: "AltitudeKit", targets: ["AltitudeKit"])],
    targets: [
        .target(name: "AltitudeKit"),
        .testTarget(name: "AltitudeKitTests", dependencies: ["AltitudeKit"]),
    ]
)

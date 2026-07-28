// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "GeodesyKit",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [.library(name: "GeodesyKit", targets: ["GeodesyKit"])],
    targets: [
        .target(name: "GeodesyKit"),
        .testTarget(name: "GeodesyKitTests", dependencies: ["GeodesyKit"]),
    ]
)

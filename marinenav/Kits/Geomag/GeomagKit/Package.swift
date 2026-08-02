// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "GeomagKit",
    platforms: [.macOS(.v13), .iOS(.v16), .watchOS(.v10)],
    products: [.library(name: "GeomagKit", targets: ["GeomagKit"])],
    targets: [
        .target(name: "GeomagKit"),
        .testTarget(name: "GeomagKitTests", dependencies: ["GeomagKit"]),
    ]
)

// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AirspeedKit",
    platforms: [.macOS(.v13), .iOS(.v16), .watchOS(.v10)],
    products: [.library(name: "AirspeedKit", targets: ["AirspeedKit"])],
    targets: [
        .target(name: "AirspeedKit"),
        .testTarget(name: "AirspeedKitTests", dependencies: ["AirspeedKit"]),
    ]
)

// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FuelKit",
    platforms: [.macOS(.v13), .iOS(.v16), .watchOS(.v10)],
    products: [.library(name: "FuelKit", targets: ["FuelKit"])],
    targets: [
        .target(name: "FuelKit"),
        .testTarget(name: "FuelKitTests", dependencies: ["FuelKit"]),
    ]
)

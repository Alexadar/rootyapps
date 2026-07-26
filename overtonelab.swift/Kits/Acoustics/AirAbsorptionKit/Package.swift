// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AirAbsorptionKit",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [.library(name: "AirAbsorptionKit", targets: ["AirAbsorptionKit"])],
    targets: [
        .target(name: "AirAbsorptionKit"),
        .testTarget(name: "AirAbsorptionKitTests", dependencies: ["AirAbsorptionKit"]),
    ]
)

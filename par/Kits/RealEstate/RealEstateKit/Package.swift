// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "RealEstateKit",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [.library(name: "RealEstateKit", targets: ["RealEstateKit"])],
    targets: [
        .target(name: "RealEstateKit"),
        .testTarget(name: "RealEstateKitTests", dependencies: ["RealEstateKit"]),
    ]
)

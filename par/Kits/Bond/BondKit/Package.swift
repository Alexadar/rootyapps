// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BondKit",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [.library(name: "BondKit", targets: ["BondKit"])],
    targets: [
        .target(name: "BondKit"),
        .testTarget(name: "BondKitTests", dependencies: ["BondKit"]),
    ]
)

// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "UnitsKit",
    platforms: [.macOS(.v14), .iOS(.v17), .watchOS(.v10)],
    products: [.library(name: "UnitsKit", targets: ["UnitsKit"])],
    targets: [
        .target(name: "UnitsKit"),
        .testTarget(name: "UnitsKitTests", dependencies: ["UnitsKit"]),
    ]
)

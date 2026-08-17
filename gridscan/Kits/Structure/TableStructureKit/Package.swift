// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TableStructureKit",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [.library(name: "TableStructureKit", targets: ["TableStructureKit"])],
    targets: [
        .target(name: "TableStructureKit"),
        .testTarget(name: "TableStructureKitTests", dependencies: ["TableStructureKit"]),
    ]
)

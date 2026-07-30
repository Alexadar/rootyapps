// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MaterialsKit",
    platforms: [.iOS(.v16), .macOS(.v13), .watchOS(.v9)],
    products: [.library(name: "MaterialsKit", targets: ["MaterialsKit"])],
    targets: [
        .target(name: "MaterialsKit"),
        .testTarget(name: "MaterialsKitTests", dependencies: ["MaterialsKit"]),
    ]
)

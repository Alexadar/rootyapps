// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GeometryKit",
    platforms: [.macOS(.v13), .iOS(.v16), .watchOS(.v9)],
    products: [.library(name: "GeometryKit", targets: ["GeometryKit"])],
    targets: [
        .target(name: "GeometryKit"),
        .testTarget(name: "GeometryKitTests", dependencies: ["GeometryKit"]),
    ]
)

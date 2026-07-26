// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "GeometryKit",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [.library(name: "GeometryKit", targets: ["GeometryKit"])],
    targets: [
        .target(name: "GeometryKit"),
        .testTarget(name: "GeometryKitTests", dependencies: ["GeometryKit"]),
    ]
)

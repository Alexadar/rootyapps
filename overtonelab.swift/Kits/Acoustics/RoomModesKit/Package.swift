// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RoomModesKit",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [.library(name: "RoomModesKit", targets: ["RoomModesKit"])],
    targets: [
        .target(name: "RoomModesKit"),
        .testTarget(name: "RoomModesKitTests", dependencies: ["RoomModesKit"]),
    ]
)

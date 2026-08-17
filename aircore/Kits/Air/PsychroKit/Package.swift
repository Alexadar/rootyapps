// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PsychroKit",
    platforms: [.macOS(.v14), .iOS(.v17), .watchOS(.v10)],
    products: [.library(name: "PsychroKit", targets: ["PsychroKit"])],
    targets: [
        .target(name: "PsychroKit"),
        .testTarget(name: "PsychroKitTests", dependencies: ["PsychroKit"]),
    ]
)

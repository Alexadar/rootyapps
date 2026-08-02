// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DayCountKit",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [.library(name: "DayCountKit", targets: ["DayCountKit"])],
    targets: [
        .target(name: "DayCountKit"),
        .testTarget(name: "DayCountKitTests", dependencies: ["DayCountKit"]),
    ]
)

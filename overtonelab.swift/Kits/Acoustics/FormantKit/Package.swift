// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "FormantKit",
    platforms: [.iOS(.v16), .macOS(.v13), .watchOS(.v9)],
    products: [.library(name: "FormantKit", targets: ["FormantKit"])],
    targets: [
        .target(name: "FormantKit"),
        .testTarget(name: "FormantKitTests", dependencies: ["FormantKit"]),
    ]
)

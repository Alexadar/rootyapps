// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ConcreteKit",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [.library(name: "ConcreteKit", targets: ["ConcreteKit"])],
    targets: [
        .target(name: "ConcreteKit"),
        .testTarget(name: "ConcreteKitTests", dependencies: ["ConcreteKit"]),
    ]
)

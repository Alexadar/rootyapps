// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DocumentModelKit",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [.library(name: "DocumentModelKit", targets: ["DocumentModelKit"])],
    targets: [
        .target(name: "DocumentModelKit"),
        .testTarget(name: "DocumentModelKitTests", dependencies: ["DocumentModelKit"]),
    ]
)

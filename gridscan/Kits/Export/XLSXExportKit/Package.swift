// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "XLSXExportKit",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [.library(name: "XLSXExportKit", targets: ["XLSXExportKit"])],
    targets: [
        .target(name: "XLSXExportKit"),
        .testTarget(name: "XLSXExportKitTests", dependencies: ["XLSXExportKit"]),
    ]
)

// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CSVExportKit",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [.library(name: "CSVExportKit", targets: ["CSVExportKit"])],
    targets: [
        .target(name: "CSVExportKit"),
        .testTarget(name: "CSVExportKitTests", dependencies: ["CSVExportKit"]),
    ]
)

// swift-tools-version: 5.9
import PackageDescription

// Every number the user reads. Byte counts, transfer rates, ETAs and step counts — the things that
// look trivial and are wrong in half the apps that show them. Foundation only.
let package = Package(
    name: "FormatKit",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "FormatKit", targets: ["FormatKit"])],
    targets: [
        .target(name: "FormatKit"),
        .testTarget(name: "FormatKitTests", dependencies: ["FormatKit"]),
    ]
)

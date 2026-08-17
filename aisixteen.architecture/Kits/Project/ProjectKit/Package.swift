// swift-tools-version: 6.0
import PackageDescription

// What a project IS on disk: the folder layout, the sidecars, and a store that works over any
// injected root. That last part is the whole point — "iCloud available" and "iCloud unavailable"
// become the same code over two different URLs, which is the only reason a user with iCloud
// switched off exercises tested paths.
let package = Package(
    name: "ProjectKit",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [.library(name: "ProjectKit", targets: ["ProjectKit"])],
    targets: [
        .target(name: "ProjectKit", swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(name: "ProjectKitTests", dependencies: ["ProjectKit"], swiftSettings: [.swiftLanguageMode(.v6)]),
    ]
)

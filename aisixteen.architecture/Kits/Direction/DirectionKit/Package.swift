// swift-tools-version: 6.0
import PackageDescription

// Style presets and prompt composition. Swatches are stored as hex integers rather than `Color`
// so this package stays Foundation-only; the app maps hex to Color in exactly one place.
let package = Package(
    name: "DirectionKit",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [.library(name: "DirectionKit", targets: ["DirectionKit"])],
    targets: [
        .target(name: "DirectionKit", swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(name: "DirectionKitTests", dependencies: ["DirectionKit"], swiftSettings: [.swiftLanguageMode(.v6)]),
    ]
)

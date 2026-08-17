// swift-tools-version: 6.0
import PackageDescription

// Every user-facing number in the app. Pure, locale-aware, and pinned against a fixed clock in
// tests — because "about 1 min left" printed for fifteen seconds remaining is the kind of small
// lie this app's whole design is trying not to tell.
let package = Package(
    name: "FormatKit",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [.library(name: "FormatKit", targets: ["FormatKit"])],
    targets: [
        .target(name: "FormatKit", swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(name: "FormatKitTests", dependencies: ["FormatKit"], swiftSettings: [.swiftLanguageMode(.v6)]),
    ]
)

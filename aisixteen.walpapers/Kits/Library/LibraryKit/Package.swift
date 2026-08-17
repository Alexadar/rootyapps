// swift-tools-version: 5.9
import PackageDescription

// What a saved wallpaper is, where it lives and how it is named. Foundation only — the same code
// runs against the iCloud ubiquity container and against the local fallback folder, which is the
// point: a user with iCloud switched off exercises tested paths, not an untested branch.
let package = Package(
    name: "LibraryKit",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "LibraryKit", targets: ["LibraryKit"])],
    dependencies: [.package(path: "../../Generation/GenerationKit")],
    targets: [
        .target(name: "LibraryKit", dependencies: ["GenerationKit"]),
        .testTarget(name: "LibraryKitTests", dependencies: ["LibraryKit"]),
    ]
)

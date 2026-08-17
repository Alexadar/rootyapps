// swift-tools-version: 5.9
import PackageDescription

// Where an edit lives on disk, and the guarantee that the file the user started with is never
// written to again. Foundation and CryptoKit only — the same code runs against the iCloud ubiquity
// container and against the local fallback folder, which is the point: a user with iCloud switched
// off exercises tested paths, not an untested branch.
let package = Package(
    name: "EditsKit",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "EditsKit", targets: ["EditsKit"])],
    dependencies: [.package(path: "../../Recipe/RecipeKit")],
    targets: [
        .target(name: "EditsKit", dependencies: ["RecipeKit"]),
        .testTarget(name: "EditsKitTests", dependencies: ["EditsKit"]),
    ]
)

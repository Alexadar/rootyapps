// swift-tools-version: 5.9
import PackageDescription

// What an edit *is*: which areas it touches, how strongly, and what the screen should show for a
// given dial position. Foundation only — no CoreGraphics, no SwiftUI — so the whole state space
// (four detents, four scopes, composition, the blend rule, the comparison handle) is proved by
// `swift test` in milliseconds, on any machine, without a simulator.
//
// The one invariant this package exists to protect: **strength 0 is the original, not a blend at
// alpha 0.** See `Composite`.
let package = Package(
    name: "RecipeKit",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "RecipeKit", targets: ["RecipeKit"])],
    targets: [
        .target(name: "RecipeKit"),
        .testTarget(name: "RecipeKitTests", dependencies: ["RecipeKit"]),
    ]
)

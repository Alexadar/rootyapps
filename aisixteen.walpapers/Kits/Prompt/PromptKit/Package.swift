// swift-tools-version: 5.9
import PackageDescription

// *Surprise me* — the control that decides whether a first-time user ever gets a good result.
// Foundation only, and no random number generator of its own: the caller supplies one, so the
// same seed always produces the same suggestion.
let package = Package(
    name: "PromptKit",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "PromptKit", targets: ["PromptKit"])],
    targets: [
        .target(name: "PromptKit", resources: [.process("Resources")]),
        .testTarget(name: "PromptKitTests", dependencies: ["PromptKit"]),
    ]
)

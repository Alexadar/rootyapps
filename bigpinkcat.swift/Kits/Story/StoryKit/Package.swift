// swift-tools-version: 5.9
import PackageDescription

// StoryKit — the loader that has never worked, rewritten against the content that actually exists.
//
// The 2025 build shipped three independent mismatches between `GameDataLoader.swift` and
// `output_story/`, any one of which was fatal:
//
//   1. it enumerated `output_story/summary_parts/`, a folder that exists only in the 2024 Unity
//      project and was never copied into the Swift bundle;
//   2. it asked for `dialog_<Int>` while the content is a tree — `dialog_1_1_1`;
//   3. it decoded a flat `[Dialog]` while the YAML is `[- guidelines:, - story_dialogs:]`, with
//      `final_words` as a MAP where the model expected a scalar.
//
// Net effect: `getInitialDialog()` returned nil, `showMainMenu()`'s guard failed, and the app booted
// to "An error occurred". That is the actual reason it was unshippable, and it is not what the
// rejection was about.
//
// Yams is the one external dependency in this repo's Kits, and it earns it: the dialogue text
// contains colons, apostrophes and quoted strings, so a hand-rolled subset parser would be a
// silent-corruption risk rather than a saving.
let package = Package(
    name: "StoryKit",
    platforms: [.macOS(.v13), .iOS(.v16), .tvOS(.v16), .watchOS(.v9), .visionOS(.v1)],
    products: [
        .library(name: "StoryKit", targets: ["StoryKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0"),
    ],
    targets: [
        .target(name: "StoryKit", dependencies: [.product(name: "Yams", package: "Yams")]),
        .testTarget(name: "StoryKitTests", dependencies: ["StoryKit"]),
    ]
)

// swift-tools-version: 5.9
import PackageDescription

// The on-device generation base, shared across apps.
//
// `aisixteen.models` already held the *conversion* half of this — the Python that turns a checkpoint
// into Core ML models and writes the `model.json` that declares what they are. This is the runtime
// half that reads them. Keeping the two in one place is the point: an id written by the converter
// and an id compared by a resumed job are the same string, and a rename that breaks one silently
// breaks the other.
//
// Deliberately **not** an image-generation library. It knows nothing about diffusion, ESRGAN or
// wallpapers. It answers two questions that every on-device generation app has to answer and that
// took this project several device reboots to get right:
//
//   * `ModelKit` — *which model is this, and can this device run it?*
//   * `TaskKit`  — *what was this job doing when it stopped, and may that work be reused?*
let package = Package(
    name: "AISixteenModels",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "ModelKit", targets: ["ModelKit"]),
        .library(name: "TaskKit", targets: ["TaskKit"]),
        .library(name: "DiffusionKit", targets: ["DiffusionKit"]),
        .library(name: "DiffusionRuntime", targets: ["DiffusionRuntime"]),
    ],
    dependencies: [
        // Only the SD3 / SDXL paths need it, and only for their tokenizers. Pinned exactly, as in
        // the app that vendored this first.
        .package(url: "https://github.com/huggingface/swift-transformers.git", exact: "0.1.8"),
    ],
    targets: [
        // Foundation only. Identity, fingerprints and output sizes — no model is loaded, nothing is
        // rendered, so every rule here is testable in milliseconds.
        .target(name: "ModelKit"),
        // Adds CoreGraphics and CoreML: durable job state, the tile ledger and the checkpoint codec.
        // Still no model and no UI framework.
        .target(name: "TaskKit", dependencies: ["ModelKit"]),
        // Apple's ml-stable-diffusion, vendored (MIT — see APPLE-LICENSE.md), with four changes,
        // all of them additive or visibility-only so upstream fixes can still be re-applied by
        // re-copying and re-widening: `predictNoise`/`prewarmResources` made public, zero-residual
        // support so ONE controlled unet serves both plain and ControlNet runs, `ResumePoint` for
        // restarting a de-noising loop, and `retainsDenoisingModels` + autorelease pools in the
        // step loop, which together took a nine-tile refine from 372 s to 42 s.
        .target(name: "DiffusionKit",
                dependencies: [.product(name: "Transformers", package: "swift-transformers")]),

        // The part every app on this model shares: loading the pack component by component,
        // generating, and driving a tiled ControlNet pass. What differs between apps is *which*
        // ControlNet they attach and what they do with the result — not any of this.
        .target(name: "DiffusionRuntime", dependencies: ["DiffusionKit", "ModelKit", "TaskKit"]),

        .testTarget(name: "DiffusionRuntimeTests", dependencies: ["DiffusionRuntime"]),
        .testTarget(name: "ModelKitTests", dependencies: ["ModelKit"]),
        .testTarget(name: "TaskKitTests", dependencies: ["TaskKit"]),
    ]
)

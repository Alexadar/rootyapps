// swift-tools-version: 5.9
import PackageDescription

// **The seam.** Everything in the app talks to `PhotoEnhancer`; nothing talks to a model. When the
// on-device diffusion pipeline lands (see ../../../aisixteen.models/) it is added behind this
// protocol and no view changes.
//
// Foundation and CoreGraphics only. CoreGraphics is here because the seam is typed in `CGImage` —
// a value layer, not a UI framework — so `swift test` still runs the whole schedule in
// milliseconds without a simulator. No SwiftUI, no UIKit, no AppKit, no Core ML.
let package = Package(
    name: "EnhanceKit",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "EnhanceKit", targets: ["EnhanceKit"])],
    targets: [
        .target(name: "EnhanceKit"),
        .testTarget(name: "EnhanceKitTests", dependencies: ["EnhanceKit"]),
    ]
)

// swift-tools-version: 5.9
import PackageDescription

// The seam between "something made an image" and the rest of the app. Foundation only: no
// SwiftUI, no CoreGraphics, no CoreML. The real diffusion pipeline links this package and conforms
// to `ImageGenerator`; nothing above it has to change when it does.
//
// Sits on `ModelKit`, the shared base in `aisixteen.models`. Output sizes and model identity are not
// facts about *this* app — they are facts about running a converted model on a device, and the
// converter that produces those models lives in the same place.
let package = Package(
    name: "GenerationKit",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "GenerationKit", targets: ["GenerationKit"])],
    dependencies: [.package(path: "../../../../aisixteen.models/swift/AISixteenModels")],
    targets: [
        .target(name: "GenerationKit", dependencies: [.product(name: "ModelKit", package: "AISixteenModels")]),
        .testTarget(name: "GenerationKitTests", dependencies: ["GenerationKit"]),
    ]
)

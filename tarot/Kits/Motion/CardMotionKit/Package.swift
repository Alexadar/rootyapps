// swift-tools-version: 5.9
import PackageDescription

// CardMotionKit — every piece of card-feel mathematics, as a loop-less batched program.
//
// The state carries a leading [N] world axis: N = 1 is the live game, N = 4096 is the test
// harness. Same arrays, same kernel — the architecture citypigeon/froggo2/bigpinkcat proved.
// Foundation only, deliberately not MLX: the batch here exists for *testing*, not throughput,
// and Foundation `Double` runs in `swift test`, in the iOS Simulator, and everywhere else
// MLX cannot go.
let package = Package(
    name: "CardMotionKit",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [
        .library(name: "CardMotionKit", targets: ["CardMotionKit"])
    ],
    targets: [
        .target(name: "CardMotionKit"),
        .testTarget(name: "CardMotionKitTests", dependencies: ["CardMotionKit"]),
    ]
)

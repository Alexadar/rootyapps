// swift-tools-version: 6.0
import PackageDescription

// Foundation only. No SwiftUI, no CoreGraphics, no AVFoundation, no ActivityKit — that is what
// lets `swift test` run the whole job state space in milliseconds, and what will let the real
// depth-conditioned Core ML pipeline link this package without dragging in a UI.
//
// The platform floor is LOWER than the app's (26.0) on purpose: nothing here needs Liquid Glass,
// and a low floor keeps `swift test` off the SDK-26 toolchain constraint. It is not lower still
// because the mocks guard their cancellation flag with `Synchronization.Mutex`, which lands in
// macOS 15 / iOS 18 — `NSLock` is unavailable from async contexts and is an error under Swift 6.
let package = Package(
    name: "RedesignKit",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [.library(name: "RedesignKit", targets: ["RedesignKit"])],
    targets: [
        .target(name: "RedesignKit", swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(name: "RedesignKitTests", dependencies: ["RedesignKit"], swiftSettings: [.swiftLanguageMode(.v6)]),
    ]
)

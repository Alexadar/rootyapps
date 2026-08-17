// swift-tools-version: 5.9
import PackageDescription

// TarotKit — the deck as data, and the shuffle as a provable algorithm.
//
// Foundation-only, no UI, no network. Pinned to old platform minimums (unlike the app's 26.0)
// so any future companion — a widget, a watch app — can consume it unchanged.
let package = Package(
    name: "TarotKit",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [
        .library(name: "TarotKit", targets: ["TarotKit"])
    ],
    targets: [
        .target(name: "TarotKit"),
        .testTarget(name: "TarotKitTests", dependencies: ["TarotKit"]),
    ]
)

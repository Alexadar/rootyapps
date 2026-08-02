// swift-tools-version: 5.9
import PackageDescription

// SpaceWeatherKit — the oracle-first trust moat.
//
// Six Foundation-only libraries. No UIKit, no network. Live data enters as raw
// numbers; every classification the app displays is computed here and asserted
// against a cited published definition in the matching *KitTests oracle suite.
// Ship no number these Kits can't validate. `swift test` runs every oracle suite.
let package = Package(
    name: "SpaceWeatherKit",
    platforms: [.macOS(.v13), .iOS(.v16), .watchOS(.v10)],
    products: [
        .library(name: "SpaceWeatherFeed", targets: ["SpaceWeatherFeed"]),
        .library(name: "GeomagKit", targets: ["GeomagKit"]),
        .library(name: "FlareKit", targets: ["FlareKit"]),
        .library(name: "SolarWindKit", targets: ["SolarWindKit"]),
        .library(name: "AuroraKit", targets: ["AuroraKit"]),
        .library(name: "HpoKit", targets: ["HpoKit"]),
        .library(name: "SolarIndexKit", targets: ["SolarIndexKit"]),
    ],
    targets: [
        .target(name: "GeomagKit"),
        .testTarget(name: "GeomagKitTests", dependencies: ["GeomagKit"]),

        .target(name: "FlareKit"),
        .testTarget(name: "FlareKitTests", dependencies: ["FlareKit"]),

        .target(name: "SolarWindKit"),
        .testTarget(name: "SolarWindKitTests", dependencies: ["SolarWindKit"]),

        .target(name: "AuroraKit"),
        .testTarget(name: "AuroraKitTests", dependencies: ["AuroraKit"]),

        .target(name: "HpoKit", dependencies: ["GeomagKit"]),
        .testTarget(name: "HpoKitTests", dependencies: ["HpoKit"]),

        .target(name: "SolarIndexKit"),
        .testTarget(name: "SolarIndexKitTests", dependencies: ["SolarIndexKit"]),

        // Feed — the shared fetch/classify/persist layer used by app, widgets, and watch.
        // Unlike the six oracle Kits it talks to the network and the app-group store;
        // classification still happens only through the Kits.
        .target(name: "SpaceWeatherFeed",
                dependencies: ["GeomagKit", "FlareKit", "SolarWindKit", "AuroraKit", "HpoKit", "SolarIndexKit"]),
        .testTarget(name: "SpaceWeatherFeedTests", dependencies: ["SpaceWeatherFeed"],
                    resources: [.process("Fixtures")]),
    ]
)

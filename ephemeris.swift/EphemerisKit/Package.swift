// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "EphemerisKit",
    // watchOS is listed so the watch app and its complications can link the same engine.
    // The Kit is pure Swift with no UIKit/AppKit/CoreMotion, so it ports unchanged.
    platforms: [.macOS(.v13), .iOS(.v16), .watchOS(.v10)],
    products: [
        .library(name: "EphemerisKit", targets: ["EphemerisKit"]),
        .executable(name: "ephemeris-export", targets: ["ephemeris-export"]),
    ],
    targets: [
        .target(name: "EphemerisKit"),
        .executableTarget(name: "ephemeris-export", dependencies: ["EphemerisKit"]),
        .testTarget(name: "EphemerisKitTests", dependencies: ["EphemerisKit"]),
    ]
)

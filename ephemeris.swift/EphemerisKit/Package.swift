// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "EphemerisKit",
    platforms: [.macOS(.v13), .iOS(.v16)],
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

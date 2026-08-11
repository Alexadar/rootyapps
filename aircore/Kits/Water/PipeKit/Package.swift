// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PipeKit",
    platforms: [.macOS(.v14), .iOS(.v17), .watchOS(.v10)],
    products: [.library(name: "PipeKit", targets: ["PipeKit"])],
    // Shares Colebrook–White and Darcy–Weisbach with the duct side. See FluidKit's discussion.
    dependencies: [.package(path: "../../Foundation/FluidKit")],
    targets: [
        .target(name: "PipeKit", dependencies: [.product(name: "FluidKit", package: "FluidKit")]),
        .testTarget(name: "PipeKitTests", dependencies: ["PipeKit"]),
    ]
)

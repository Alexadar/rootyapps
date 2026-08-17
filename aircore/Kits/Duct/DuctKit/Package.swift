// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DuctKit",
    platforms: [.macOS(.v14), .iOS(.v17), .watchOS(.v10)],
    products: [.library(name: "DuctKit", targets: ["DuctKit"])],
    // The one cross-Kit dependency in this app: Colebrook–White and Darcy–Weisbach are the same
    // equations for air in a duct and water in a pipe, and two copies of an implicit numerical
    // solve would drift apart. See FluidKit's discussion.
    dependencies: [.package(path: "../../Foundation/FluidKit")],
    targets: [
        .target(name: "DuctKit", dependencies: [.product(name: "FluidKit", package: "FluidKit")]),
        .testTarget(name: "DuctKitTests", dependencies: ["DuctKit"]),
    ]
)

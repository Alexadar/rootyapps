// swift-tools-version:5.9
import PackageDescription

// NOT a Kit. This package ships nothing: it exists so the *combinations* of Kits can be tested, which
// no individual Kit can do — Kits take no dependencies on each other by design (PLAN.md §4), so a chain
// like "dates → day count → bond price" has no home inside either Kit. Every published end-to-end value
// in the project is asserted here.
let package = Package(
    name: "ChainTests",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [.library(name: "ChainSupport", targets: ["ChainSupport"])],
    dependencies: [
        .package(path: "../../Kits/DayCount/DayCountKit"),
        .package(path: "../../Kits/TVM/TVMKit"),
        .package(path: "../../Kits/Amort/AmortKit"),
        .package(path: "../../Kits/CashFlow/CashFlowKit"),
        .package(path: "../../Kits/Rate/RateKit"),
        .package(path: "../../Kits/Bond/BondKit"),
        .package(path: "../../Kits/Depreciation/DepKit"),
        .package(path: "../../Kits/Percent/PercentKit"),
        .package(path: "../../Kits/Stat/StatKit"),
        .package(path: "../../Kits/RealEstate/RealEstateKit"),
    ],
    targets: [
        .target(name: "ChainSupport"),
        .testTarget(
            name: "ChainTests",
            dependencies: [
                "ChainSupport",
                .product(name: "DayCountKit", package: "DayCountKit"),
                .product(name: "TVMKit", package: "TVMKit"),
                .product(name: "AmortKit", package: "AmortKit"),
                .product(name: "CashFlowKit", package: "CashFlowKit"),
                .product(name: "RateKit", package: "RateKit"),
                .product(name: "BondKit", package: "BondKit"),
                .product(name: "DepKit", package: "DepKit"),
                .product(name: "PercentKit", package: "PercentKit"),
                .product(name: "StatKit", package: "StatKit"),
                .product(name: "RealEstateKit", package: "RealEstateKit"),
            ]
        ),
    ]
)

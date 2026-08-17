// swift-tools-version: 5.9
import PackageDescription

// DetMathKit — the determinism floor.
//
// Foundation only, and it never calls a libm transcendental. That is the entire point of the
// package existing separately from TensorKit.
//
// Verified on this toolchain (arm64, Xcode 26.5 SDK) rather than assumed:
//
//   * Swift does NOT contract `a*b + c` into `fmadd`, even at -Ounchecked — it emits separate
//     `fmul` and `fadd`. The single worst determinism hazard in C and C++ does not exist here,
//     because Swift is IEEE-754 strict and has no fast-math switch.
//   * `Double.squareRoot()` lowers to the hardware `fsqrt` instruction, which IEEE-754 specifies
//     as correctly rounded. It is therefore bit-identical on every conforming target and is safe
//     to call directly.
//   * `simd_fast_normalize` / `simd_fast_recip` / `simd_fast_rsqrt` exist in the SDK beside their
//     `simd_precise_*` counterparts. They are approximate by construction and are on the ban list.
//
// The one real hole is transcendentals: IEEE-754 mandates correct rounding for + - * / and sqrt,
// but NOT for sin, cos, exp, log or pow. libm implementations legitimately differ in the last ulp
// across OS versions and architectures. So this package ships its own, with fixed coefficients, and
// they are bit-identical forever and immune to an OS update. That is standard practice in lockstep
// and rollback netcode — not research.
let package = Package(
    name: "DetMathKit",
    platforms: [.macOS(.v13), .iOS(.v16), .tvOS(.v16), .watchOS(.v9), .visionOS(.v1)],
    products: [
        .library(name: "DetMathKit", targets: ["DetMathKit"]),
    ],
    targets: [
        .target(name: "DetMathKit"),
        .testTarget(name: "DetMathKitTests", dependencies: ["DetMathKit"]),
    ]
)

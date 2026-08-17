import XCTest
@testable import DetMathKit

/// ORACLES for this suite:
///
///   * **Oracle-backed** — the system libm (`Foundation.sin` / `cos` / `atan` / `atan2`), used as an
///     *independent implementation* per `docs/calculators_VALIDATION.md`: "a second independent
///     implementation" is an accepted oracle. We are allowed to compare against it for *accuracy*
///     even though we may not depend on it for *determinism*, which is the whole reason DetMath
///     exists. The two concerns are separate and this suite keeps them separate.
///   * **Identity** — Pythagorean identity, parity, periodicity; definitions cross-checked
///     numerically.
///   * **Invariant** — range and monotonicity bounds.
final class DetMathTests: XCTestCase {

    /// A few ulp at double precision. Every physical tolerance in this game is many orders looser.
    private let ulpTolerance = 8.0

    private func assertCloseInUlps(_ got: Double, _ want: Double,
                                   _ label: String, ulps: Double? = nil,
                                   file: StaticString = #filePath, line: UInt = #line) {
        let tol = (ulps ?? ulpTolerance) * Swift.max(want.ulp, Double.leastNormalMagnitude)
        XCTAssertEqual(got, want, accuracy: tol, label, file: file, line: line)
    }

    // MARK: - Oracle-backed: agreement with an independent implementation

    func testSinAgreesWithLibmAcrossFourPeriods() {
        // 4001 samples over [-4π, 4π] — exercises all four quadrants of the reduction, both signs.
        let n = 4001
        var worstUlps = 0.0
        for i in 0..<n {
            let x = -4 * Double.pi + (8 * Double.pi) * Double(i) / Double(n - 1)
            let got = DetMath.sin(x)
            let want = Foundation.sin(x)
            let ulps = abs(got - want) / Swift.max(want.ulp, Double.leastNormalMagnitude)
            worstUlps = Swift.max(worstUlps, ulps)
        }
        XCTAssertLessThan(worstUlps, 1e9,
                          "sin is wildly wrong, not merely imprecise (worst \(worstUlps) ulp)")
        // Absolute agreement is the meaningful bound near zeros, where relative ulp explodes.
        for i in 0..<n {
            let x = -4 * Double.pi + (8 * Double.pi) * Double(i) / Double(n - 1)
            XCTAssertEqual(DetMath.sin(x), Foundation.sin(x), accuracy: 1e-15, "sin(\(x))")
        }
    }

    func testCosAgreesWithLibmAcrossFourPeriods() {
        let n = 4001
        for i in 0..<n {
            let x = -4 * Double.pi + (8 * Double.pi) * Double(i) / Double(n - 1)
            XCTAssertEqual(DetMath.cos(x), Foundation.cos(x), accuracy: 1e-15, "cos(\(x))")
        }
    }

    func testSinCosAgreeFarFromOrigin() {
        // Range reduction is where a naive implementation falls apart. Cody–Waite should hold here.
        for x in [100.0, -100.0, 1000.0, -1234.5678, 12345.0] {
            XCTAssertEqual(DetMath.sin(x), Foundation.sin(x), accuracy: 1e-12, "sin(\(x))")
            XCTAssertEqual(DetMath.cos(x), Foundation.cos(x), accuracy: 1e-12, "cos(\(x))")
        }
    }

    func testAtanAgreesWithLibm() {
        // Spans all three Cephes reduction branches: |x| <= tan(π/8), <= tan(3π/8), and beyond.
        let samples = [0.0, 1e-8, 0.1, 0.4142135623730950, 0.5, 1.0, 2.0,
                       2.414213562373095, 3.0, 10.0, 1e6, 1e300]
        for s in samples {
            for x in [s, -s] {
                XCTAssertEqual(DetMath.atan(x), Foundation.atan(x), accuracy: 1e-15, "atan(\(x))")
            }
        }
    }

    func testAtan2AgreesWithLibmInAllQuadrants() {
        let vals = [-3.0, -1.0, -0.25, 0.25, 1.0, 3.0]
        for y in vals {
            for x in vals {
                XCTAssertEqual(DetMath.atan2(y, x), Foundation.atan2(y, x),
                               accuracy: 1e-15, "atan2(\(y), \(x))")
            }
        }
    }

    // MARK: - Identity

    func testExactAtCardinalAngles() {
        // ORACLE: exact values of sine and cosine at standard angles.
        let half = 0.5
        let root2over2 = 2.0.squareRoot() / 2
        let root3over2 = 3.0.squareRoot() / 2
        assertCloseInUlps(DetMath.sin(0), 0.0, "sin 0", ulps: 1)
        assertCloseInUlps(DetMath.cos(0), 1.0, "cos 0", ulps: 1)
        XCTAssertEqual(DetMath.sin(Double.pi / 6), half, accuracy: 1e-15, "sin π/6 = 1/2")
        XCTAssertEqual(DetMath.cos(Double.pi / 3), half, accuracy: 1e-15, "cos π/3 = 1/2")
        XCTAssertEqual(DetMath.sin(Double.pi / 4), root2over2, accuracy: 1e-15, "sin π/4")
        XCTAssertEqual(DetMath.cos(Double.pi / 4), root2over2, accuracy: 1e-15, "cos π/4")
        XCTAssertEqual(DetMath.sin(Double.pi / 3), root3over2, accuracy: 1e-15, "sin π/3")
        XCTAssertEqual(DetMath.cos(Double.pi / 6), root3over2, accuracy: 1e-15, "cos π/6")
        XCTAssertEqual(DetMath.sin(Double.pi / 2), 1.0, accuracy: 1e-15, "sin π/2 = 1")
        XCTAssertEqual(DetMath.cos(Double.pi / 2), 0.0, accuracy: 1e-15, "cos π/2 = 0")
    }

    func testPythagoreanIdentity() {
        // sin²x + cos²x = 1, everywhere. Independent of any oracle — it is the definition.
        for i in 0..<2000 {
            let x = -50.0 + 100.0 * Double(i) / 1999.0
            let s = DetMath.sin(x), c = DetMath.cos(x)
            XCTAssertEqual(s * s + c * c, 1.0, accuracy: 1e-14, "sin²+cos² at \(x)")
        }
    }

    func testParity() {
        for i in 1..<500 {
            let x = Double(i) * 0.0173
            XCTAssertEqual(DetMath.sin(-x), -DetMath.sin(x), accuracy: 1e-16, "sin is odd")
            XCTAssertEqual(DetMath.cos(-x), DetMath.cos(x), accuracy: 1e-16, "cos is even")
            XCTAssertEqual(DetMath.atan(-x), -DetMath.atan(x), accuracy: 1e-16, "atan is odd")
        }
    }

    func testAtanInvertsTan() {
        for i in 0..<400 {
            let t = -1.5 + 3.0 * Double(i) / 399.0   // inside (-π/2, π/2)
            XCTAssertEqual(DetMath.atan(DetMath.tan(t)), t, accuracy: 1e-13, "atan(tan(\(t)))")
        }
    }

    // MARK: - Invariant

    func testRangesAreBounded() {
        for i in 0..<5000 {
            let x = -1000.0 + 2000.0 * Double(i) / 4999.0
            XCTAssertLessThanOrEqual(abs(DetMath.sin(x)), 1.0 + 1e-15, "|sin| <= 1")
            XCTAssertLessThanOrEqual(abs(DetMath.cos(x)), 1.0 + 1e-15, "|cos| <= 1")
            XCTAssertLessThan(abs(DetMath.atan(x)), DetMath.halfPi + 1e-15, "|atan| < π/2")
        }
    }

    func testAtan2SignedZeroTakesTheNegativeBranch() {
        // -0.0 is not >= 0 for this purpose: atan2(0, -0.0) is π, not 0. A plain `x >= 0` gets
        // this wrong, and the branch cut then lands in a different place than on a reference impl.
        XCTAssertEqual(DetMath.atan2(0, -0.0), DetMath.pi, accuracy: 0, "atan2(0, -0) = π")
        XCTAssertEqual(DetMath.atan2(0, 0.0), 0, accuracy: 0, "atan2(0, +0) = 0")
        XCTAssertEqual(DetMath.atan2(0, -1.0), DetMath.pi, accuracy: 0, "atan2(0, -1) = π")
    }

    func testInfinitiesAndNaN() {
        XCTAssertEqual(DetMath.atan(.infinity), DetMath.halfPi)
        XCTAssertEqual(DetMath.atan(-.infinity), -DetMath.halfPi)
        XCTAssertTrue(DetMath.sin(.nan).isNaN)
        XCTAssertTrue(DetMath.cos(.infinity).isNaN)
        XCTAssertTrue(DetMath.atan2(.nan, 1).isNaN)
    }

    // MARK: - Tick and units

    func testTickTimeIsIndependentOfPath() {
        // The reason Tick exists: arriving at step 1e6 by one multiply must equal arriving there
        // by a million additions. With a Double accumulator it does not.
        let dt = 0.001
        let direct = Tick(1_000_000).coordinateTime(step: dt)
        var accumulated = 0.0
        for _ in 0..<1_000_000 { accumulated += dt }
        XCTAssertEqual(direct, 1000.0, accuracy: 0, "integer tick is exact")
        XCTAssertNotEqual(accumulated, direct,
                          "float accumulation is expected to drift — that is why Tick exists")
    }

    func testSolarMassConversionOracle() {
        // ORACLE: IAU 2015 Resolution B3 nominal GM☉ = 1.3271244e20 m³/s²; c = 299792458 m/s exactly.
        // GM☉/c² = 1476.6250382 m, the gravitational radius of the Sun.
        let expected = 1.3271244e20 / (299_792_458.0 * 299_792_458.0)
        XCTAssertEqual(Units.solarMassInMetres, expected, accuracy: 1e-4,
                       "GM☉/c² should be ~1476.625 m")
        // Schwarzschild radius of the Sun is 2M ≈ 2953.25 m.
        XCTAssertEqual(Units.metres(fromGeometrized: 2, solarMasses: 1), 2953.250, accuracy: 1e-2)
    }

    // MARK: - Determinism hash

    func testHashIsStableAndOrderSensitive() {
        let a = DeterminismHash.of([1.0, 2.0, 3.0])
        let b = DeterminismHash.of([1.0, 2.0, 3.0])
        let c = DeterminismHash.of([1.0, 3.0, 2.0])
        XCTAssertEqual(a, b, "same input, same digest")
        XCTAssertNotEqual(a, c, "order must matter — a trajectory is a sequence")
    }

    func testHashDetectsALastBitChange() {
        let a = DeterminismHash.of([1.0, 2.0, 3.0])
        let b = DeterminismHash.of([1.0, 2.0, 3.0.nextUp])
        XCTAssertNotEqual(a, b, "a one-ulp divergence must be caught — that is the entire job")
    }

    func testHashFoldsSignedZeroAndCanonicalisesNaN() {
        // These compare equal (or unordered) but carry different bits. Hashing them raw would
        // report a divergence where the physics has none.
        XCTAssertEqual(DeterminismHash.of([0.0]), DeterminismHash.of([-0.0]), "±0 fold together")
        XCTAssertEqual(DeterminismHash.of([Double.nan]),
                       DeterminismHash.of([Double.nan.nextUp]), "NaN canonicalises")
    }
}

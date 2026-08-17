import XCTest
import TensorKit
@testable import RelativityKit

/// ORACLES: every expected value below is a published closed form, not something this code emitted.
///
///   * Horizons r± = M ± √(M² − a²) — Boyer & Lindquist (1967).
///   * Photon orbit and ISCO radii — Bardeen, Press & Teukolsky (1972), ApJ 178, 347.
///   * Schwarzschild limits (r₊ = 2M, photon sphere 3M, ISCO 6M) — standard, and exact.
///
/// Test taxonomy per `docs/calculators_VALIDATION.md`: **Oracle-backed** where a published number is
/// cited, **Identity** where a definition is cross-checked numerically, **Invariant** for bounds and
/// monotonicity.
final class RegionsOracleTests: XCTestCase {

    /// Batch-of-one. Every scalar assertion below therefore also exercises the vector path — there
    /// is no second implementation to drift.
    private func t(_ v: Double) -> Tensor { Tensor(shape: [1], data: [v]) }
    private func first(_ x: Tensor) -> Double { x.data[0] }

    // MARK: - Oracle-backed: horizons

    func testSchwarzschildHorizonIsExactlyTwoM() {
        XCTAssertEqual(first(Regions.outerHorizon(spin: t(0))), 2.0, accuracy: 0,
                       "r₊ = 2M at a = 0, exactly")
        XCTAssertEqual(first(Regions.innerHorizon(spin: t(0))), 0.0, accuracy: 0,
                       "Schwarzschild has no inner horizon")
    }

    func testExtremalHorizonsCoincideAtM() {
        XCTAssertEqual(first(Regions.outerHorizon(spin: t(1))), 1.0, accuracy: 1e-15)
        XCTAssertEqual(first(Regions.innerHorizon(spin: t(1))), 1.0, accuracy: 1e-15)
    }

    func testHorizonsBracketAndProductIsUnity() {
        // Identity: r₊ r₋ = a², and r₊ + r₋ = 2M. Both fall out of Δ = (r − r₊)(r − r₋).
        for a in [0.0, 0.1, 0.5, 0.9, 0.998, 1.0] {
            let rp = first(Regions.outerHorizon(spin: t(a)))
            let rm = first(Regions.innerHorizon(spin: t(a)))
            XCTAssertEqual(rp * rm, a * a, accuracy: 1e-14, "r₊r₋ = a² at a=\(a)")
            XCTAssertEqual(rp + rm, 2.0, accuracy: 1e-14, "r₊+r₋ = 2M at a=\(a)")
            XCTAssertGreaterThanOrEqual(rp, rm, "outer horizon is outside the inner one")
        }
    }

    func testDeltaVanishesAtBothHorizons() {
        // Identity: the horizons are by definition the roots of Δ.
        for a in [0.0, 0.3, 0.7, 0.95] {
            let rp = Regions.outerHorizon(spin: t(a))
            let rm = Regions.innerHorizon(spin: t(a))
            XCTAssertEqual(first(KerrMetric.delta(r: rp, spin: t(a))), 0, accuracy: 1e-14)
            XCTAssertEqual(first(KerrMetric.delta(r: rm, spin: t(a))), 0, accuracy: 1e-14)
        }
    }

    // MARK: - Oracle-backed: ergosphere

    func testErgosphereTouchesHorizonOnAxisAndReachesTwoMAtEquator() {
        for a in [0.1, 0.5, 0.9, 0.999] {
            let onAxis = first(Regions.ergosphereOuter(theta: t(0), spin: t(a)))
            let rp = first(Regions.outerHorizon(spin: t(a)))
            XCTAssertEqual(onAxis, rp, accuracy: 1e-14,
                           "ergosphere meets the horizon on the rotation axis, a=\(a)")

            let equator = first(Regions.ergosphereOuter(theta: t(DetMathPi / 2), spin: t(a)))
            XCTAssertEqual(equator, 2.0, accuracy: 1e-12,
                           "static limit is 2M in the equatorial plane for ANY spin, a=\(a)")
        }
    }

    func testNoErgosphereForSchwarzschild() {
        // At a = 0 the static limit collapses onto the horizon: there is nowhere you cannot stand.
        for th in [0.0, 0.5, 1.0, DetMathPi / 2] {
            XCTAssertEqual(first(Regions.ergosphereOuter(theta: t(th), spin: t(0))), 2.0,
                           accuracy: 1e-15)
        }
    }

    // MARK: - Oracle-backed: photon orbit and ISCO (Bardeen, Press & Teukolsky 1972)

    func testPhotonSphereIsThreeMForSchwarzschild() {
        XCTAssertEqual(first(Regions.photonOrbit(spin: t(0), prograde: true)), 3.0, accuracy: 1e-12,
                       "photon sphere at exactly 3M when a = 0")
        XCTAssertEqual(first(Regions.photonOrbit(spin: t(0), prograde: false)), 3.0, accuracy: 1e-12)
    }

    func testExtremalPhotonOrbits() {
        // BPT: 1M prograde, 4M retrograde at a = M.
        XCTAssertEqual(first(Regions.photonOrbit(spin: t(1), prograde: true)), 1.0, accuracy: 1e-9)
        XCTAssertEqual(first(Regions.photonOrbit(spin: t(1), prograde: false)), 4.0, accuracy: 1e-9)
    }

    func testIscoIsSixMForSchwarzschild() {
        XCTAssertEqual(first(Regions.isco(spin: t(0), prograde: true)), 6.0, accuracy: 1e-12,
                       "ISCO at exactly 6M when a = 0")
        XCTAssertEqual(first(Regions.isco(spin: t(0), prograde: false)), 6.0, accuracy: 1e-12)
    }

    func testExtremalIsco() {
        // BPT eq. (2.21): 1M prograde, 9M retrograde at a = M.
        XCTAssertEqual(first(Regions.isco(spin: t(1), prograde: true)), 1.0, accuracy: 1e-9)
        XCTAssertEqual(first(Regions.isco(spin: t(1), prograde: false)), 9.0, accuracy: 1e-9)
    }

    // MARK: - Invariant: ordering and monotonicity

    func testRadialOrderingHolds() {
        // r₋ ≤ r₊ ≤ r_photon(pro) ≤ r_ISCO(pro), for every spin. The level layout, asserted.
        for a in [0.0, 0.2, 0.5, 0.8, 0.95, 0.999] {
            let rm = first(Regions.innerHorizon(spin: t(a)))
            let rp = first(Regions.outerHorizon(spin: t(a)))
            let ph = first(Regions.photonOrbit(spin: t(a), prograde: true))
            let iscoR = first(Regions.isco(spin: t(a), prograde: true))
            XCTAssertLessThanOrEqual(rm, rp + 1e-12, "a=\(a)")
            XCTAssertLessThanOrEqual(rp, ph + 1e-9, "photon orbit is outside the horizon, a=\(a)")
            XCTAssertLessThanOrEqual(ph, iscoR + 1e-9, "ISCO is outside the photon orbit, a=\(a)")
        }
    }

    func testProgradeOrbitsAreAlwaysTighter() {
        for a in [0.1, 0.4, 0.7, 0.9, 0.99] {
            XCTAssertLessThan(first(Regions.isco(spin: t(a), prograde: true)),
                              first(Regions.isco(spin: t(a), prograde: false)),
                              "co-rotating ISCO sits closer in, a=\(a)")
        }
    }

    func testFrameDraggingVanishesWithoutSpinAndIsPositiveWithIt() {
        let th = t(DetMathPi / 2)
        XCTAssertEqual(first(Regions.framePickupRate(r: t(5), theta: th, spin: t(0))), 0,
                       accuracy: 0, "no spin, no dragging")
        XCTAssertGreaterThan(first(Regions.framePickupRate(r: t(2), theta: th, spin: t(0.9))), 0,
                             "a spinning hole drags a zero-angular-momentum body forward")
    }

    func testStaticObserversCeaseToExistAtTheStaticLimit() {
        // The redshift factor for a static observer goes to zero exactly on the ergosphere
        // boundary — the same statement as "you cannot stand still", from the other direction.
        let a = t(0.9), th = t(DetMathPi / 2)
        let re = Regions.ergosphereOuter(theta: th, spin: a)
        XCTAssertEqual(first(Regions.staticRedshiftFactor(r: re, theta: th, spin: a)), 0,
                       accuracy: 1e-12)
        XCTAssertGreaterThan(first(Regions.staticRedshiftFactor(r: t(10), theta: th, spin: a)), 0.8,
                             "far away, clocks run nearly normally")
    }

    // MARK: - Vector discipline

    func testBatchOfManyMatchesBatchOfOne() {
        // The whole architecture rests on this: N = 1 and N = many are the same code. If they ever
        // disagree, the batching is a second implementation and the oracle only covers one of them.
        let spins = [0.0, 0.15, 0.3, 0.45, 0.6, 0.75, 0.9, 0.99]
        let batch = Tensor(shape: [spins.count], data: spins)
        let batchIsco = Regions.isco(spin: batch, prograde: true)
        for (i, a) in spins.enumerated() {
            XCTAssertEqual(batchIsco.data[i], first(Regions.isco(spin: t(a), prograde: true)),
                           accuracy: 0, "batched ISCO must be bit-identical to scalar at a=\(a)")
        }
    }
}

/// π, spelled out here so the test file does not import a libm constant into a determinism-critical
/// package by habit.
let DetMathPi = 3.14159265358979311600e+00

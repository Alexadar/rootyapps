import XCTest
import MLX
@testable import CityPigeon

/// The closed form, tested as IDENTITIES, ORDERINGS and AGREEMENT WITH AN INDEPENDENT INTEGRATOR
/// rather than as remembered numbers.
///
/// Almost nothing here asserts a literal. A literal expectation is a second copy of the
/// implementation written by the same hand; an identity (`f⁻¹(f(x)) == x`), an ordering
/// (`more charge ⇒ sooner`), or agreement with RK4 are claims the implementation cannot satisfy by
/// being consistently wrong.
///
/// **On tolerances.** The engine is Float32 because MLX has no Float64, and the reference is Double.
/// So every disagreement below is dominated by Float32 rounding, not by the integrator — RK4 is
/// exact for constant acceleration. Tolerances are stated as absolute where the expression cancels
/// and relative where it does not, and each says which.
final class DropOracleTests: XCTestCase {

    let w = WorldConfig.shipping
    var rk4: PayloadIntegrator { PayloadIntegrator(gravity: w.gravity) }

    // MARK: - Identities

    /// `u → T → u` over a grid that covers the whole playable envelope and then some.
    ///
    /// **Absolute**, not relative. `u = gT/2 − H/T` is a difference of two similar-magnitude terms
    /// exactly when `u ≈ 0` (i.e. `T ≈ √(2H/g)`), so relative error there is unbounded while
    /// absolute error stays at a few ulp of the larger term. Asserting relatively would make this
    /// test flaky for a reason that has nothing to do with correctness.
    func testReleaseVelocityAndFlightTimeAreInverses() {
        var us: [Double] = [], hs: [Double] = []
        for u in stride(from: -40.0, through: 10.0, by: 2.0) {
            for h in stride(from: 2.0, through: 40.0, by: 2.0) { us.append(u); hs.append(h) }
        }
        let U = arr(us), H = arr(hs)

        let T = Drop.flightTime(releaseVelocity: U, drop: H, in: w)
        let back = Drop.releaseVelocity(flightTime: T.value, drop: H, in: w)

        XCTAssertTrue(allTrue(T.valid), "a drop from a positive height was refused")
        let worst = maxAbsDiff(back.value, U)
        print("IDENTITY u→T→u: worst absolute error \(worst) m/s over \(us.count) samples")
        // Measured 7.6e-6. Set at ~13x that: tight enough to catch a formula change, loose enough
        // that Float32 lane-ordering differences cannot make it flaky.
        XCTAssertLessThan(worst, 1e-4,
                          "the inverse is not recovering u — at Float32 a few ulp of gT/2 is ~1e-5")
    }

    /// `T → u → T`, the other way round.
    func testFlightTimeAndReleaseVelocityAreInverses() {
        var ts: [Double] = [], hs: [Double] = []
        for t in stride(from: 0.4, through: 4.0, by: 0.2) {
            for h in stride(from: 2.0, through: 40.0, by: 2.0) { ts.append(t); hs.append(h) }
        }
        let T = arr(ts), H = arr(hs)

        let u = Drop.releaseVelocity(flightTime: T, drop: H, in: w)
        let back = Drop.flightTime(releaseVelocity: u.value, drop: H, in: w)

        let worst = maxRelDiff(back.value, T)
        print("IDENTITY T→u→T: worst relative error \(worst) over \(ts.count) samples")
        XCTAssertLessThan(worst, 2e-6, "the round trip through u is losing more than Float32 alone")  // measured 1.3e-7
    }

    /// `c → T → c`, covering both signs of climb rate.
    func testChargeAndFlightTimeAreInverses() {
        var cs: [Double] = [], hs: [Double] = [], vys: [Double] = []
        for c in stride(from: 0.0, through: 1.0, by: 0.05) {
            for h in stride(from: 20.0, through: 34.0, by: 2.0) {
                for vy in [-4.0, 0.0, 4.0] { cs.append(c); hs.append(h); vys.append(vy) }
            }
        }
        let C = arr(cs), H = arr(hs), VY = arr(vys)

        let T = Drop.flightTime(drop: H, climb: VY, charge: C, in: w)
        let back = Drop.charge(flightTime: T.value, drop: H, climb: VY, in: w)

        XCTAssertTrue(allTrue(T.valid))
        let worst = maxAbsDiff(back.value, C)
        print("IDENTITY c→T→c: worst absolute error \(worst) over \(cs.count) samples")
        XCTAssertLessThan(worst, 2e-6, "charge does not round-trip through flight time")  // measured 1.8e-7
    }

    /// The textbook case, which the model must reproduce without being told: released with no
    /// vertical velocity at all, the payload takes `√(2H/g)`.
    func testFreeFallMatchesTheTextbook() {
        let hs = Array(stride(from: 1.0, through: 40.0, by: 1.0))
        let T = Drop.flightTime(releaseVelocity: arr(hs.map { _ in 0.0 }), drop: arr(hs), in: w)
        let expected = hs.map { (2 * $0 / w.gravity).squareRoot() }
        let worst = maxRelDiff(T.value, arr(expected))
        print("IDENTITY free fall: worst relative error \(worst)")
        XCTAssertLessThan(worst, 1e-6)  // measured 1.0e-7
    }

    /// Energy is conserved along the analytic arc — a property of the *position* function, which is
    /// a separate code path from the flight-time solve and would otherwise go unchecked.
    func testEnergyIsConservedAlongTheArc() {
        let n = 21
        let times = arr((0..<n).map { 1.8 * Double($0) / Double(n - 1) })
        let x0 = MLXArray.zeros([n]), y0 = MLXArray.ones([n]) * 30
        let vx0 = MLXArray.ones([n]) * 12, u0 = MLXArray.ones([n]) * -8

        let p = Drop.position(x0: x0, y0: y0, vx0: vx0, u0: u0, elapsed: times, in: w)
        let vy = u0 - MLXArray(Float(w.gravity)) * times
        let energy = 0.5 * (vx0 * vx0 + vy * vy) + MLXArray(Float(w.gravity)) * p.y

        let e = energy.asArray(Float.self).map(Double.init)
        let spread = (e.max()! - e.min()!) / abs(e[0])
        print("IDENTITY energy: relative spread \(spread) over \(n) samples")
        XCTAssertLessThan(spread, 1e-6)  // measured 7.7e-8
    }

    // MARK: - Agreement with independent mathematics

    /// The closed form against RK4. Two different mathematics: one solves, one integrates.
    func testAgreesWithTheIndependentIntegrator() {
        var worstTime = 0.0, worstX = 0.0, checked = 0

        for u in stride(from: -30.0, through: 6.0, by: 4.0) {
            for h in stride(from: 4.0, through: 34.0, by: 6.0) {
                for vx in [9.0, 12.0, 15.0] {
                    let T = Drop.flightTime(releaseVelocity: arr([u]), drop: arr([h]), in: w)
                    guard T.valid.item(Bool.self) else { continue }
                    let tClosed = Double(T.value.item(Float.self))
                    let xClosed = vx * tClosed

                    guard let hit = rk4.impact(x0: 0, y0: h, vx0: vx, u0: u, plane: 0) else {
                        XCTFail("RK4 found no impact for u=\(u) h=\(h) — the closed form claims \(tClosed)")
                        continue
                    }
                    worstTime = max(worstTime, abs(hit.time - tClosed) / hit.time)
                    worstX = max(worstX, abs(hit.x - xClosed) / max(abs(hit.x), 1))
                    checked += 1
                }
            }
        }

        print("AGREEMENT vs RK4 over \(checked) shots: time \(worstTime) rel, x \(worstX) rel")
        XCTAssertGreaterThan(checked, 50)
        // Float32 in the engine against Double RK4. 1e-5 relative is a few Float32 ulp; anything
        // materially worse means the formula, not the precision.
        // Measured 8.0e-8 for both — Float32 machine precision. RK4 contributes nothing at this
        // scale because it is exact for constant acceleration.
        XCTAssertLessThan(worstTime, 1e-6)
        XCTAssertLessThan(worstX, 1e-6)
    }

    /// **The numerical-stability regression.**
    ///
    /// `(u + √D)/g` cancels catastrophically for `u < 0` with `2gH ≪ u²` — a fast charged shot
    /// released just above a target, which is a shot this game actively encourages. The shipped
    /// two-branch form must beat the naive one by orders of magnitude, not by a little.
    func testTheStableRootBeatsTheNaiveFormWhereItCancels() {
        let u: Double = -100, h: Double = 0.001
        let g = w.gravity

        // Exact reference, computed in Double through the non-cancelling branch.
        let exact = 2 * h / ((u * u + 2 * g * h).squareRoot() - u)

        // What a Float32 implementation of the textbook form would produce.
        let uF = Float(u), hF = Float(h), gF = Float(g)
        let naive = Double((uF + (uF * uF + 2 * gF * hF).squareRoot()) / gF)

        let shipped = Double(Drop.flightTime(releaseVelocity: arr([u]), drop: arr([h]), in: w)
            .value.item(Float.self))

        let naiveErr = abs(naive - exact) / exact
        let shippedErr = abs(shipped - exact) / exact
        print("STABILITY at u=\(u) H=\(h): naive \(naiveErr) rel · shipped \(shippedErr) rel")

        XCTAssertLessThan(shippedErr, 1e-5, "the shipped root is cancelling")
        XCTAssertLessThan(shippedErr * 100, naiveErr,
                          "the stable branch is not actually buying anything here — either the "
                          + "branch selection is wrong or this case no longer cancels")
    }

    // MARK: - Orderings

    /// Every monotonicity the envelope argument rests on, asserted **separately**, strictly, and
    /// across both signs of climb rate — `u < 0` is the branch a derivative argument nearly loses.
    func testFlightTimeIsStrictlyIncreasingInReleaseVelocity() {
        for h in [4.0, 12.0, 30.0] {
            let us = Array(stride(from: -40.0, through: 10.0, by: 0.5))
            let T = Drop.flightTime(releaseVelocity: arr(us),
                                    drop: arr(us.map { _ in h }), in: w).value.asArray(Float.self)
            for i in 1..<T.count {
                XCTAssertGreaterThan(T[i], T[i - 1],
                                     "T not strictly increasing in u at h=\(h), u=\(us[i])")
            }
        }
    }

    func testFlightTimeIsStrictlyIncreasingInDrop() {
        for u in [-25.0, -8.0, 0.0, 5.0] {
            let hs = Array(stride(from: 1.0, through: 40.0, by: 0.5))
            let T = Drop.flightTime(releaseVelocity: arr(hs.map { _ in u }),
                                    drop: arr(hs), in: w).value.asArray(Float.self)
            for i in 1..<T.count {
                XCTAssertGreaterThan(T[i], T[i - 1], "T not strictly increasing in H at u=\(u)")
            }
        }
    }

    func testLeadIsStrictlyDecreasingInCharge() {
        for h in [22.0, 30.0, 34.0] {
            for vy in [-4.0, 0.0, 4.0] {
                let cs = Array(stride(from: 0.0, through: 1.0, by: 0.01))
                let T = Drop.flightTime(drop: arr(cs.map { _ in h }), climb: arr(cs.map { _ in vy }),
                                        charge: arr(cs), in: w)
                let lead = Drop.lead(forwardSpeed: arr(cs.map { _ in 12.0 }), flightTime: T.value)
                    .asArray(Float.self)
                for i in 1..<lead.count {
                    XCTAssertLessThan(lead[i], lead[i - 1],
                                      "lead not strictly decreasing in charge at h=\(h) vy=\(vy)")
                }
            }
        }
    }

    /// The identity that bounds how much authority a charge meter can ever have:
    /// `ΔT = T(0) − T(1) ≤ V/g`, with equality only in the limit of infinite altitude.
    func testChargeAuthorityIsBoundedByTheImpulseItImparts() {
        let bound = w.maxChargeSpeed / w.gravity
        for h in stride(from: 5.0, through: 200.0, by: 5.0) {
            let t0 = Drop.flightTime(releaseVelocity: arr([0]), drop: arr([h]), in: w)
            let t1 = Drop.flightTime(releaseVelocity: arr([-w.maxChargeSpeed]), drop: arr([h]), in: w)
            let dt = Double(t0.value.item(Float.self)) - Double(t1.value.item(Float.self))
            XCTAssertLessThanOrEqual(dt, bound + 1e-5, "ΔT exceeds V/g at h=\(h)")
        }
    }

    // MARK: - Degenerate inputs
    //
    // The register the sibling project uses: the reasons a shot is refused are *distinct*, and each
    // is asserted by name so that "simplifying" one away breaks a test rather than a game.

    /// **At `H = 0` the monotonicity claim is false**, and this test exists to say so out loud.
    ///
    /// The roots degenerate to `{0, 2u/g}`, so `T ≡ 0` for every `u ≤ 0` — a flat region covering
    /// every charged shot. This is documentation of why `minReleaseAltitude > 0` is a strict
    /// precondition rather than a nicety, and the engine must refuse the input rather than return a
    /// monotone-looking lie.
    func testAtZeroDropTheModelIsRefusedRatherThanBelieved() {
        let us = arr([-20.0, -5.0, 0.0, 5.0])
        let s = Drop.flightTime(releaseVelocity: us, drop: arr([0.0, 0.0, 0.0, 0.0]), in: w)
        XCTAssertFalse(anyTrue(s.valid),
                       "a zero drop was accepted; T is flat in u there and every downstream "
                       + "guarantee assumes it is strictly increasing")
    }

    /// **`H < 0` is a real case** — a plane above the release point, which happens the moment the
    /// pigeon flies below the roof of something tall. The `+` root would report a crossing the
    /// payload only reaches after passing through the body.
    func testADropOntoAPlaneAboveTheReleasePointIsRefused() {
        let s = Drop.flightTime(releaseVelocity: arr([-10.0, 0.0, 10.0]),
                                drop: arr([-2.0, -0.5, -8.0]), in: w)
        XCTAssertFalse(anyTrue(s.valid), "a negative drop was accepted")
    }

    /// A zero-width charge span cannot be inverted, and must be reported rather than divided by.
    func testChargeIsRefusedWhenTheSpanCollapses() {
        var flat = w
        flat.fullChargeTimeRatio = 1.0        // full charge does nothing ⇒ t0 == t1
        let s = Drop.charge(flightTime: arr([2.0]), drop: arr([30.0]), climb: arr([0.0]), in: flat)
        XCTAssertFalse(anyTrue(s.valid), "charge was inverted through a collapsed span")
    }

    /// Invalid lanes must not poison valid ones. A NaN in one lane of a batch would propagate
    /// through any reduction and silently corrupt every world in the batch.
    func testInvalidLanesDoNotContaminateValidOnes() {
        let H = arr([30.0, -1.0, 25.0, 0.0, 22.0])
        let U = arr([-10.0, -10.0, -10.0, -10.0, -10.0])
        let s = Drop.flightTime(releaseVelocity: U, drop: H, in: w)

        let valid = s.valid.asArray(Bool.self)
        XCTAssertEqual(valid, [true, false, true, false, true])
        for (i, v) in s.value.asArray(Float.self).enumerated() where valid[i] {
            XCTAssertTrue(v.isFinite, "valid lane \(i) is not finite")
        }
        XCTAssertTrue(s.filled(-1).sum().item(Float.self).isFinite,
                      "a reduction over the filled array produced a non-finite value")
    }

    // MARK: - Helpers

    private func arr(_ xs: [Double]) -> MLXArray { MLXArray(xs.map { Float($0) }) }
    private func allTrue(_ a: MLXArray) -> Bool { a.asArray(Bool.self).allSatisfy { $0 } }
    private func anyTrue(_ a: MLXArray) -> Bool { a.asArray(Bool.self).contains(true) }

    private func maxAbsDiff(_ a: MLXArray, _ b: MLXArray) -> Double {
        zip(a.asArray(Float.self), b.asArray(Float.self))
            .map { abs(Double($0) - Double($1)) }.max() ?? 0
    }

    private func maxRelDiff(_ a: MLXArray, _ b: MLXArray) -> Double {
        zip(a.asArray(Float.self), b.asArray(Float.self))
            .map { abs(Double($0) - Double($1)) / max(abs(Double($1)), 1e-9) }.max() ?? 0
    }
}

import XCTest
import MLX
@testable import CityPigeon

/// The interception solve, checked against methods that do not share its reasoning.
///
/// Three independent challengers, in increasing order of independence:
///  1. **A bisector** that knows only `miss` as a black box and searches for a sign change. It never
///     reads `window`, so agreement is evidence rather than tautology.
///  2. **A brute-force scan** that asserts the window as a *set* — every charge inside hits, every
///     charge outside misses — rather than merely checking its endpoints.
///  3. **RK4 construction**: ask the integrator where a shot lands and when, then place a moving
///     target exactly there at exactly that moment. Such a target is hittable by construction and
///     the solver's only job is to agree. Nothing about the placement involves the engine.
final class InterceptionOracleTests: XCTestCase {

    let w = WorldConfig.shipping
    var rk4: PayloadIntegrator { PayloadIntegrator(gravity: w.gravity) }

    /// A shot, in the coordinates the engine uses.
    struct Shot {
        var px = 0.0, py = 30.0, vx = 12.0, vy = 0.0
        var tx = 25.0, tv = -6.0, topY = 1.45
        var r = 3.0
    }

    // MARK: - Agreement with independent methods

    /// The best charge must actually hit, asserted **in miss-space rather than root-space**.
    ///
    /// `dc/dT → ∞` as `T → 0`, so a tolerance on the charge value is condition-dependent while a
    /// tolerance on the resulting miss is not. Metres are the honest unit for "did it hit".
    func testTheBestChargeLandsOnTheTarget() {
        var worst = 0.0, checked = 0
        for tv in stride(from: -10.0, through: 5.0, by: 2.5) {
            for tx in stride(from: 14.0, through: 26.0, by: 2.0) {
                let s = Shot(tx: tx, tv: tv)
                let win = window(s)
                guard win.valid.item(Bool.self) else { continue }
                let c = Interception.bestCharge(win).value
                let m = abs(Double(miss(s, charge: c).value.item(Float.self)))
                worst = max(worst, m)
                checked += 1
            }
        }
        print("INTERCEPT best-charge worst |miss| = \(worst) m over \(checked) shots")
        XCTAssertGreaterThan(checked, 20)
        XCTAssertLessThan(worst, w.hitRadius(w.car),
                          "the window midpoint does not even land inside the target")
    }

    /// Closed form against a bisector that only knows `miss`.
    func testAgreesWithAnIndependentBisector() {
        var worst = 0.0, checked = 0
        for tv in stride(from: -10.0, through: 4.0, by: 2.0) {
            for tx in stride(from: 15.0, through: 25.0, by: 1.0) {
                let s = Shot(tx: tx, tv: tv)
                let win = window(s)
                guard win.valid.item(Bool.self) else { continue }

                guard let bisected = bisectForExactHit(s) else { continue }
                let m = abs(Double(miss(s, charge: MLXArray(Float(bisected))).value.item(Float.self)))
                XCTAssertLessThan(m, 1e-3, "the bisector's own root does not hit")

                // The bisector's root must lie inside the closed-form window.
                let lo = Double(win.lo.item(Float.self)), hi = Double(win.hi.item(Float.self))
                XCTAssertTrue(bisected >= lo - 1e-4 && bisected <= hi + 1e-4,
                              "bisector found an exact hit at c=\(bisected) that the closed-form "
                              + "window [\(lo), \(hi)] excludes")
                worst = max(worst, m)
                checked += 1
            }
        }
        print("INTERCEPT bisector agreement over \(checked) shots, worst |miss| \(worst) m")
        XCTAssertGreaterThan(checked, 20)
    }

    /// **The window as a set**, not as two endpoints. This is the claim that actually matters and
    /// the one an endpoint check cannot make.
    func testEveryChargeInsideTheWindowHitsAndEveryChargeOutsideMisses() {
        let s = Shot(tx: 20.0, tv: -6.0)
        let win = window(s)
        XCTAssertTrue(win.valid.item(Bool.self))
        let lo = Double(win.lo.item(Float.self)), hi = Double(win.hi.item(Float.self))

        var insideChecked = 0, outsideChecked = 0
        for i in 0...1000 {
            let c = w.chargeFloor + (w.chargeCeiling - w.chargeFloor) * Double(i) / 1000
            let m = abs(Double(miss(s, charge: MLXArray(Float(c))).value.item(Float.self)))
            // A slim guard band around the boundary: within one Float32 ulp of r the classification
            // is genuinely undetermined and asserting either way would be superstition.
            if c > lo + 1e-3 && c < hi - 1e-3 {
                XCTAssertLessThanOrEqual(m, s.r + 1e-3, "c=\(c) is inside the window but misses")
                insideChecked += 1
            } else if c < lo - 1e-3 || c > hi + 1e-3 {
                XCTAssertGreaterThanOrEqual(m, s.r - 1e-3, "c=\(c) is outside the window but hits")
                outsideChecked += 1
            }
        }
        print("INTERCEPT set equality: \(insideChecked) inside, \(outsideChecked) outside")
        XCTAssertGreaterThan(insideChecked, 50)
        XCTAssertGreaterThan(outsideChecked, 50)
    }

    /// **Construct, then ask.** RK4 decides where the payload goes; a target is placed to be there.
    ///
    /// The placement uses no engine mathematics beyond the charge→velocity mapping it is given, so a
    /// disagreement here is the solver's, not the test's. This is the single most valuable test in
    /// the suite for the same reason `RoofPlacer` was in the sibling project.
    func testATargetPlacedWhereTheIntegratorSaysThePayloadLandsIsReportedHittable() {
        var checked = 0
        for c in stride(from: 0.1, through: 0.9, by: 0.1) {
            for tv in [-8.0, -3.0, 0.0, 3.0] {
                let s = Shot(tv: tv)
                let H = s.py - s.topY

                // The release velocity this charge implies — the one piece of engine mapping used.
                let T = Drop.flightTime(drop: MLXArray(Float(H)), climb: MLXArray(Float(s.vy)),
                                        charge: MLXArray(Float(c)), in: w)
                guard T.valid.item(Bool.self) else { continue }
                let u = Double(Drop.releaseVelocity(flightTime: T.value, drop: MLXArray(Float(H)),
                                                    in: w).value.item(Float.self))

                // RK4 decides the landing, independently.
                guard let hit = rk4.impact(x0: s.px, y0: s.py, vx0: s.vx, u0: u, plane: s.topY)
                else { XCTFail("RK4 found no impact at c=\(c)"); continue }

                // Place the target so it arrives at that spot at that instant.
                var placed = s
                placed.tx = hit.x - tv * hit.time

                let win = window(placed)
                XCTAssertTrue(win.valid.item(Bool.self),
                              "a target constructed to be hit at c=\(c), tv=\(tv) was reported unhittable")
                let lo = Double(win.lo.item(Float.self)), hi = Double(win.hi.item(Float.self))
                XCTAssertTrue(c >= lo - 1e-3 && c <= hi + 1e-3,
                              "constructing charge \(c) is outside the reported window [\(lo), \(hi)]")
                checked += 1
            }
        }
        print("INTERCEPT construct-then-ask: \(checked) constructed shots all recovered")
        XCTAssertGreaterThan(checked, 20)
    }

    /// **The millimetre sandwich.** Bracketing a boolean from both sides is the sharpest statement
    /// available about it.
    ///
    /// Framed by the target's *geometric* edge rather than by any quantity the implementation also
    /// computes — the sibling project learned that placing by a derived edge turns the test into a
    /// restatement of the implementation.
    func testTheHitBoundaryIsBracketedToAMillimetre() {
        let base = Shot(tv: -6.0)

        // Find the extreme reachable impact point at the usable charge floor, from geometry only.
        let H = base.py - base.topY
        let T = Drop.flightTime(drop: MLXArray(Float(H)), climb: MLXArray(Float(base.vy)),
                                charge: MLXArray(Float(w.chargeFloor)), in: w)
        let tFlight = Double(T.value.item(Float.self))
        let impactX = base.px + base.vx * tFlight

        // A target whose centre is exactly r beyond that impact point is grazed; one a millimetre
        // further cannot be reached at any charge.
        for (offset, shouldHit) in [(base.r - 0.001, true), (base.r + 0.001, false)] {
            var s = base
            s.tx = impactX + offset - base.tv * tFlight
            let win = window(s)
            let hittable = win.valid.item(Bool.self)
            XCTAssertEqual(hittable, shouldHit,
                           "a target centred \(offset) m past the furthest reachable impact point "
                           + "was reported \(hittable ? "hittable" : "unhittable")")
        }
    }

    // MARK: - Degenerate cases, each distinct and named

    /// Co-moving with the pigeon is a **third outcome**: every charge hits, or none does.
    func testCoMovingTargetsAreAllOrNothing() {
        var aligned = Shot(tv: 12.0, r: 3.0)        // exactly the pigeon's speed
        aligned.tx = aligned.px + 1.0               // within r
        let hit = window(aligned)
        XCTAssertTrue(hit.valid.item(Bool.self), "a co-moving target within r was reported unhittable")
        XCTAssertEqual(Double(hit.lo.item(Float.self)), w.chargeFloor, accuracy: 1e-5)
        XCTAssertEqual(Double(hit.hi.item(Float.self)), w.chargeCeiling, accuracy: 1e-5,
                       "a co-moving target within r should be hittable at EVERY charge")

        var offset = aligned
        offset.tx = offset.px + 20.0                // co-moving but out of reach
        XCTAssertFalse(window(offset).valid.item(Bool.self),
                       "a co-moving target beyond r was reported hittable — no charge can help, "
                       + "because the miss does not depend on the charge at all")
    }

    /// Approaching co-moving must not blow up. The point solve `Δx₀/Δv` would; the window must not.
    func testNearCoMovingDegradesGracefully() {
        for dv in [1.0, 0.1, 0.01, 1e-3, 1e-4, 1e-5, 0.0] {
            var s = Shot(tv: 12.0 - dv)
            s.tx = s.px + 1.0
            let win = window(s)
            let lo = Double(win.lo.item(Float.self)), hi = Double(win.hi.item(Float.self))
            XCTAssertTrue(lo.isFinite && hi.isFinite, "Δv=\(dv) produced a non-finite window")
            XCTAssertTrue(lo >= w.chargeFloor - 1e-5 && hi <= w.chargeCeiling + 1e-5,
                          "Δv=\(dv) produced a window outside the charge domain: [\(lo), \(hi)]")
        }
    }

    /// A target behind the pigeon and falling further behind is refused, not solved with a negative
    /// flight time.
    func testATargetBehindAndReceedingIsRefused() {
        let s = Shot(tx: -30.0, tv: -8.0)
        XCTAssertFalse(window(s).valid.item(Bool.self),
                       "a target behind the pigeon was reported hittable")
    }

    /// The pigeon flying below a target's impact plane must be refused, not silently solved on the
    /// wrong root.
    func testFlyingBelowATargetPlaneIsRefused() {
        var s = Shot()
        s.py = 1.0                 // below the car roof at 1.45
        XCTAssertFalse(window(s).valid.item(Bool.self))
    }

    // MARK: - Helpers

    private func window(_ s: Shot) -> Window {
        Interception.window(pigeonX: MLXArray(Float(s.px)), pigeonY: MLXArray(Float(s.py)),
                            forwardSpeed: MLXArray(Float(s.vx)), climb: MLXArray(Float(s.vy)),
                            targetX: MLXArray(Float(s.tx)), targetSpeed: MLXArray(Float(s.tv)),
                            targetTopY: MLXArray(Float(s.topY)), radius: MLXArray(Float(s.r)), in: w)
    }

    private func miss(_ s: Shot, charge c: MLXArray) -> Solution {
        Interception.miss(pigeonX: MLXArray(Float(s.px)), pigeonY: MLXArray(Float(s.py)),
                          forwardSpeed: MLXArray(Float(s.vx)), climb: MLXArray(Float(s.vy)),
                          targetX: MLXArray(Float(s.tx)), targetSpeed: MLXArray(Float(s.tv)),
                          targetTopY: MLXArray(Float(s.topY)), charge: c, in: w)
    }

    /// The independent challenger. Knows only that `miss` is continuous and monotone in charge;
    /// knows nothing whatsoever about how `window` reaches its answer.
    private func bisectForExactHit(_ s: Shot) -> Double? {
        func f(_ c: Double) -> Double? {
            let sol = miss(s, charge: MLXArray(Float(c)))
            return sol.valid.item(Bool.self) ? Double(sol.value.item(Float.self)) : nil
        }
        guard var lo = f(w.chargeFloor).map({ ($0, w.chargeFloor) }),
              var hi = f(w.chargeCeiling).map({ ($0, w.chargeCeiling) }) else { return nil }
        guard lo.0.sign != hi.0.sign else { return nil }        // no bracket, no root

        for _ in 0..<60 {
            let mid = (lo.1 + hi.1) / 2
            guard let fm = f(mid) else { return nil }
            if fm.sign == lo.0.sign { lo = (fm, mid) } else { hi = (fm, mid) }
        }
        return (lo.1 + hi.1) / 2
    }
}

import XCTest
import MLX
@testable import CityPigeon

/// The release-time solver, checked against methods that do not share its reasoning.
///
/// The instantaneous solver answers "which charge, if I let go now". This one answers "when to let
/// go, starting from now" — and the difference is not academic: charging takes 0.9 s, during which
/// the pigeon covers 11 m and the traffic keeps moving.
final class ReleaseTimingTests: XCTestCase {

    let w = WorldConfig.shipping
    var rk4: PayloadIntegrator { PayloadIntegrator(gravity: w.gravity) }

    struct Shot {
        var px = 0.0, py = 18.0, vx = 12.0, vy = 0.0, cNow = 0.0
        var tx = 34.0, tv = -6.0, topY = 1.45, r = 3.0
    }

    private func releaseWindow(_ s: Shot) -> Window {
        Interception.releaseWindow(
            pigeonX: MLXArray(Float(s.px)), pigeonY: MLXArray(Float(s.py)),
            forwardSpeed: MLXArray(Float(s.vx)), climb: MLXArray(Float(s.vy)),
            charge: MLXArray(Float(s.cNow)),
            targetX: MLXArray(Float(s.tx)), targetSpeed: MLXArray(Float(s.tv)),
            targetTopY: MLXArray(Float(s.topY)), radius: MLXArray(Float(s.r)), in: w)
    }

    /// Impact time as a function of release time, computed *only* from the host `Config` scalars —
    /// no contact with `Interception`.
    private func impactTime(_ s: Shot, tau: Double) -> Double? {
        let c = min(w.chargeCeiling, s.cNow + tau / w.chargeTime)
        guard let T = w.flightTime(drop: s.py - s.topY, climb: s.vy, charge: c) else { return nil }
        return tau + T
    }

    // MARK: - The affine claim, which everything else rests on

    /// `G(τ)` must be affine with a constant slope while the charge is still ramping.
    ///
    /// This is the structural fact that makes the solve closed form rather than a search. If it ever
    /// stops holding — someone reparametrises the charge curve, say — the solver silently starts
    /// returning wrong answers instead of failing, so it is asserted directly rather than trusted.
    func testImpactTimeIsAffineInReleaseTime() {
        let s = Shot()
        let tauFull = (w.chargeCeiling - s.cNow) * w.chargeTime
        var slopes: [Double] = []
        for i in 0..<40 {
            let t1 = tauFull * Double(i) / 40, t2 = tauFull * Double(i + 1) / 40
            guard let g1 = impactTime(s, tau: t1), let g2 = impactTime(s, tau: t2) else { continue }
            slopes.append((g2 - g1) / (t2 - t1))
        }
        let lo = slopes.min()!, hi = slopes.max()!
        let predicted = 1 - (w.unchargedTime(drop: s.py - s.topY, climb: 0)!
                             - w.fullChargeTime(drop: s.py - s.topY, climb: 0)!) / w.chargeTime
        print(String(format: "RELEASE: G' sampled %.6f…%.6f · predicted %.6f", lo, hi, predicted))
        XCTAssertEqual(hi - lo, 0, accuracy: 1e-9, "G is not affine in τ — the solver's premise is gone")
        XCTAssertEqual(lo, predicted, accuracy: 1e-9)
        XCTAssertLessThan(predicted, 0,
                          "a is expected negative at this tuning: holding longer lands EARLIER")
    }

    /// Past the charge ceiling the slope must be exactly 1 — extra time buys travel, not charge.
    func testTheSaturatedBranchHasUnitSlope() {
        let s = Shot()
        let tauFull = (w.chargeCeiling - s.cNow) * w.chargeTime
        guard let g1 = impactTime(s, tau: tauFull + 0.5),
              let g2 = impactTime(s, tau: tauFull + 1.5) else { return XCTFail("no impact time") }
        XCTAssertEqual(g2 - g1, 1.0, accuracy: 1e-9)
    }

    // MARK: - Agreement with an independent integrator

    /// **Construct, then ask.** Release at the solver's τ, integrate the shot with RK4, and require
    /// the payload to actually be on the target — with nothing from `Interception` deciding where the
    /// payload goes.
    func testReleasingAtTheSolvedTimeActuallyHits() {
        var checked = 0, worst = 0.0
        for tv in stride(from: -9.0, through: 4.0, by: 1.5) {
            for tx in stride(from: 26.0, through: 46.0, by: 4.0) {
                let s = Shot(tx: tx, tv: tv)
                let win = releaseWindow(s)
                guard win.valid.item(Bool.self) else { continue }
                let tau = Double((win.lo + win.hi).item(Float.self)) / 2
                guard tau >= 0 else { continue }

                // Fly the pigeon forward to the release moment, charge accordingly.
                let c = min(w.chargeCeiling, s.cNow + tau / w.chargeTime)
                let px = s.px + s.vx * tau
                guard let T = w.flightTime(drop: s.py - s.topY, climb: s.vy, charge: c),
                      let u = w.releaseVelocity(flightTime: T, drop: s.py - s.topY) else { continue }

                // RK4 decides the landing, independently of every formula above.
                guard let hit = rk4.impact(x0: px, y0: s.py, vx0: s.vx, u0: u, plane: s.topY)
                else { XCTFail("RK4 found no impact at tv=\(tv) tx=\(tx)"); continue }

                let targetAt = s.tx + tv * (tau + hit.time)
                let miss = abs(hit.x - targetAt)
                worst = max(worst, miss)
                XCTAssertLessThan(miss, s.r,
                                  "released at the solved τ=\(tau) and missed by \(miss) m "
                                  + "(tv=\(tv), tx=\(tx))")
                checked += 1
            }
        }
        print("RELEASE: \(checked) solved shots, worst miss \(worst) m against r=3.0")
        XCTAssertGreaterThan(checked, 20)
    }

    /// The window is a *set*: every τ inside hits, every τ outside misses.
    func testEveryReleaseTimeInsideTheWindowHits() {
        let s = Shot()
        let win = releaseWindow(s)
        XCTAssertTrue(win.valid.item(Bool.self))
        let lo = Double(win.lo.item(Float.self)), hi = Double(win.hi.item(Float.self))
        XCTAssertGreaterThan(hi - lo, 0.01, "a window this narrow is not usable by a human")

        var inside = 0, outside = 0
        for i in 0...600 {
            let tau = max(0, lo - 0.4) + (hi + 0.4 - max(0, lo - 0.4)) * Double(i) / 600
            let c = min(w.chargeCeiling, s.cNow + tau / w.chargeTime)
            guard let T = w.flightTime(drop: s.py - s.topY, climb: s.vy, charge: c) else { continue }
            let impactX = s.px + s.vx * (tau + T)
            let targetAt = s.tx + s.tv * (tau + T)
            let miss = abs(impactX - targetAt)

            if tau > lo + 1e-3 && tau < hi - 1e-3 {
                XCTAssertLessThanOrEqual(miss, s.r + 1e-3, "τ=\(tau) is inside the window but misses")
                inside += 1
            } else if tau < lo - 1e-3 || tau > hi + 1e-3 {
                XCTAssertGreaterThanOrEqual(miss, s.r - 1e-3, "τ=\(tau) is outside the window but hits")
                outside += 1
            }
        }
        print("RELEASE: set equality — \(inside) inside, \(outside) outside")
        XCTAssertGreaterThan(inside, 20)
        XCTAssertGreaterThan(outside, 20)
    }

    // MARK: - It differs from the momentary answer, which is the entire point

    /// If the time-aware solver agreed with the instantaneous one, none of this would be worth
    /// building. Show they disagree, and that the instantaneous answer is the wrong one.
    func testTheMomentaryAnswerWouldHaveMissed() {
        var disagreements = 0, momentaryMisses = 0
        for tv in stride(from: -9.0, through: 2.0, by: 1.0) {
            let s = Shot(tv: tv)
            let timed = releaseWindow(s)
            let momentary = Interception.window(
                pigeonX: MLXArray(Float(s.px)), pigeonY: MLXArray(Float(s.py)),
                forwardSpeed: MLXArray(Float(s.vx)), climb: MLXArray(Float(s.vy)),
                targetX: MLXArray(Float(s.tx)), targetSpeed: MLXArray(Float(s.tv)),
                targetTopY: MLXArray(Float(s.topY)), radius: MLXArray(Float(s.r)), in: w)
            guard timed.valid.item(Bool.self), momentary.valid.item(Bool.self) else { continue }

            // What the OLD pilot did: take the momentary midpoint charge, hold until it arrives,
            // then release — by which time the world has moved.
            let cWanted = Double((momentary.lo + momentary.hi).item(Float.self)) / 2
            let tauNaive = max(0, (cWanted - s.cNow) * w.chargeTime)
            guard let T = w.flightTime(drop: s.py - s.topY, climb: s.vy, charge: cWanted) else { continue }
            let naiveMiss = abs((s.px + s.vx * (tauNaive + T)) - (s.tx + s.tv * (tauNaive + T)))

            // What the new one does.
            let tauGood = Double((timed.lo + timed.hi).item(Float.self)) / 2
            let cGood = min(w.chargeCeiling, s.cNow + tauGood / w.chargeTime)
            guard let Tg = w.flightTime(drop: s.py - s.topY, climb: s.vy, charge: cGood) else { continue }
            let goodMiss = abs((s.px + s.vx * (tauGood + Tg)) - (s.tx + s.tv * (tauGood + Tg)))

            if abs(naiveMiss - goodMiss) > 0.5 { disagreements += 1 }
            if naiveMiss > s.r { momentaryMisses += 1 }
            XCTAssertLessThan(goodMiss, s.r + 1e-3, "the time-aware solution missed at tv=\(tv)")
        }
        print("RELEASE: momentary answer missed outright in \(momentaryMisses) cases; "
              + "\(disagreements) material disagreements")
        XCTAssertGreaterThan(momentaryMisses, 0,
                             "the momentary solver hit every case, so the time-aware one is solving "
                             + "a problem nobody had — check the scenario, not the solver")
    }

    // MARK: - Degenerate cases

    func testCoMovingIsAllOrNothing() {
        var aligned = Shot(tv: 12.0); aligned.tx = 1.0
        XCTAssertTrue(releaseWindow(aligned).valid.item(Bool.self))
        var away = Shot(tv: 12.0); away.tx = 40.0
        XCTAssertFalse(releaseWindow(away).valid.item(Bool.self))
    }

    func testATargetBehindAndRecedingIsRefused() {
        XCTAssertFalse(releaseWindow(Shot(tx: -40.0, tv: -9.0)).valid.item(Bool.self))
    }

    /// Already fully charged: there is no ramping branch left, only the saturated one.
    func testAnAlreadyFullChargeStillSolves() {
        var s = Shot(); s.cNow = w.chargeCeiling
        let win = releaseWindow(s)
        XCTAssertTrue(win.valid.item(Bool.self), "a fully charged pigeon can still time a release")
        XCTAssertGreaterThanOrEqual(Double(win.lo.item(Float.self)), -1e-6)
    }
}

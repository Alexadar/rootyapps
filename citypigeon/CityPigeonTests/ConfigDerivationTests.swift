import XCTest
@testable import CityPigeon

/// The arithmetic somebody would otherwise do in their head and get wrong.
///
/// froggo2's `ConfigConsistencyTests` exists because its first draft shipped rooftops wider than the
/// maximum jump — a solver provably right about an impossible world. Same job here.
final class ConfigDerivationTests: XCTestCase {

    let w = WorldConfig.shipping

    /// Not an assertion — a report. These are the numbers the design is arguing about.
    func testReportTheTuning() {
        print("""

        ── City Pigeon tuning ─────────────────────────────────────
        cruise drop time      \(f(w.cruiseDropTime)) s
        max charge speed V    \(f(w.maxChargeSpeed)) m/s      (derived from ratio \(w.fullChargeTimeRatio))
        charge authority      \(f(w.chargeAuthority)) m       (\(f(w.chargeAuthority / (2 * w.car.halfLength))) car lengths)
        V / (g · t_charge)    \(f(w.maxChargeSpeed / (w.gravity * w.chargeTime)))
        G′ (constant)         \(f(w.impactTimeSlope))   impact time per second of hold
        effective authority   \(f(w.effectiveAuthorityPerSecond)) m/s of hold
        min fair window       \(f(w.minFairWindow)) s   (derived: react + charge + cooldown)
        hit radius, car       \(f(w.hitRadius(w.car))) m
        hit radius, pedestrian\(f(w.hitRadius(w.pedestrian))) m
        ───────────────────────────────────────────────────────────
        """)
    }

    /// The charge meter must visibly do something. This is the exact failure mode that ruled out
    /// mass-as-charge, so it would be absurd not to assert it of the mechanism that replaced it.
    func testChargeMeterHasRealAuthority() {
        let carLengths = w.chargeAuthority / (2 * w.car.halfLength)
        XCTAssertGreaterThan(carLengths, 3.0,
                             "charge swings the impact point only \(w.chargeAuthority) m — under three "
                             + "car lengths, the meter will read as decorative")
    }

    /// `H > 0` strictly, for every target kind, from the lowest the player can fly.
    /// The whole closed form rests on this and it is one careless altitude edit from being false.
    func testReleaseAltitudeIsStrictlyAboveEveryTarget() {
        let tallest = max(w.car.topY, w.pedestrian.topY)
        XCTAssertGreaterThan(w.altitudeRange.lowerBound - tallest, 1.0,
                             "the pigeon can fly within 1 m of the tallest target's impact plane; "
                             + "H → 0 is where monotonicity stops being strict")
    }

    /// Every envelope corner carries sign(v_x).
    func testForwardSpeedIsStrictlyPositive() {
        XCTAssertGreaterThan(w.forwardSpeedRange.lowerBound, 0)
        XCTAssertGreaterThan(w.guaranteeSpeedRange.lowerBound, 0)
    }

    /// The guarantee band must sit inside the band the player can actually occupy.
    func testGuaranteeBoxIsInsideTheStateBox() {
        XCTAssertTrue(w.altitudeRange.contains(w.guaranteeAltitudeRange.lowerBound))
        XCTAssertTrue(w.altitudeRange.contains(w.guaranteeAltitudeRange.upperBound))
        XCTAssertTrue(w.forwardSpeedRange.contains(w.guaranteeSpeedRange.lowerBound))
        XCTAssertTrue(w.forwardSpeedRange.contains(w.guaranteeSpeedRange.upperBound))
    }

    /// **The one that matters.**
    ///
    /// The guaranteed set is an INTERSECTION over pigeon states, so its endpoints sit at the
    /// *opposite* corners from the hull's. `A` is the largest lead still reachable at full charge;
    /// `B` is the smallest lead reachable at zero charge. `[A, B]` is what every spawn guarantee is
    /// built on, and it is empty for any box that is too wide — which is exactly what happened at
    /// the first tuning attempt.
    func testGuaranteedCoreIsNonEmptyWithMarginForTheHitRadius() {
        for (name, p) in [("car", w.car), ("pedestrian", w.pedestrian)] {
            guard let core = leadCore(p) else {
                return XCTFail("\(name): guaranteed core is EMPTY — no lead is reachable from every "
                               + "state in the guarantee band")
            }
            let r = w.hitRadius(p)
            print("core[\(name)] = [\(f(core.lowerBound)), \(f(core.upperBound))] "
                  + "width \(f(core.upperBound - core.lowerBound)) m, 2r = \(f(2 * r)) m")
            XCTAssertGreaterThan(core.upperBound - core.lowerBound, 2 * r,
                                 "\(name): the core is narrower than one target, so a spawn placed "
                                 + "inside it is not reliably hittable")
        }
    }

    /// The hull is what the camera has to be able to show.
    func testTheImpactPointIsAlwaysOnScreen() {
        for (name, p) in [("car", w.car), ("pedestrian", w.pedestrian)] {
            let hull = leadHull(p)
            print("hull[\(name)] = [\(f(hull.lowerBound)), \(f(hull.upperBound))] m")
            XCTAssertLessThan(hull.upperBound + w.hitRadius(p), w.visibleAheadOfPigeon,
                              "\(name): the predicted impact point can land off the front of the "
                              + "screen, so the reticle would leave the frame")
        }
    }

    /// The band itself is `Spawn`'s to compute and `SpawnOracleTests`' to verify — this only
    /// asserts the config admits one at all. An earlier version of this test re-derived the algebra
    /// here and promptly went stale when the fairness model was split into in-window and
    /// pre-visibility halves, passing while the real spawner had no admissible speeds left.
    /// Two copies of a derivation is one copy too many.
    func testEveryTargetKindHasSomeAdmissibleSpeed() {
        for (name, p) in [("car", w.car), ("pedestrian", w.pedestrian)] {
            guard let band = Spawn.admissibleSpeeds(p, in: w) else {
                return XCTFail("\(name): no target speed produces a fair, on-screen approach")
            }
            print("\(name): admissible \(f(band.lowerBound))…\(f(band.upperBound)) m/s "
                  + "(fairness ≤ \(f(Spawn.maxClosingSpeed(p, in: w))) m/s, "
                  + "camera ≤ \(f(Spawn.maxVisibleClosingSpeed(p, in: w))) m/s)")
            XCTAssertGreaterThan(band.upperBound - band.lowerBound, 1.0,
                                 "\(name): the band is so narrow that all traffic moves at one speed")
        }
    }

    /// `G′` — impact time per second of hold — must stay **constant** across the charge range.
    ///
    /// That constancy is not cosmetic: it is what makes `Interception.releaseWindow` a closed-form
    /// inversion instead of a search. If someone reparametrises the charge curve so that charge is no
    /// longer linear in flight time, this fails here rather than silently degrading the solver into
    /// returning confident wrong answers.
    func testImpactTimeSlopeIsConstantAcrossTheChargeRange() {
        let H = w.cruiseAltitude - w.car.topY
        var slopes: [Double] = []
        for i in 0..<40 {
            let c1 = Double(i) / 40, c2 = Double(i + 1) / 40
            guard let t1 = w.flightTime(drop: H, climb: 0, charge: c1),
                  let t2 = w.flightTime(drop: H, climb: 0, charge: c2) else { continue }
            // dG/dτ = 1 + dT/dc · dc/dτ, and dc/dτ = 1/chargeTime.
            slopes.append(1 + ((t2 - t1) / (c2 - c1)) / w.chargeTime)
        }
        let lo = slopes.min()!, hi = slopes.max()!
        print("\(f(lo))…\(f(hi)) sampled G′ · \(f(w.impactTimeSlope)) derived")
        XCTAssertEqual(hi - lo, 0, accuracy: 1e-9, "G′ is not constant — releaseWindow's premise is gone")
        XCTAssertEqual(lo, w.impactTimeSlope, accuracy: 1e-9)
    }

    /// The sign decides how holding *feels*, and a silent flip would invert the control.
    func testHoldingLongerBringsTheImpactForward() {
        XCTAssertLessThan(w.impactTimeSlope, 0,
                          "at this tuning holding longer lands the payload EARLIER; if this flips, "
                          + "the charge meter's relationship to timing has inverted")
        XCTAssertLessThan(w.effectiveAuthorityPerSecond, 0)
    }

    // MARK: - Helpers

    private func f(_ d: Double) -> String { String(format: "%.3f", d) }

    /// Outer hull: the union over the FULL state box — what some state can reach. Culling, camera.
    private func leadHull(_ p: TargetProfile) -> ClosedRange<Double> {
        let lo = lead(alt: w.altitudeRange.lowerBound, vx: w.forwardSpeedRange.lowerBound,
                      vy: w.climbRateRange.lowerBound, c: w.chargeCeiling, p)
        let hi = lead(alt: w.altitudeRange.upperBound, vx: w.forwardSpeedRange.upperBound,
                      vy: w.climbRateRange.upperBound, c: w.chargeFloor, p)
        return lo...hi
    }

    /// Inner core: the intersection over the GUARANTEE box — what every state can reach.
    /// Note the corners are the opposite ones from the hull's.
    private func leadCore(_ p: TargetProfile) -> ClosedRange<Double>? {
        let a = lead(alt: w.guaranteeAltitudeRange.upperBound, vx: w.guaranteeSpeedRange.upperBound,
                     vy: w.guaranteeClimbRange.upperBound, c: w.chargeCeiling, p)
        let b = lead(alt: w.guaranteeAltitudeRange.lowerBound, vx: w.guaranteeSpeedRange.lowerBound,
                     vy: w.guaranteeClimbRange.lowerBound, c: w.chargeFloor, p)
        return b > a ? a...b : nil
    }

    private func lead(alt: Double, vx: Double, vy: Double, c: Double, _ p: TargetProfile) -> Double {
        let H = alt - p.topY
        return vx * (w.flightTime(drop: H, climb: vy, charge: c) ?? .nan)
    }

}

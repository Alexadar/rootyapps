import XCTest
import MLX
@testable import CityPigeon

/// The charge a payload actually leaves with.
///
/// This file exists because v1 shipped with `usedCharge` pinned to `chargeFloor` on every single
/// shot — the release-edge capture read `w.charge` *after* the same step had zeroed it. The charge
/// meter moved, the autopilot solved for a charge, and none of it reached the payload.
///
/// Nothing caught it for an entire build. `testTheAutopilotReliablyScores` asserted `score > 0`, and
/// a minimum-charge drop still lands often enough to score, so a game with a dead charge meter was
/// indistinguishable from a working one at the level anything was checked. **An end-to-end test that
/// only asserts the loop closes cannot see a control that has been disconnected inside it.**
final class ChargeReleaseTests: XCTestCase {

    let w = WorldConfig.shipping

    /// One shot's release state, plus the street landing derived from it.
    ///
    /// The landing is computed from the captured release state rather than read from `payImpactX`,
    /// deliberately: `payImpactX` uses the flight time to whatever the payload actually strikes, so
    /// a shot that clips a car roof and one that reaches the road are not comparable. Deriving from
    /// `(y0, u0, vx0)` isolates what the *charge* did.
    private struct Shot {
        var held: Float, mass: Float, u0: Float, x0: Float, y0: Float, vx0: Float
        /// Lead from the release point to the street, the quantity `chargeAuthority` predicts.
        var lead: Double = 0
        /// Absolute landing position in world space — what the player actually sees hit the road.
        var landing: Double { Double(x0) + lead }
    }

    private func fire(holdFrames: Int) -> Shot {
        var world = World(batch: 1, config: w, seed: 5)
        let hold = Intent(moveX: MLXArray.zeros([1]), moveY: MLXArray.zeros([1]), hold: MLXArray([true]))
        for _ in 0..<holdFrames { Step.advance(&world, intent: hold) }
        let heldBeforeRelease = world.charge.item(Float.self)

        Step.advance(&world, intent: .idle(batch: 1))       // falling edge — the shot
        world.evaluate()

        // Exactly one payload should be live; find it without assuming a slot.
        let alive = world.payAlive.asArray(Bool.self)
        guard let slot = alive.firstIndex(of: true) else {
            return Shot(held: heldBeforeRelease, mass: .nan, u0: .nan, x0: .nan, y0: .nan, vx0: .nan)
        }
        var shot = Shot(held: heldBeforeRelease,
                        mass: world.payMass.asArray(Float.self)[slot],
                        u0: world.payU0.asArray(Float.self)[slot],
                        x0: world.payX0.asArray(Float.self)[slot],
                        y0: world.payY0.asArray(Float.self)[slot],
                        vx0: world.payVX0.asArray(Float.self)[slot])
        let T = w.flightTime(drop: Double(shot.y0), releaseVelocity: Double(shot.u0)) ?? .nan
        shot.lead = Double(shot.vx0) * T
        return shot
    }

    /// **The regression.** What the player held is what the payload leaves with.
    func testThePayloadLeavesWithTheChargeThatWasHeld() {
        for frames in [6, 12, 24, 40, 54] {
            let s = fire(holdFrames: frames)
            let expected = min(max(s.held, Float(w.chargeFloor)), Float(w.chargeCeiling))
            XCTAssertEqual(s.mass, expected, accuracy: 1e-5,
                           "held \(s.held) after \(frames) frames but the payload carries \(s.mass) — "
                           + "the release edge is not capturing the charge")
        }
    }

    /// The bug's signature, pinned so it cannot come back in a different disguise: if the capture
    /// ever breaks again, every hold length collapses onto the same payload.
    func testDifferentHoldsProduceDifferentShots() {
        let short = fire(holdFrames: 8)
        let long = fire(holdFrames: 50)

        XCTAssertNotEqual(short.mass, long.mass, accuracy: 0.05,
                          "an 8-frame hold and a 50-frame hold produced the same payload mass — "
                          + "this is exactly how the v1 bug looked")
        XCTAssertLessThan(long.u0, short.u0,
                          "more charge must mean a more downward release velocity")
        XCTAssertLessThan(long.lead, short.lead,
                          "more charge must land the payload SHORTER relative to the release point — "
                          + "this is the charge meter's entire promise to the player")
    }

    /// The charge must actually reach the top of its travel, or the ceiling is unreachable and the
    /// upper half of the meter is a lie.
    func testAFullHoldReachesTheChargeCeiling() {
        let full = fire(holdFrames: Int((w.chargeTime / w.dt).rounded(.up)) + 4)
        XCTAssertEqual(full.mass, Float(w.chargeCeiling), accuracy: 1e-4)
    }

    /// A tap — pressed and released inside one frame pair — must still fire, at the floor.
    func testATapFiresAtTheFloorRatherThanNotAtAll() {
        let tap = fire(holdFrames: 1)
        XCTAssertEqual(tap.mass, Float(w.chargeFloor), accuracy: 0.02,
                       "a tap should produce the longest, flattest shot, not no shot")
    }

    /// The span the meter commands **from a fixed release point** — `chargeAuthority` observed
    /// end-to-end through the engine rather than derived from the same formula that defines it.
    func testTheMeterCommandsTheAuthorityTheConfigClaims() {
        let short = fire(holdFrames: 2)
        let long = fire(holdFrames: Int((w.chargeTime / w.dt).rounded(.up)) + 4)
        let observed = short.lead - long.lead
        print("CHARGE: lead authority \(observed) m · config claims \(w.chargeAuthority) m")
        XCTAssertEqual(observed, w.chargeAuthority, accuracy: w.chargeAuthority * 0.12,
                       "the lead moves \(observed) m across the meter but the config derives "
                       + "\(w.chargeAuthority) m — the model and the engine disagree")
    }

    /// **The fact that motivates time-aware targeting, measured rather than argued.**
    ///
    /// `chargeAuthority` is a *momentary* quantity: how much the lead changes if you could switch
    /// charge instantly. You cannot. Holding for the full 0.9 s also flies you ~11 m forward, and
    /// that travel pushes the landing point the opposite way — so the two effects very nearly
    /// cancel and the **effective** authority the player experiences is a small fraction of the
    /// nominal one.
    ///
    /// This is the same `a = 1 − span/chargeTime ≈ −0.27` seen from the outside: absolute landing
    /// position moves by `v_x · a · Δτ`, not by `v_x · span`.
    func testHoldingCarriesYouForwardAndEatsMostOfTheAuthority() {
        let short = fire(holdFrames: 2)
        let long = fire(holdFrames: Int((w.chargeTime / w.dt).rounded(.up)) + 4)

        let nominal = short.lead - long.lead                    // fixed-release-point authority
        let effective = short.landing - long.landing            // what actually happens in play
        let travelled = Double(long.x0 - short.x0)

        print(String(format: "CHARGE: nominal %.2f m · travelled %.2f m during the hold · effective %.2f m",
                     nominal, travelled, effective))

        XCTAssertGreaterThan(travelled, 8,
                             "the pigeon should cover ~11 m while charging fully")
        XCTAssertLessThan(abs(effective), nominal * 0.45,
                          "the hold's forward travel should cancel most of the nominal authority; "
                          + "if it stops doing so, `a` has changed sign or magnitude and the "
                          + "time-aware solver's affine model needs revisiting")

        // Direction: `a < 0` means a longer hold lands at a SMALLER x, so short-minus-long is
        // positive. (The first version of this assertion had the sign inverted while the prose above
        // it was right — worth keeping as a reminder that "backward" and "negative" are not the same
        // claim until you say which difference you are taking.)
        XCTAssertGreaterThan(effective, 0,
                             "a = 1 − span/chargeTime is negative at this tuning, so holding longer "
                             + "must land the payload at a smaller x")

        // The measured gap is smaller than v_x·|a|·Δτ would suggest, and the reason is structural:
        // this hold straddles the charge ceiling. Past `τ_full` the extra frames buy travel but no
        // charge, which is exactly the saturated branch the release-time solver has to model.
        let tauFull = (w.chargeCeiling - Double(short.held)) * w.chargeTime
        XCTAssertLessThan(tauFull, Double(long.held) * w.chargeTime + w.chargeTime,
                          "expected this hold to reach the charge ceiling")
    }
}

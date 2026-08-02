import Testing
import Foundation
@testable import PipeKit

/// Calc #11 — simple pipe offset (set · travel · run).
///
/// ORACLES:
///  • PUBLISHED — the pipe-trades fitting-multiplier tables, quoted to 3–4 decimals:
///    travel (csc θ) 45° = 1.414, 60° = 1.155, 30° = 2.000, 22½° = 2.613, 11¼° = 5.126;
///    run (cot θ) 45° = 1.000, 22½° = 2.414, 11¼° = 5.027. These constants are printed identically
///    across pipefitting references and on the fitting-multiplier cards sold in the trade.
///  • IDENTITY — those published constants ARE `1/sin θ` and `cos θ/sin θ`; asserted against the
///    closed form at 1e-9 so a re-transcribed table cannot silently move the maths.
///  • INVARIANT — right-triangle closure, travel↔set round-trips, monotonicity as the angle narrows.
@Suite struct PipeOffsetOracle {

    @Test func publishedTravelMultipliers() {
        // oracle: published fitting-multiplier table (3-decimal precision)
        #expect(abs(PipeOffset.travelMultiplier(fittingAngleDeg: 45) - 1.414) < 0.0005)
        #expect(abs(PipeOffset.travelMultiplier(fittingAngleDeg: 60) - 1.155) < 0.0005)
        #expect(abs(PipeOffset.travelMultiplier(fittingAngleDeg: 30) - 2.000) < 1e-12)   // exact: csc 30 = 2
        #expect(abs(PipeOffset.travelMultiplier(fittingAngleDeg: 22.5) - 2.613) < 0.0005)
        #expect(abs(PipeOffset.travelMultiplier(fittingAngleDeg: 11.25) - 5.126) < 0.0005)
    }

    @Test func publishedRunMultipliers() {
        // oracle: published fitting-multiplier table (cot θ column)
        #expect(abs(PipeOffset.runMultiplier(fittingAngleDeg: 45) - 1.000) < 1e-12)      // exact: cot 45 = 1
        #expect(abs(PipeOffset.runMultiplier(fittingAngleDeg: 22.5) - 2.414) < 0.0005)
        #expect(abs(PipeOffset.runMultiplier(fittingAngleDeg: 11.25) - 5.027) < 0.0005)
        #expect(abs(PipeOffset.runMultiplier(fittingAngleDeg: 60) - 0.577) < 0.0005)
    }

    /// Identity anchors — the published constants above, re-derived from the closed form. Independent
    /// of the transcribed table, so the two oracles corroborate rather than repeat each other.
    @Test func multipliersAreCscAndCot() {
        let d2r = Double.pi / 180
        for θ in [11.25, 22.5, 30.0, 45.0, 60.0, 90.0] {
            #expect(abs(PipeOffset.travelMultiplier(fittingAngleDeg: θ) - 1 / sin(θ * d2r)) < 1e-9)
            #expect(abs(PipeOffset.runMultiplier(fittingAngleDeg: θ) - cos(θ * d2r) / sin(θ * d2r)) < 1e-9)
        }
        #expect(abs(PipeOffset.travelMultiplier(fittingAngleDeg: 45) - 2.0.squareRoot()) < 1e-12)  // √2
    }

    @Test func rightTriangleCloses() {
        // A 45° offset of 10" set: travel is the hypotenuse of set and run.
        let set = 10.0, θ = 45.0
        let travel = PipeOffset.travelIn(setIn: set, fittingAngleDeg: θ)
        let run = PipeOffset.runIn(setIn: set, fittingAngleDeg: θ)
        #expect(abs(run - 10) < 1e-9)                                   // cot 45 = 1 → run == set
        #expect(abs(travel * travel - (set * set + run * run)) < 1e-9)  // Pythagoras
        #expect(abs(travel - 14.1421356) < 1e-6)                        // 10 × √2
    }

    @Test func inverseAndRoundTrip() {
        // Angle recovered from set and run.
        #expect(abs(PipeOffset.fittingAngleDeg(setIn: 10, runIn: 10) - 45) < 1e-9)
        #expect(abs(PipeOffset.fittingAngleDeg(setIn: 10, runIn: 0) - 90) < 1e-9)   // square offset
        #expect(abs(PipeOffset.fittingAngleDeg(setIn: 3, runIn: 4) - 36.8698976) < 1e-6)  // atan(3/4)
        // travel → set → travel survives the trip at every standard fitting.
        for θ in [11.25, 22.5, 30.0, 45.0, 60.0] {
            let travel = PipeOffset.travelIn(setIn: 8.5, fittingAngleDeg: θ)
            #expect(abs(PipeOffset.setIn(travelIn: travel, fittingAngleDeg: θ) - 8.5) < 1e-9)
        }
    }

    @Test func narrowerAngleCostsMoreTravelAndRun() {
        let angles = [60.0, 45.0, 30.0, 22.5, 11.25]
        for (a, b) in zip(angles, angles.dropFirst()) {
            #expect(PipeOffset.travelMultiplier(fittingAngleDeg: b) > PipeOffset.travelMultiplier(fittingAngleDeg: a))
            #expect(PipeOffset.runMultiplier(fittingAngleDeg: b) > PipeOffset.runMultiplier(fittingAngleDeg: a))
        }
    }

    @Test func guardsNoCrash() {
        #expect(PipeOffset.travelMultiplier(fittingAngleDeg: 0) == 0)      // 0° → 0, no divide by sin 0
        #expect(PipeOffset.travelMultiplier(fittingAngleDeg: -45) == 0)    // negative fitting → 0
        #expect(PipeOffset.travelMultiplier(fittingAngleDeg: 91) == 0)     // beyond square → 0
        #expect(PipeOffset.runMultiplier(fittingAngleDeg: 90) == 0)        // square offset consumes no run
        #expect(PipeOffset.travelIn(setIn: 0, fittingAngleDeg: 45) == 0)   // no set → no travel
        #expect(PipeOffset.fittingAngleDeg(setIn: 0, runIn: 0) == 0)       // nothing to solve → 0, not NaN
        #expect(PipeOffset.setIn(travelIn: 10, fittingAngleDeg: 0) == 0)
    }
}

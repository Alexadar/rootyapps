import Testing
import Foundation
@testable import PipeKit

/// Calc #12 — rolling offset (set + roll → true offset, travel, run, roll angle).
///
/// ORACLES:
///  • IDENTITY — the true offset is the Pythagorean hypotenuse of set and roll; asserted on the
///    hand-verifiable 3-4-5 and 6-8-10 triangles, and the roll angle is `atan(roll ⁄ set)`.
///  • INVARIANT — with roll = 0 a rolling offset must reduce *exactly* to the simple offset of
///    Calc #11; with set = 0 it is a pure 90° roll. Travel/run stay consistent with the same
///    published multipliers, so this composes on top of an already-cited calc rather than
///    introducing new constants.
@Suite struct RollingOffsetOracle {

    @Test func trueOffsetIsTheHypotenuse() {
        #expect(abs(RollingOffset.trueOffsetIn(setIn: 3, rollIn: 4) - 5) < 1e-12)     // 3-4-5
        #expect(abs(RollingOffset.trueOffsetIn(setIn: 6, rollIn: 8) - 10) < 1e-12)    // 6-8-10
        #expect(abs(RollingOffset.trueOffsetIn(setIn: 5, rollIn: 12) - 13) < 1e-12)   // 5-12-13
    }

    @Test func rollAngleIsAtanRollOverSet() {
        #expect(abs(RollingOffset.rollAngleDeg(setIn: 3, rollIn: 4) - 53.1301024) < 1e-6)  // atan(4/3)
        #expect(abs(RollingOffset.rollAngleDeg(setIn: 10, rollIn: 10) - 45) < 1e-9)
        #expect(RollingOffset.rollAngleDeg(setIn: 10, rollIn: 0) == 0)                     // plain vertical
        #expect(abs(RollingOffset.rollAngleDeg(setIn: 0, rollIn: 10) - 90) < 1e-9)         // pure roll
    }

    /// The invariant that matters most: no roll ⇒ this IS Calc #11, to the last bit.
    @Test func reducesToSimpleOffsetWhenRollIsZero() {
        for θ in [11.25, 22.5, 30.0, 45.0, 60.0] {
            let r = RollingOffset.solve(setIn: 12, rollIn: 0, fittingAngleDeg: θ)
            #expect(abs(r.trueOffsetIn - 12) < 1e-12)
            #expect(abs(r.travelIn - PipeOffset.travelIn(setIn: 12, fittingAngleDeg: θ)) < 1e-12)
            #expect(abs(r.runIn - PipeOffset.runIn(setIn: 12, fittingAngleDeg: θ)) < 1e-12)
            #expect(r.rollAngleDeg == 0)
        }
    }

    @Test func solveComposesTheCitedMultipliers() {
        // 6" set, 8" roll → 10" true offset; at 45° travel = 10 × 1.41421356, run = 10 × 1.
        let r = RollingOffset.solve(setIn: 6, rollIn: 8, fittingAngleDeg: 45)
        #expect(abs(r.trueOffsetIn - 10) < 1e-12)
        #expect(abs(r.travelIn - 14.1421356) < 1e-6)          // 10 × √2
        #expect(abs(r.runIn - 10) < 1e-9)                     // cot 45 = 1
        #expect(abs(r.rollAngleDeg - 53.1301024) < 1e-6)      // atan(8/6)
        // Right-triangle closure still holds in the tilted plane.
        #expect(abs(r.travelIn * r.travelIn - (r.trueOffsetIn * r.trueOffsetIn + r.runIn * r.runIn)) < 1e-9)
    }

    @Test func rollAngleDoesNotChangeTravel() {
        // Same true offset reached by different set/roll splits ⇒ identical travel and run.
        let a = RollingOffset.solve(setIn: 10, rollIn: 0, fittingAngleDeg: 22.5)
        let b = RollingOffset.solve(setIn: 6, rollIn: 8, fittingAngleDeg: 22.5)
        #expect(abs(a.travelIn - b.travelIn) < 1e-9)
        #expect(abs(a.runIn - b.runIn) < 1e-9)
        #expect(a.rollAngleDeg != b.rollAngleDeg)             // …but the fitter rolls them differently
    }

    @Test func guardsNoCrash() {
        let z = RollingOffset.solve(setIn: 0, rollIn: 0, fittingAngleDeg: 45)
        #expect(z.trueOffsetIn == 0)
        #expect(z.travelIn == 0)
        #expect(z.rollAngleDeg == 0)                                   // nothing to solve → 0, not NaN
        let bad = RollingOffset.solve(setIn: 6, rollIn: 8, fittingAngleDeg: 0)
        #expect(bad.trueOffsetIn == 10)                                // geometry still valid…
        #expect(bad.travelIn == 0)                                     // …but 0° fitting yields no travel
        #expect(bad.runIn == 0)
    }
}

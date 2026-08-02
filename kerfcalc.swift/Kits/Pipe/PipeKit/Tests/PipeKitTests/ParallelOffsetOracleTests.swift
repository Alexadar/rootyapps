import Testing
import Foundation
@testable import PipeKit

/// Calc #16 — parallel / multi-pipe offsets.
///
/// ORACLES:
///  • **TODO(oracle): the stagger formula is NOT cited.** `spacing · tan(θ⁄2)` is derived from the
///    geometry, not transcribed from a published pipefitting reference, and the layout convention it
///    assumes (which reference line the spacing is measured on) needs a source before any number here
///    is shown to a user. Until then this namespace stays out of the UI — see the note in
///    `ParallelOffset.swift`.
///  • INVARIANT — everything below is a property the derivation must satisfy regardless of which
///    convention turns out to be the cited one: vanishing at zero angle, linearity in spacing,
///    monotonicity in angle, and reduction to the already-cited single-pipe run of Calc #11.
///  • IDENTITY/DEFINITION — `spreadIn` is just `(count − 1) · spacing`; nothing to cite.
@Suite struct ParallelOffsetOracle {

    @Test func spreadIsDefinitional() {
        #expect(PipeOffset.travelMultiplier(fittingAngleDeg: 45) > 0)          // sanity: Kit linked
        #expect(abs(ParallelOffset.spreadIn(count: 4, spacingIn: 6) - 18) < 1e-12)   // 3 gaps × 6"
        #expect(ParallelOffset.spreadIn(count: 1, spacingIn: 6) == 0)                // one pipe, no spread
        #expect(ParallelOffset.spreadIn(count: 0, spacingIn: 6) == 0)
    }

    @Test func staggerVanishesAndSaturates() {
        // No turn ⇒ nothing to stagger; a square jog ⇒ stagger equals the spacing.
        #expect(ParallelOffset.staggerIn(spacingIn: 6, fittingAngleDeg: 0) == 0)
        #expect(abs(ParallelOffset.staggerIn(spacingIn: 6, fittingAngleDeg: 90) - 6) < 1e-9)  // tan 45 = 1
        // Shallow angles stagger very little.
        #expect(ParallelOffset.staggerIn(spacingIn: 6, fittingAngleDeg: 11.25) < 0.6)
    }

    @Test func staggerIsLinearInSpacing() {
        let a = ParallelOffset.staggerIn(spacingIn: 6, fittingAngleDeg: 45)
        let b = ParallelOffset.staggerIn(spacingIn: 12, fittingAngleDeg: 45)
        #expect(abs(b - 2 * a) < 1e-12)
        #expect(abs(a - 6 * tan(22.5 * Double.pi / 180)) < 1e-12)   // = spacing · tan(θ/2)
    }

    @Test func staggerGrowsWithAngle() {
        let angles = [11.25, 22.5, 30.0, 45.0, 60.0, 90.0]
        for (a, b) in zip(angles, angles.dropFirst()) {
            #expect(ParallelOffset.staggerIn(spacingIn: 6, fittingAngleDeg: b)
                    > ParallelOffset.staggerIn(spacingIn: 6, fittingAngleDeg: a))
        }
    }

    @Test func bankReducesToTheCitedSinglePipeRun() {
        // One pipe ⇒ exactly Calc #11's run, no stagger term.
        for θ in [22.5, 45.0] {
            #expect(abs(ParallelOffset.bankRunIn(setIn: 10, spacingIn: 6, count: 1, fittingAngleDeg: θ)
                        - PipeOffset.runIn(setIn: 10, fittingAngleDeg: θ)) < 1e-12)
        }
        // Each extra pipe adds exactly one stagger.
        let one = ParallelOffset.bankRunIn(setIn: 10, spacingIn: 6, count: 1, fittingAngleDeg: 45)
        let three = ParallelOffset.bankRunIn(setIn: 10, spacingIn: 6, count: 3, fittingAngleDeg: 45)
        #expect(abs(three - one - 2 * ParallelOffset.staggerIn(spacingIn: 6, fittingAngleDeg: 45)) < 1e-12)
    }

    @Test func guardsNoCrash() {
        #expect(ParallelOffset.staggerIn(spacingIn: 0, fittingAngleDeg: 45) == 0)     // no spacing → 0
        #expect(ParallelOffset.staggerIn(spacingIn: -6, fittingAngleDeg: 45) == 0)    // negative → 0
        #expect(ParallelOffset.staggerIn(spacingIn: 6, fittingAngleDeg: 120) == 0)    // beyond square → 0
        #expect(ParallelOffset.staggerIn(spacingIn: 6, fittingAngleDeg: -45) == 0)
        #expect(ParallelOffset.bankRunIn(setIn: 0, spacingIn: 0, count: 0, fittingAngleDeg: 45) == 0)
    }
}

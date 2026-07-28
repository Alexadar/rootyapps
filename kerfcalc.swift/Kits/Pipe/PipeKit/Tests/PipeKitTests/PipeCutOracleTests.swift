import Testing
import Foundation
@testable import PipeKit

/// Calc #13 — cut length (centre-to-centre − two take-outs).
///
/// ORACLES:
///  • IDENTITY/DEFINITION — end-to-end is *defined* as the centre-to-centre dimension less each
///    fitting's take-out. There is no external number to cite and none is invented: the take-outs are
///    user-entered, so the only thing under test is the subtraction, its inverse, and its guards.
///  • NOT oracle-backed — take-out values themselves. They vary by manufacturer, material, pressure
///    class and joining method, and are deliberately not shipped as a table.
@Suite struct PipeCutOracle {

    @Test func definitionalSubtraction() {
        // 24" centre-to-centre between two fittings taking out 1½" each → 21" of pipe.
        #expect(abs(PipeCut.endToEndIn(centerToCenterIn: 24, takeoutAIn: 1.5, takeoutBIn: 1.5) - 21) < 1e-12)
        // Unequal take-outs (an elbow and a tee, say).
        #expect(abs(PipeCut.endToEndIn(centerToCenterIn: 36, takeoutAIn: 1.125, takeoutBIn: 2.25) - 32.625) < 1e-12)
        // No fittings → the whole dimension is pipe.
        #expect(abs(PipeCut.endToEndIn(centerToCenterIn: 18, takeoutAIn: 0, takeoutBIn: 0) - 18) < 1e-12)
    }

    @Test func inverseRoundTrip() {
        let c2c = 47.375, a = 1.4375, b = 2.0
        let e2e = PipeCut.endToEndIn(centerToCenterIn: c2c, takeoutAIn: a, takeoutBIn: b)
        #expect(abs(PipeCut.centerToCenterIn(endToEndIn: e2e, takeoutAIn: a, takeoutBIn: b) - c2c) < 1e-12)
    }

    @Test func collidingFittingsReadAsZeroNotNegative() {
        // Take-outs exceed the layout dimension — the fittings meet, there is no pipe to cut.
        #expect(PipeCut.endToEndIn(centerToCenterIn: 3, takeoutAIn: 2, takeoutBIn: 2) == 0)
        #expect(PipeCut.fittingsCollide(centerToCenterIn: 3, takeoutAIn: 2, takeoutBIn: 2))
        #expect(PipeCut.fittingsCollide(centerToCenterIn: 4, takeoutAIn: 2, takeoutBIn: 2))   // exactly touching
        #expect(!PipeCut.fittingsCollide(centerToCenterIn: 24, takeoutAIn: 1.5, takeoutBIn: 1.5))
    }

    @Test func guardsNoCrash() {
        #expect(PipeCut.endToEndIn(centerToCenterIn: 0, takeoutAIn: 0, takeoutBIn: 0) == 0)
        #expect(PipeCut.endToEndIn(centerToCenterIn: -10, takeoutAIn: 1, takeoutBIn: 1) == 0)  // negative → 0
        #expect(PipeCut.centerToCenterIn(endToEndIn: 0, takeoutAIn: 1.5, takeoutBIn: 1.5) == 3)
    }
}

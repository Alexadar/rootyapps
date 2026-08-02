import Testing
import Foundation
@testable import FramingKit

/// Calc #4 — right-angle / pitch.
///
/// ORACLES:
///  • IDENTITY — the 3-4-5 / 6-8-10 right triangles (Pythagoras); hand-verifiable.
///  • PUBLISHED — roof-pitch→angle tables: 4/12 = 18.43°, 6/12 = 26.57°, 8/12 = 33.69°, 12/12 = 45°.
///    (barntoolbox.com/roof-pitch-angles.htm; roofobservations.com — consistent across roofing refs.)
@Suite struct PitchOracle {

    @Test func pythagoreanIdentity() {
        #expect(abs(Pitch.diagonal(rise: 3, run: 4) - 5) < 1e-12)          // 3-4-5
        #expect(abs(Pitch.diagonal(rise: 6, run: 8) - 10) < 1e-12)         // 6-8-10
        #expect(abs(Pitch.leg(diagonal: 5, otherLeg: 3) - 4) < 1e-12)
        #expect(abs(Pitch.diagonal(rise: 5, run: 12) - 13) < 1e-12)        // 5-12-13
    }

    @Test func angles345() {
        #expect(abs(Pitch.angleDegrees(rise: 3, run: 4) - 36.8698976) < 1e-6)   // atan(3/4)
        #expect(abs(Pitch.angleDegrees(rise: 4, run: 3) - 53.1301024) < 1e-6)   // atan(4/3)
    }

    @Test func publishedRoofPitchAngles() {
        // oracle: published roof-pitch→degrees tables
        #expect(abs(Pitch.angleFromPitch(riseIn12: 4) - 18.43) < 0.01)
        #expect(abs(Pitch.angleFromPitch(riseIn12: 6) - 26.57) < 0.01)
        #expect(abs(Pitch.angleFromPitch(riseIn12: 8) - 33.69) < 0.01)
        #expect(abs(Pitch.angleFromPitch(riseIn12: 12) - 45.0) < 1e-9)
    }

    @Test func guardsNoCrash() {
        #expect(Pitch.slopePercent(rise: 6, run: 0) == 0)           // run 0 → 0, no divide crash
        #expect(Pitch.riseInTwelve(rise: 6, run: 0) == 0)
        #expect(Pitch.leg(diagonal: 3, otherLeg: 5) == 0)          // impossible triangle → 0, not NaN
        #expect(Rafter.commonPerFootRun(rise: 0) == 12)            // flat roof → 12"/ft
        #expect(Stairs.solve(totalRise: 0).risers == 1)            // 0 rise → 1 riser, no /0
    }

    @Test func slopeAndPitch() {
        #expect(abs(Pitch.slopePercent(rise: 6, run: 12) - 50) < 1e-12)        // 6/12 = 50 % grade
        #expect(abs(Pitch.slopePercent(rise: 1, run: 4) - 25) < 1e-12)         // 1:4 = 25 %
        #expect(abs(Pitch.riseInTwelve(rise: 3, run: 4) - 9) < 1e-12)          // 3-in-4 → 9-in-12
        #expect(abs(Pitch.pitchFromAngle(degrees: 45) - 12) < 1e-9)            // 45° → 12/12
    }
}

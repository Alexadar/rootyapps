import Testing
import Foundation
@testable import PitchKit

// Oracle = the framing-square rafter table + definitional trigonometry.  oracle-backed/identity.
/// ORACLES:
///  • PUBLISHED — the numbers printed on a physical framing square's rafter table, which is a
///    century-old published artefact reproduced identically across framing references:
///    common length per foot of run at 3/12 = 12.37, 6/12 = 13.42, 7/12 = 13.89, 18/12 = 21.63;
///    hip/valley at 6/12 = 18.00. The square is printed to 1/100", so tolerance is 0.005.
///    Cross-referenced with NAVEDTRA 14044 "Framing Roofs" (US Navy, public domain).
///  • IDENTITY  — those table values ARE sqrt(rise^2 + 144) and sqrt(rise^2 + 288), asserted against
///    the closed form at 1e-9 so a re-transcribed table cannot silently move the maths.
///  • IDENTITY  — a 12/12 roof is 45 degrees; the hip unit run is 12*sqrt(2).
///  • INVARIANT — right-triangle closure, monotonicity, and jack rafters differing by a constant.
///
/// Why this Kit is worth shipping, in a competitor's own review — RedX Roof, 1★:
/// *"Following the measurements for hip and Jack rafters to the 16th came up with the wrong
/// measurements and a lot of wasted material."*
@Suite("Pitch and Rafter — oracle-backed")
struct PitchRafterOracleTests {

    static let source = """
        Framing-square rafter table (published artefact, reproduced identically across framing \
        references); cross-referenced with NAVEDTRA 14044 "Framing Roofs", US Navy, public domain; \
        https://nvlpubs.nist.gov/ is NOT the source here — see docs/storypole_oracle_gate_2026-07-29.md \
        §3.2 for why this Kit is classed IDENTITY with a published cross-check rather than PUBLISHED.
        """

    // MARK: - PUBLISHED: the framing square

    @Test("common rafter length per foot of run matches the framing square")
    func commonPerFootRun() {
        #expect(abs(Rafter.commonPerFootRun(rise: 3) - 12.37) < 0.005)
        #expect(abs(Rafter.commonPerFootRun(rise: 6) - 13.42) < 0.005)
        #expect(abs(Rafter.commonPerFootRun(rise: 7) - 13.89) < 0.005)
        #expect(abs(Rafter.commonPerFootRun(rise: 18) - 21.63) < 0.005)
    }

    @Test("hip/valley length per foot of common run matches the framing square")
    func hipValleyPerFootRun() {
        #expect(abs(Rafter.hipValleyPerFootRun(rise: 6) - 18.00) < 0.005)
        #expect(abs(Rafter.hipUnitRun - 16.9705627) < 1e-6, "the 45-degree diagonal of a 12in square")
        #expect(abs(Rafter.hipUnitRun - 12 * 2.0.squareRoot()) < 1e-15)
    }

    /// The published table values re-derived from the closed form — independent of the
    /// transcription, so the two corroborate rather than repeat each other.
    @Test("the table values ARE sqrt(rise^2 + 144) and sqrt(rise^2 + 288)")
    func tableIsTheClosedForm() {
        for rise in stride(from: 1.0, through: 24.0, by: 1.0) {
            #expect(abs(Rafter.commonPerFootRun(rise: rise) - (rise * rise + 144).squareRoot()) < 1e-9)
            #expect(abs(Rafter.hipValleyPerFootRun(rise: rise) - (rise * rise + 288).squareRoot()) < 1e-9)
        }
        // The hip formula's 288 is 144 + 144: the hip runs the diagonal of the unit square.
        #expect(abs(Rafter.hipUnitRun * Rafter.hipUnitRun - 288) < 1e-9)
    }

    // MARK: - IDENTITY: pitch three ways

    @Test("a 12-in-12 roof is exactly 45 degrees, 100 percent, and 12 in 12")
    func twelveTwelve() {
        #expect(abs(Pitch.angleFromPitch(riseIn12: 12) - 45) < 1e-12)
        #expect(abs(Pitch.slopePercent(rise: 12, run: 12) - 100) < 1e-12)
        #expect(abs(Pitch.riseInTwelve(rise: 12, run: 12) - 12) < 1e-12)
    }

    @Test("a 6-in-12 roof, the three ways three trades read it")
    func sixTwelve() {
        #expect(abs(Pitch.angleFromPitch(riseIn12: 6) - 26.5650512) < 1e-6)
        #expect(abs(Pitch.slopePercent(rise: 6, run: 12) - 50) < 1e-12)
        #expect(abs(Pitch.pitchMultiplier(riseIn12: 6) - 1.1180340) < 1e-6, "sqrt(1.25)")
        #expect(abs(Pitch.pitchMultiplier(riseIn12: 6) - 1.25.squareRoot()) < 1e-15)
    }

    @Test("angle and pitch are inverses of each other")
    func angleAndPitchRoundTrip() {
        for rise in stride(from: 0.5, through: 24.0, by: 0.5) {
            let deg = Pitch.angleFromPitch(riseIn12: rise)
            #expect(abs(Pitch.pitchFromAngle(degrees: deg) - rise) < 1e-9, "round-trip failed at \(rise)/12")
        }
    }

    @Test("the pitch multiplier is the slope factor, and scales plan area to sloped area")
    func multiplierScalesArea() {
        for rise in [4.0, 6.0, 9.0, 12.0] {
            #expect(abs(Pitch.pitchMultiplier(riseIn12: rise) - Rafter.slopeFactor(rise: rise)) < 1e-12,
                    "the two names must be the same number")
            #expect(abs(Pitch.slopedArea(planArea: 1000, riseIn12: rise)
                        - 1000 * Pitch.pitchMultiplier(riseIn12: rise)) < 1e-9)
        }
    }

    // MARK: - IDENTITY: cut angles and lengths

    @Test("plumb and level cuts are complements")
    func cutsAreComplements() {
        for rise in stride(from: 1.0, through: 20.0, by: 1.0) {
            #expect(abs(Rafter.plumbCutDegrees(rise: rise) + Rafter.levelCutDegrees(rise: rise) - 90) < 1e-12)
        }
        #expect(abs(Rafter.plumbCutDegrees(rise: 6) - 26.5650512) < 1e-6)
        #expect(abs(Rafter.levelCutDegrees(rise: 6) - 63.4349488) < 1e-6)
        #expect(abs(Rafter.plumbCutDegrees(rise: 12) - 45) < 1e-12)
    }

    @Test("total lengths for a 6/12 roof at 10 ft of run")
    func totalLengths() {
        #expect(abs(Rafter.commonLength(rise: 6, runFeet: 10) - 134.1640786) < 1e-6)
        #expect(abs(Rafter.hipValleyLength(rise: 6, commonRunFeet: 10) - 180.0) < 1e-6)
    }

    @Test("the rafter closes the right triangle it describes")
    func rightTriangleCloses() {
        for rise in [4.0, 6.0, 12.0] {
            let runFt = 10.0
            let len = Rafter.commonLength(rise: rise, runFeet: runFt)
            let runIn = runFt * 12
            let riseIn = runFt * rise
            #expect(abs(len * len - (runIn * runIn + riseIn * riseIn)) < 1e-6, "Pythagoras must hold")
        }
    }

    @Test("actual cut length is line length minus ridge plus tail")
    func actualCut() {
        let line = Rafter.commonLength(rise: 6, runFeet: 12)
        let ridge = Rafter.ridgeDeductionIn(rise: 6, ridgeThicknessIn: 1.5)
        let tail = Rafter.overhangAlongIn(rise: 6, overhangIn: 12)
        let actual = Rafter.actualLength(rise: 6, runFeet: 12, ridgeThicknessIn: 1.5, overhangIn: 12)

        #expect(abs(ridge - 0.8385255) < 1e-6)
        #expect(abs(tail - 13.4164079) < 1e-6)
        #expect(abs(actual - (line - ridge + tail)) < 1e-9, "self-consistency")
        #expect(abs(actual - 173.5747767) < 1e-6)
        // Closed form: the whole cut is 155.25" of horizontal run times the slope factor.
        #expect(abs(actual - 155.25 * Rafter.slopeFactor(rise: 6)) < 1e-6)
    }

    @Test("jack rafters differ by a constant common difference")
    func jackRafters() {
        let d = Rafter.jackCommonDifference(rise: 6, spacingInches: 16)
        #expect(abs(d - 17.8885438) < 1e-6)
        let j1 = Rafter.jackLength(rise: 6, longestRunFeet: 12, spacingInches: 16, index: 1)
        let j2 = Rafter.jackLength(rise: 6, longestRunFeet: 12, spacingInches: 16, index: 2)
        #expect(abs((j1 - j2) - d) < 1e-9, "each jack is exactly one common difference shorter")
        #expect(j2 < j1, "jacks get shorter as the index rises")
    }

    @Test("a jack rafter never goes negative")
    func jacksClampAtZero() {
        #expect(Rafter.jackLength(rise: 6, longestRunFeet: 2, spacingInches: 16, index: 50) == 0)
    }

    @Test("steeper roofs give longer rafters")
    func monotonicInRise() {
        var previous = 0.0
        for rise in stride(from: 1.0, through: 24.0, by: 1.0) {
            let l = Rafter.commonPerFootRun(rise: rise)
            #expect(l > previous, "length per foot of run must increase with pitch")
            previous = l
        }
    }
}

import Testing
import Foundation
import PipeKit
import FramingKit
@testable import KerfCalc

/// Unit tests for the pipe tools' picker → value mapping, and for the one place PipeKit deliberately
/// duplicates FramingKit.
///
/// The mapping tests exist for the same reason `ToolHeroesTests` does: a wrong row in a segmented
/// control feeds a *correct* Kit the *wrong* input, and nothing in the Kit's own suite can catch it.
@Suite struct PipeOptionsTests {

    @Test func fittingAnglesMapToTheRightSegment() {
        #expect(PipeFittingChoice.titles.count == 4)
        #expect(PipeFittingChoice.angleDeg(index: 0, custom: 60) == 45)
        #expect(PipeFittingChoice.angleDeg(index: 1, custom: 60) == 22.5)
        #expect(PipeFittingChoice.angleDeg(index: 2, custom: 60) == 11.25)
        // "Other" is the only row that honours the custom field.
        #expect(PipeFittingChoice.angleDeg(index: PipeFittingChoice.otherIndex, custom: 60) == 60)
        #expect(PipeFittingChoice.angleDeg(index: 3, custom: 30) == 30)
    }

    @Test func gradesMapToTheRightSegment() {
        #expect(PipeGradeChoice.titles.count == 4)
        #expect(PipeGradeChoice.fallInPerFt(index: 0, custom: 0.375) == 0.25)    // ¼"/ft
        #expect(PipeGradeChoice.fallInPerFt(index: 1, custom: 0.375) == 0.125)   // ⅛"/ft
        #expect(PipeGradeChoice.fallInPerFt(index: 2, custom: 0.375) == 0.5)     // ½"/ft
        #expect(PipeGradeChoice.fallInPerFt(index: PipeGradeChoice.otherIndex, custom: 0.375) == 0.375)
    }

    /// The picked segments must land on the published multipliers, end to end through the Kit —
    /// this is the wiring the user actually sees on the Offset screen.
    @Test func pickedAnglesProduceThePublishedMultipliers() {
        let m = { (i: Int) in PipeOffset.travelMultiplier(fittingAngleDeg: PipeFittingChoice.angleDeg(index: i, custom: 0)) }
        #expect(abs(m(0) - 1.414) < 0.0005)   // 45°
        #expect(abs(m(1) - 2.613) < 0.0005)   // 22½°
        #expect(abs(m(2) - 5.126) < 0.0005)   // 11¼°
    }

    /// PipeKit restates FramingKit's right triangle in the pipe trades' vocabulary rather than
    /// importing it (no Kit here depends on another). This test is the guard against the two
    /// spellings drifting apart — the app target links both, so it is the only place they can meet.
    @Test func pipeGradeAgreesWithFramingPitch() {
        for fallPerFt in [0.125, 0.25, 0.5, 1.0, 6.0, 12.0] {
            #expect(abs(PipeGrade.percent(fallInPerFt: fallPerFt)
                        - Pitch.slopePercent(rise: fallPerFt, run: 12)) < 1e-12)
            #expect(abs(PipeGrade.degrees(fallInPerFt: fallPerFt)
                        - Pitch.angleDegrees(rise: fallPerFt, run: 12)) < 1e-12)
        }
    }

    /// Same for the offset triangle: travel is the hypotenuse of set and run, whichever Kit spells it.
    @Test func pipeOffsetAgreesWithFramingPitch() {
        for θ in [11.25, 22.5, 30.0, 45.0, 60.0] {
            let set = 10.0
            let run = PipeOffset.runIn(setIn: set, fittingAngleDeg: θ)
            #expect(abs(PipeOffset.travelIn(setIn: set, fittingAngleDeg: θ)
                        - Pitch.diagonal(rise: set, run: run)) < 1e-9)
            #expect(abs(PipeOffset.fittingAngleDeg(setIn: set, runIn: run)
                        - Pitch.angleDegrees(rise: set, run: run)) < 1e-9)
        }
    }
}

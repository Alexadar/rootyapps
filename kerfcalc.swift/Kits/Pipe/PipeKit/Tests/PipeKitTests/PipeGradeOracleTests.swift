import Testing
import Foundation
@testable import PipeKit

/// Calc #14 — drainage grade / fall (in/ft ↔ percent ↔ 1:N ↔ degrees).
///
/// ORACLES:
///  • PUBLISHED — the plumbing codes' minimum drainage slopes, which are printed as all three
///    spellings of the same number: **¼″ per foot = 2 % (nominally 2.08 %) = 1:48** for horizontal
///    drains up to 2½″, and **⅛″ per foot = 1 % (nominally 1.04 %) = 1:96** for larger pipe.
///    (IPC Table 704.1 / UPC 708.0 — code-cycle values; the edition adopted varies by jurisdiction,
///    so `Standards.swift` carries them at the *code* volatility tier.)
///  • IDENTITY — percent is `fallPerFt ⁄ 12 · 100` and the ratio is its reciprocal `12 ⁄ fallPerFt`;
///    the degree form is `atan(fallPerFt ⁄ 12)`. Round-trips asserted in both directions.
///  • INVARIANT — fall scales linearly with run; a level run has no fall, no grade and no angle.
@Suite struct PipeGradeOracle {

    @Test func publishedCodeMinimumSlopes() {
        // oracle: IPC/UPC minimum slope — ¼"/ft
        #expect(abs(PipeGrade.percent(fallInPerFt: 0.25) - 2.0833) < 0.0001)
        #expect(abs(PipeGrade.ratioDenominator(fallInPerFt: 0.25) - 48) < 1e-12)      // 1:48
        // oracle: IPC/UPC minimum slope — ⅛"/ft (pipe larger than 2½")
        #expect(abs(PipeGrade.percent(fallInPerFt: 0.125) - 1.0417) < 0.0001)
        #expect(abs(PipeGrade.ratioDenominator(fallInPerFt: 0.125) - 96) < 1e-12)     // 1:96
        // ½"/ft, the other slope commonly tabulated alongside them
        #expect(abs(PipeGrade.percent(fallInPerFt: 0.5) - 4.1667) < 0.0001)
        #expect(abs(PipeGrade.ratioDenominator(fallInPerFt: 0.5) - 24) < 1e-12)       // 1:24
    }

    @Test func fallOverARun() {
        // 40 ft of 4" drain at ¼"/ft drops 10".
        #expect(abs(PipeGrade.fallIn(runFeet: 40, fallInPerFt: 0.25) - 10) < 1e-12)
        #expect(abs(PipeGrade.fallIn(runFeet: 100, fallInPerFt: 0.125) - 12.5) < 1e-12)
        // …and the grade is recoverable from a measured fall.
        #expect(abs(PipeGrade.fallInPerFt(fallIn: 10, runFeet: 40) - 0.25) < 1e-12)
    }

    @Test func degreesFromGrade() {
        #expect(abs(PipeGrade.degrees(fallInPerFt: 0.25) - 1.1934) < 0.0001)    // atan(0.25/12)
        #expect(abs(PipeGrade.degrees(fallInPerFt: 0.125) - 0.5968) < 0.0001)   // atan(0.125/12)
        #expect(abs(PipeGrade.degrees(fallInPerFt: 12) - 45) < 1e-9)            // 12"/ft = 45°
        #expect(PipeGrade.degrees(fallInPerFt: 0) == 0)                         // level
    }

    @Test func roundTripsBetweenSpellings() {
        for f in [0.125, 0.25, 0.5, 1.0] {
            #expect(abs(PipeGrade.fallInPerFt(percent: PipeGrade.percent(fallInPerFt: f)) - f) < 1e-12)
            #expect(abs(PipeGrade.fallInPerFt(ratioDenominator: PipeGrade.ratioDenominator(fallInPerFt: f)) - f) < 1e-12)
        }
    }

    /// Identity anchor — grade is the same right triangle as the rest of the app, with the run pinned
    /// at 12". Mirrors `FramingKit.Pitch.slopePercent(rise:run:)`; `kerfcalcTests` asserts they agree.
    @Test func percentIsRiseOverRunWithRunTwelve() {
        for f in [0.125, 0.25, 0.5, 1.0, 6.0] {
            #expect(abs(PipeGrade.percent(fallInPerFt: f) - (f / 12 * 100)) < 1e-12)
            #expect(abs(PipeGrade.degrees(fallInPerFt: f) - atan2(f, 12) * 180 / Double.pi) < 1e-12)
        }
    }

    @Test func guardsNoCrash() {
        #expect(PipeGrade.fallInPerFt(fallIn: 10, runFeet: 0) == 0)        // no run → 0, no divide crash
        #expect(PipeGrade.ratioDenominator(fallInPerFt: 0) == 0)           // level → 0, not infinity
        #expect(PipeGrade.fallInPerFt(ratioDenominator: 0) == 0)
        #expect(PipeGrade.percent(fallInPerFt: 0) == 0)
        #expect(PipeGrade.fallIn(runFeet: 0, fallInPerFt: 0.25) == 0)
    }
}

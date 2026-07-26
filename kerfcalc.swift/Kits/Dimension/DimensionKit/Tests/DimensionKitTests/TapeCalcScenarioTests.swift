import Testing
import Foundation
@testable import DimensionKit

/// Exhaustive keypad-logic scenarios — every way a worker might punch the tape calculator.
/// Ground truth is exact inch arithmetic (hand-verified in each comment) + the independent
/// CPython Fraction cross-check for the arithmetic core.
@Suite struct TapeCalcScenarios {

    private func digits(_ c: inout TapeCalc, _ n: Int) {
        let s = n < 0 ? String(-n) : String(n)
        if n < 0 { /* no unary minus key; negatives arise from subtraction */ }
        for ch in s { c.digit(Int(String(ch))!) }
    }

    // MARK: entry forms
    @Test func feetOnly() {
        var c = TapeCalc(); digits(&c, 5); c.feetKey()
        #expect(c.display == "5'")
    }
    @Test func inchOnly() {
        var c = TapeCalc(); digits(&c, 9); c.inchKey()
        #expect(c.display == "9\"")
    }
    @Test func bareNumberIsInches() {
        var c = TapeCalc(); digits(&c, 18); c.equals()
        #expect(c.display == "1' 6\"")                     // 18" = 1'6"
    }
    @Test func fractionOnly() {
        var c = TapeCalc(); c.digit(3); c.fractionKey(); c.digit(4)
        #expect(c.display == "3/4\"")
    }
    @Test func mixedEntry() {
        var c = TapeCalc(); digits(&c, 12); c.feetKey(); c.digit(6); c.inchKey(); c.digit(1); c.fractionKey(); c.digit(2)
        #expect(c.display == "12' 6-1/2\"")
    }

    // MARK: the four operators (immediate execution, left-to-right)
    @Test func additionChain() {
        var c = TapeCalc()
        digits(&c, 1); c.feetKey(); c.setOp(.add)
        digits(&c, 2); c.feetKey(); c.setOp(.add)
        digits(&c, 3); c.feetKey(); c.equals()
        #expect(c.display == "6'")                          // 1'+2'+3'
    }
    @Test func subtractionToNegative() {
        var c = TapeCalc()
        digits(&c, 5); c.feetKey(); digits(&c, 3); c.inchKey()   // 5'3" = 63"
        c.setOp(.sub)
        digits(&c, 8); c.feetKey(); c.equals()                    // − 96"
        #expect(c.display == "-2' 9\"")                     // 63−96 = −33" = −2'9"
    }
    @Test func scalarMultiply() {
        var c = TapeCalc()
        digits(&c, 6); c.feetKey(); digits(&c, 8); c.inchKey()    // 6'8" = 80"
        c.setOp(.mul); digits(&c, 3); c.equals()
        #expect(c.display == "20'")                         // 80"×3 = 240" = 20'
    }
    @Test func scalarDivide() {
        var c = TapeCalc()
        digits(&c, 12); c.feetKey(); digits(&c, 6); c.inchKey()   // 12'6" = 150"
        c.setOp(.div); digits(&c, 2); c.equals()
        #expect(c.display == "6' 3\"")                      // 150"/2 = 75" = 6'3"
    }
    @Test func fullReelCalc() {
        var c = TapeCalc()
        digits(&c, 8); c.feetKey(); digits(&c, 4); c.inchKey(); c.digit(1); c.fractionKey(); c.digit(2) // 8'4½"
        c.setOp(.mul); digits(&c, 3)
        c.setOp(.sub); digits(&c, 2); c.feetKey(); digits(&c, 6); c.inchKey()
        c.setOp(.div); digits(&c, 2); c.equals()
        #expect(c.display == "11' 3-3/4\"")                 // 100.5×3−30÷2 = 135.75" = 11'3¾"
    }

    // MARK: fraction precision & reduction
    @Test func precisionRounding() {
        var c = TapeCalc(); c.digit(1); c.fractionKey(); c.digit(3)   // 1/3"
        c.setDenominator(16); #expect(c.display == "5/16\"")
        c.setDenominator(8);  #expect(c.display == "3/8\"")
        c.setDenominator(32); #expect(c.display == "11/32\"")
    }
    @Test func fractionReduces() {
        var c = TapeCalc(); c.digit(8); c.fractionKey(); digits(&c, 16)   // 8/16"
        #expect(c.display == "1/2\"")
    }

    // MARK: edit keys
    @Test func backspaceRemovesLastPart() {
        var c = TapeCalc()
        digits(&c, 6); c.feetKey(); digits(&c, 5); c.inchKey()      // 6'5"
        #expect(c.display == "6' 5\"")
        c.backspace()
        #expect(c.display == "6'")
    }
    @Test func clearResetsToZero() {
        var c = TapeCalc()
        digits(&c, 5); c.feetKey(); c.setOp(.add); digits(&c, 3); c.feetKey()
        c.clear()                                                    // clears entry
        c.clear()                                                    // clears all
        #expect(c.display == "0\"")
    }

    // MARK: right-triangle registers
    @Test func diagonalTriangles() {
        for (rise, run, diag) in [(3, 4, "5'"), (5, 12, "13'"), (6, 8, "10'")] {
            var c = TapeCalc()
            digits(&c, rise); c.feetKey(); c.storeRise()
            digits(&c, run);  c.feetKey(); c.storeRun()
            c.solveDiagonal()
            #expect(c.display == diag, "\(rise)-\(run) triangle")
        }
    }
    @Test func pitchFromRiseRun() {
        var c = TapeCalc()
        digits(&c, 4); c.inchKey(); c.storeRise()
        digits(&c, 12); c.inchKey(); c.storeRun()
        c.solvePitch()
        #expect(c.display == "4.00 /12")
    }

    // MARK: conversions (the engine method; NIST factors)
    @Test func guardsNoCrash() {
        var c = TapeCalc()
        digits(&c, 5); c.feetKey(); c.setOp(.div); c.digit(0); c.equals()
        #expect(c.display == "5'")                                  // ÷ 0 keeps the value, no crash
        _ = FeetInch.approx(inches: 1_000_000, den: 16)             // huge value, no overflow crash
        #expect(FeetInch.parse("///") == nil)                       // garbage parses to nil, not a trap
        #expect(Rational(0, 5) == Rational(0))                      // 0 numerator reduces cleanly
    }

    @Test func convertResultToMetricAndBack() {
        var c = TapeCalc(); digits(&c, 1); c.feetKey()             // 1 ft
        c.convert(to: .millimeter); #expect(c.display == "304.8 mm")
        var d = TapeCalc(); digits(&d, 1); d.feetKey()
        d.convert(to: .inch); #expect(d.display == "12 in")        // 1 ft = 12 in exactly
        var e = TapeCalc(); digits(&e, 1); e.feetKey()
        e.convert(to: .meter); #expect(e.display == "0.305 m")     // 0.3048 → 3dp
    }
}

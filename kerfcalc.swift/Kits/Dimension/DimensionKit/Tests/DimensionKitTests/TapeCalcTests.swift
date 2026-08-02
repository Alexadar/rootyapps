import Testing
import Foundation
@testable import DimensionKit

/// Keypad state-machine tests — drives the calculator exactly as fingers would, then checks the
/// readout. Ground truth is the SAME published feet-inch arithmetic as calc #1 (the marquee
/// `6'2½" + 2'7¾" = 8'10¼"`), now proven end-to-end through the tape engine.
@Suite struct TapeCalcMachine {

    /// helper: type a bare integer's digits
    private func digits(_ c: inout TapeCalc, _ n: Int) { for ch in String(n) { c.digit(Int(String(ch))!) } }

    @Test func entersADimension() {
        var c = TapeCalc()
        digits(&c, 6); c.feetKey(); digits(&c, 2); c.inchKey(); c.digit(1); c.fractionKey(); c.digit(2)
        #expect(c.display == "6' 2-1/2\"")
    }

    @Test func publishedAddition() {
        // 6' 2-1/2" + 2' 7-3/4" = 8' 10-1/4"  (published worked example, via the keypad)
        var c = TapeCalc()
        digits(&c, 6); c.feetKey(); digits(&c, 2); c.inchKey(); c.digit(1); c.fractionKey(); c.digit(2)
        c.setOp(.add)
        digits(&c, 2); c.feetKey(); digits(&c, 7); c.inchKey(); c.digit(3); c.fractionKey(); c.digit(4)
        c.equals()
        #expect(c.display == "8' 10-1/4\"")
    }

    @Test func publishedSubtraction() {
        // 6' 5-1/4" − 3' 2-7/8" = 3' 2-3/8"
        var c = TapeCalc()
        digits(&c, 6); c.feetKey(); digits(&c, 5); c.inchKey(); c.digit(1); c.fractionKey(); c.digit(4)
        c.setOp(.sub)
        digits(&c, 3); c.feetKey(); digits(&c, 2); c.inchKey(); c.digit(7); c.fractionKey(); c.digit(8)
        c.equals()
        #expect(c.display == "3' 2-3/8\"")
    }

    @Test func scalarMultiplyAndDivide() {
        var m = TapeCalc()
        digits(&m, 10); m.feetKey(); m.setOp(.mul); m.digit(3); m.equals()
        #expect(m.display == "30'")                       // 10' × 3

        var d = TapeCalc()
        digits(&d, 12); d.feetKey(); d.setOp(.div); d.digit(2); d.equals()
        #expect(d.display == "6'")                        // 12' ÷ 2
    }

    @Test func bareNumberIsInches() {
        var c = TapeCalc()
        digits(&c, 18)                                    // no tag → inches
        c.equals()
        #expect(c.display == "1' 6\"")                    // 18" = 1'6"
    }

    @Test func precisionAndConvert() {
        var c = TapeCalc()
        digits(&c, 3); c.feetKey()
        c.convert(to: .meter)
        #expect(c.display == "0.914 m")                   // 3 ft = 0.9144 m (rounded 3dp)
        c.digit(1)                                        // typing clears the transient conversion
        #expect(c.display != "0.914 m")
    }

    @Test func riseRunDiagonalSolve() {
        // 3-4-5 right triangle via the Spec registers: Rise 3', Run 4' → Diag 5'.
        var c = TapeCalc()
        digits(&c, 3); c.feetKey(); c.storeRise()
        digits(&c, 4); c.feetKey(); c.storeRun()
        c.solveDiagonal()
        #expect(c.display == "5'")                         // √(36²+48²)=60" = 5'
        #expect(c.riseDisplay == "3'" && c.runDisplay == "4'")
    }

    @Test func pitchSolve() {
        // Rise 6", Run 12" → pitch 6.00 /12 ; Rise 12" Run 12" → 12.00 /12
        var c = TapeCalc()
        digits(&c, 6); c.inchKey(); c.storeRise()
        digits(&c, 12); c.inchKey(); c.storeRun()
        c.solvePitch()
        #expect(c.display == "6.00 /12")
    }

    @Test func clearResets() {
        var c = TapeCalc()
        digits(&c, 5); c.feetKey(); c.clear()             // clears entry
        c.clear()                                         // clears all
        #expect(c.display == "0\"")
    }
}

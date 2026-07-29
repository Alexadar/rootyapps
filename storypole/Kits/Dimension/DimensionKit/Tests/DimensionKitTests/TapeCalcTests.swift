import Testing
import Foundation
@testable import DimensionKit

// Oracle = the incumbent's named defects, reproduced as scenarios.  invariant.
/// ORACLES:
///  • INVARIANT — defect ③, the app's longest-standing failure: multiplying two dimensioned
///    lengths must produce an area. Twelve years of reviews, 2014 to 2025.
///  • INVARIANT — a fraction can be entered NUMERATOR FIRST (three reviewers call the incumbent's
///    denominator-first spinner backwards).
///  • INVARIANT — undefined dimensions surface an error instead of clamping to a plausible lie.
@Suite("TapeCalc — the keypad")
struct TapeCalcTests {

    /// Enter a feet-inches value: digits, Feet, digits, Inch.
    private func enter(_ c: inout TapeCalc, feet: Int?, inches: Int?, num: Int? = nil, den: Int? = nil) {
        if let feet {
            for d in String(feet) { c.digit(Int(String(d))!) }
            c.feetKey()
        }
        if let inches {
            for d in String(inches) { c.digit(Int(String(d))!) }
            c.inchKey()
        }
        if let num, let den {
            for d in String(num) { c.digit(Int(String(d))!) }
            c.fractionKey()                       // numerator first, then the / key
            for d in String(den) { c.digit(Int(String(d))!) }
        }
    }

    // MARK: - Defect ③: the twelve-year multiplication failure

    /// 2★ 2016-09-24: *"I can not multiply 12'-4" X 12'-4" ... I need feet and inches by feet and
    /// inches. NO need for decimals."*
    @Test("12'4\" x 12'4\" gives an area, not a refusal")
    func dimensionedMultiplicationWorks() throws {
        var c = TapeCalc()
        enter(&c, feet: 12, inches: 4)
        c.setOp(.mul)
        enter(&c, feet: 12, inches: 4)
        c.equals()

        #expect(c.error == nil, "the operation must succeed")
        #expect(c.currentDimension == .square, "length x length is an area")
        // 148 in x 148 in = 21904 in² = 152.11 ft²
        let ft2 = try #require(c.areaFt2)
        #expect(abs(ft2 - 21904.0 / 144.0) < 1e-9, "got \(ft2) sq ft")
    }

    /// 1★ 2025-11-22: *"can't even multiply for square footage."*
    @Test("a room's square footage: 19'8\" x 11'4\"")
    func squareFootage() throws {
        var c = TapeCalc()
        enter(&c, feet: 19, inches: 8)
        c.setOp(.mul)
        enter(&c, feet: 11, inches: 4)
        c.equals()
        let ft2 = try #require(c.areaFt2)
        #expect(abs(ft2 - (236.0 * 136.0) / 144.0) < 1e-9, "got \(ft2) sq ft")
    }

    @Test("area x depth gives a volume")
    func volumeFromAreaAndDepth() throws {
        var c = TapeCalc()
        enter(&c, feet: 10, inches: 0)
        c.setOp(.mul)
        enter(&c, feet: 8, inches: 0)
        c.equals()
        #expect(c.currentDimension == .square)
        c.setOp(.mul)
        enter(&c, feet: nil, inches: 4)
        c.equals()
        #expect(c.currentDimension == .cubic)
        let ft3 = try #require(c.volumeFt3)
        #expect(abs(ft3 - (120.0 * 96.0 * 4.0) / 1728.0) < 1e-9, "got \(ft3) cu ft")
    }

    @Test("a bare number is a scalar multiplier, not a length")
    func scalarMultiplierKeepsDimension() {
        var c = TapeCalc()
        enter(&c, feet: 10, inches: 0)
        c.setOp(.mul)
        c.digit(3)                                  // untagged → scalar
        c.equals()
        #expect(c.currentDimension == .linear, "10' x 3 is still a length")
        #expect(c.displayValue == FeetInch(feet: 30))
    }

    // MARK: - Errors are surfaced, never clamped

    @Test("a fourth power is refused, not silently called a volume")
    func fourthPowerIsRefused() {
        var c = TapeCalc()
        enter(&c, feet: 2, inches: 0)
        c.setOp(.mul); enter(&c, feet: 2, inches: 0); c.equals()   // square
        c.setOp(.mul); enter(&c, feet: 2, inches: 0); c.equals()   // cubic
        #expect(c.currentDimension == .cubic)
        c.setOp(.mul); enter(&c, feet: 2, inches: 0); c.equals()   // would be 4th power
        #expect(c.error == .dimensionOverflow, "must report, not clamp to cubic")
        #expect(c.currentDimension == .cubic, "state must not have advanced")
    }

    @Test("division by zero is refused")
    func divisionByZero() {
        var c = TapeCalc()
        enter(&c, feet: 10, inches: 0)
        c.setOp(.div)
        c.digit(0)
        c.equals()
        #expect(c.error == .divisionByZero)
    }

    // MARK: - Fraction entry, numerator first

    /// 5★ 2022-02-04: *"wish it didn't make me do the denominator first"*.
    @Test("a fraction is typed numerator first: 6, /, 16 gives 6/16")
    func fractionIsNumeratorFirst() {
        var c = TapeCalc()
        enter(&c, feet: nil, inches: 8, num: 7, den: 16)
        #expect(c.displayValue == FeetInch(inches: 8, num: 7, den: 16))
        #expect(c.displayValue.formatted() == "8-7/16\"")
    }

    @Test("addition of mixed fractions, the app's core job")
    func addsMixedFractions() {
        var c = TapeCalc()
        enter(&c, feet: 6, inches: 2, num: 1, den: 2)
        c.setOp(.add)
        enter(&c, feet: 2, inches: 7, num: 3, den: 4)
        c.equals()
        // 6'2 1/2" + 2'7 3/4" = 8'10 1/4"
        #expect(c.displayValue.formatted() == "8' 10-1/4\"", "got \(c.displayValue.formatted())")
    }

    // MARK: - Recall and tape

    /// 5★ 2020-04-17: *"I would like to be able click on a measurement I just calculated and be
    /// able to add or subtract from that as well"*.
    @Test("a result can be recalled into the next calculation")
    func resultRecalls() {
        var c = TapeCalc()
        enter(&c, feet: 6, inches: 0)
        c.equals()
        let first = c.displayValue

        var d = TapeCalc()
        d.preload(first)
        d.setOp(.add)
        enter(&d, feet: nil, inches: 6)
        d.equals()
        #expect(d.displayValue == FeetInch(feet: 6, inches: 6))
    }

    @Test("the tape is offered for a length and withheld for an area")
    func tapeOnlyForLengths() {
        var c = TapeCalc()
        enter(&c, feet: 8, inches: 0)
        c.equals()
        #expect(c.tape?.lengthFeet == 12, "8 ft fits a 12 ft tape")

        var area = TapeCalc()
        enter(&area, feet: 10, inches: 0)
        area.setOp(.mul)
        enter(&area, feet: 10, inches: 0)
        area.equals()
        #expect(area.tape == nil, "an area is not a point on a tape")
    }

    @Test("a result longer than every real tape offers no tape")
    func noTapeBeyondReality() {
        var c = TapeCalc()
        enter(&c, feet: 40, inches: 0)
        c.equals()
        #expect(c.tape == nil, "40 ft exceeds every blade in the catalogue")
    }

    // MARK: - Editing

    @Test("clear resets the entry, then the whole calculation")
    func clearBehaviour() {
        var c = TapeCalc()
        enter(&c, feet: 12, inches: 6)
        c.clear()
        #expect(c.displayValue == .zero)
        c.clear()
        #expect(c.pendingOp == nil)
    }

    @Test("backspace unwinds a fraction back through the / key")
    func backspaceUnwindsFraction() {
        var c = TapeCalc()
        enter(&c, feet: nil, inches: 8, num: 7, den: 16)
        c.backspace()                                  // 16 -> 1
        c.backspace()                                  // 1 -> (empty denominator)
        c.backspace()                                  // leave fraction mode, restore numerator
        #expect(c.displayValue == FeetInch(inches: 8, num: 0, den: 1) || c.displayValue.inches.den == 1,
                "after unwinding, no partial fraction should remain: \(c.displayValue.formatted())")
    }
}

// Oracle = "never silently discard what the user typed".  invariant.
/// Found by a UI test: at the default 1/16 display, typing `5" 1/32` rendered as plain `5"`.
/// A 1/32 is exactly half a sixteenth, so round-half-to-even sent it to zero and the fraction the
/// user had just keyed in disappeared in front of them.
@Suite("TapeCalc — entered precision is never lost")
struct EnteredPrecisionTests {

    private func enter(_ c: inout TapeCalc, inches: Int, num: Int, den: Int) {
        for d in String(inches) { c.digit(Int(String(d))!) }
        c.inchKey()
        for d in String(num) { c.digit(Int(String(d))!) }
        c.fractionKey()
        for d in String(den) { c.digit(Int(String(d))!) }
    }

    @Test("typing a finer fraction raises the display precision to hold it",
          arguments: [Int64(32), 64])
    func finerFractionRaisesPrecision(den: Int64) {
        var c = TapeCalc()
        #expect(c.denominator == 16, "the default display precision")
        enter(&c, inches: 5, num: 1, den: Int(den))
        #expect(c.denominator == den, "precision should have risen to 1/\(den)")
        #expect(c.displayValue.formatted(toDenominator: c.denominator).contains("1/\(den)"),
                "got \(c.displayValue.formatted(toDenominator: c.denominator))")
    }

    @Test("the exact case the UI test caught: 5\" 1/32 at a 1/16 display")
    func theRegression() {
        var c = TapeCalc()
        enter(&c, inches: 5, num: 1, den: 32)
        let shown = c.displayValue.formatted(toDenominator: c.denominator)
        #expect(shown == "5-1/32\"", "the typed 1/32 must survive; got \(shown)")
    }

    @Test("a coarser fraction does not lower the precision")
    func coarserFractionLeavesPrecisionAlone() {
        var c = TapeCalc()
        c.setDenominator(32)
        enter(&c, inches: 5, num: 1, den: 2)
        #expect(c.denominator == 32, "typing 1/2 is not a request to lose resolution")
    }

    @Test("an unsupported denominator is ignored rather than adopted")
    func oddDenominatorIsIgnored() {
        var c = TapeCalc()
        enter(&c, inches: 5, num: 1, den: 3)          // thirds are not a tape precision
        #expect(c.denominator == 16, "1/3 is not on the tape; precision must not change")
    }

    @Test("every offered precision round-trips through entry")
    func everyPrecisionSurvives() {
        for den in TapeCalc.denominators {
            var c = TapeCalc()
            enter(&c, inches: 5, num: 1, den: Int(den))
            let shown = c.displayValue.formatted(toDenominator: c.denominator)
            #expect(shown.contains("/") || den == 1, "1/\(den) vanished: \(shown)")
        }
    }
}

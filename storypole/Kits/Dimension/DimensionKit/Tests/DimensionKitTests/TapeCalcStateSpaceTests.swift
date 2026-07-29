import Testing
import Foundation
@testable import DimensionKit

/// The keypad's STATE SPACE — every branch, not one path through them.
///
/// ## Why this file exists, and why it is not a UI test
///
/// A calculator is mostly branches, and a suite that walks one happy path through them is theatre.
/// The bug that motivated this: a shipped watch app whose measurement-unit toggle did nothing —
/// every number correct, every screen rendering, the suite green, because no assertion ever flipped
/// it. Controls get tested in their default state or not at all.
///
/// The same coverage through XCUITest is unaffordable. Measured on this app: **~1.1 s per keypad
/// tap**, so the six denominators alone cost 66 s on screen. Here they cost microseconds, which is
/// why this file can afford the *product* of the states rather than a sample of them.
///
/// The division of labour, then:
///
/// | layer | proves |
/// |---|---|
/// | this file | every operator, every dimension transition, every entry mode, every reset path |
/// | the UI suite | that a key reaches this model and this model's answer reaches the screen |
///
/// Nothing here duplicates `TapeCalcTests`, which pins the named review defects to worked examples.
/// This file asserts INVARIANTS over the whole input space instead: properties that must hold for
/// every combination, so a new operator or dimension cannot be added without being covered.
@Suite("TapeCalc — the state space")
struct TapeCalcStateSpaceTests {

    private func enter(_ c: inout TapeCalc, feet: Int? = nil, inches: Int? = nil,
                       num: Int? = nil, den: Int? = nil) {
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
            c.fractionKey()
            for d in String(den) { c.digit(Int(String(d))!) }
        }
    }

    /// A bare scalar: digits with no Feet/Inch tag.
    private func enterScalar(_ c: inout TapeCalc, _ n: Int) {
        for d in String(n) { c.digit(Int(String(d))!) }
    }

    // MARK: - Every denominator, in both directions

    /// This is the port of a UI test that cost 66 s on the simulator to cover six cases. It now
    /// covers all six in microseconds — so it also covers the case the UI test could not afford:
    /// entering a fraction FINER than the display precision, at every display precision.
    @Test("every denominator survives entry at every display precision",
          arguments: TapeCalc.denominators, TapeCalc.denominators)
    func everyDenominatorSurvives(display: Int64, typed: Int64) {
        var c = TapeCalc()
        c.setDenominator(display)
        enter(&c, inches: 5, num: 1, den: Int(typed))
        c.equals()
        // A 1/32 typed at a 1/16 display must RAISE the precision, not round itself away. Before
        // `raiseDenominatorIfFinerWasTyped`, half-to-even sent it to zero and `5" 1/32` rendered
        // as a bare 5" — the keystrokes vanished with no error.
        #expect(c.error == nil)
        #expect(c.displayValue.formatted(toDenominator: c.denominator).contains("/"),
                "1/\(typed) at a 1/\(display) display lost its fraction")
    }

    // MARK: - Every operator

    /// Each operator, applied to two lengths, must produce SOMETHING — a value or a stated error,
    /// never a silent no-op. The dimension it lands in is asserted case by case below.
    @Test("every operator commits and none is silently dropped", arguments: TapeCalc.Op.allCases)
    func everyOperatorCommits(op: TapeCalc.Op) {
        var c = TapeCalc()
        enter(&c, feet: 8)
        c.setOp(op)
        enter(&c, feet: 2)
        c.equals()
        #expect(c.error == nil, "\(op) errored on two plain lengths")
        #expect(c.pendingOp == nil, "\(op) was left pending after equals")
    }

    /// The inverse property, over every operator that has one. This is what catches a sign dropped
    /// or a subtraction implemented as an addition — a worked example cannot, because the wrong
    /// implementation still returns a plausible number.
    @Test("a op b op⁻¹ b == a", arguments: [(TapeCalc.Op.add, TapeCalc.Op.sub),
                                            (TapeCalc.Op.sub, TapeCalc.Op.add)])
    func operatorsInvert(forward: TapeCalc.Op, back: TapeCalc.Op) {
        var c = TapeCalc()
        enter(&c, feet: 9, inches: 7, num: 3, den: 8)
        let start = c.displayValue
        c.setOp(forward)
        enter(&c, feet: 2, inches: 5, num: 1, den: 16)
        c.equals()
        #expect(c.displayValue != start, "\(forward) did nothing")
        c.setOp(back)
        enter(&c, feet: 2, inches: 5, num: 1, den: 16)
        c.equals()
        #expect(c.displayValue == start, "\(forward) then \(back) did not return to the start")
    }

    /// × and ÷ invert too, but only through a SCALAR — dividing a length by a length is a ratio,
    /// which is a different dimension and correctly not a length.
    @Test("x then ÷ by the same scalar returns the length")
    func scaleInverts() {
        var c = TapeCalc()
        enter(&c, feet: 6, inches: 3)
        let start = c.displayValue
        c.setOp(.mul); enterScalar(&c, 4); c.equals()
        #expect(c.currentDimension == .linear, "a length times a bare number is still a length")
        c.setOp(.div); enterScalar(&c, 4); c.equals()
        #expect(c.displayValue == start)
    }

    // MARK: - Dimension transitions — the product, not the diagonal

    /// Multiplying dimensions walks linear → square → cubic and must REFUSE the fourth power
    /// rather than clamp to a plausible-looking lie.
    @Test("repeated dimensioned multiplication walks the dimensions and then refuses")
    func dimensionLadder() {
        var c = TapeCalc()
        enter(&c, feet: 10)
        c.setOp(.mul); enter(&c, feet: 8); c.equals()
        #expect(c.currentDimension == .square)
        #expect(c.areaFt2 != nil)

        c.setOp(.mul); enter(&c, inches: 4); c.equals()
        // THE SHIPPED BUG: `commitEntryIntoAccumulator` reset `accDim` to `.linear` when there was
        // nothing to commit, so this second multiplication computed an AREA again instead of a
        // volume. It is asserted here because the failure is invisible on screen — the number is
        // merely wrong, not absent.
        #expect(c.currentDimension == .cubic, "area x length must be a volume, not another area")
        #expect(c.volumeFt3 != nil)

        c.setOp(.mul); enter(&c, inches: 2); c.equals()
        #expect(c.error == .dimensionOverflow, "a fourth power must be refused, visibly")
    }

    /// Dividing back down the ladder, and the underflow at the bottom.
    @Test("division walks back down and underflows visibly")
    func dimensionLadderDown() {
        var c = TapeCalc()
        enter(&c, feet: 10)
        c.setOp(.mul); enter(&c, feet: 8); c.equals()
        c.setOp(.div); enter(&c, feet: 2); c.equals()
        #expect(c.error == nil)
        #expect(c.currentDimension == .linear, "area ÷ length is a length")

        // A length divided by a length is a RATIO — dimensionless, and correctly `.scalar` rather
        // than an error. (I asserted an underflow here first; the app was right and the test was
        // wrong. Worth keeping the distinction explicit, because the next step down IS an error.)
        c.setOp(.div); enter(&c, feet: 2); c.equals()
        #expect(c.error == nil, "a ratio of two lengths is legal")
        #expect(c.currentDimension == .scalar, "length ÷ length is dimensionless")

        // One more division has nowhere to go: a negative power of length is not a thing the app
        // can display, so it must be refused rather than clamped.
        c.setOp(.div); enter(&c, feet: 2); c.equals()
        #expect(c.error == .dimensionUnderflow, "scalar ÷ length has no dimension — say so")
    }

    /// Every ordered pair of operators, chained. This is where accumulators rot: the second
    /// operator sees state the first left behind.
    @Test("every chained operator pair leaves a defined state",
          arguments: TapeCalc.Op.allCases, TapeCalc.Op.allCases)
    func chainedPairs(first: TapeCalc.Op, second: TapeCalc.Op) {
        var c = TapeCalc()
        enter(&c, feet: 12)
        c.setOp(first);  enterScalar(&c, 3)
        c.setOp(second); enterScalar(&c, 2)
        c.equals()
        // Either a clean answer or a NAMED error — never a pending operator, and never a silent
        // wrong-dimension result.
        #expect(c.pendingOp == nil, "\(first) then \(second) left an operator pending")
        if c.error == nil {
            #expect(c.currentDimension == .linear,
                    "\(first) then \(second) on scalars must stay a length, got \(c.currentDimension)")
        }
    }

    // MARK: - Reset paths

    /// `=` pressed twice must not re-apply the operation.
    @Test("equals is idempotent")
    func equalsTwiceDoesNotReapply() {
        var c = TapeCalc()
        enter(&c, feet: 8)
        c.setOp(.add); enter(&c, feet: 2); c.equals()
        let once = c.displayValue
        c.equals()
        #expect(c.displayValue == once, "the second equals recomputed")
    }

    /// Clear from EVERY entry state. The first clear drops the entry, the second resets the
    /// accumulator — so two clears from anywhere must reach zero.
    @Test("two clears reach zero from any state")
    func clearFromEveryState() {
        var states: [(String, (inout TapeCalc) -> Void)] = [
            ("mid-feet",     { c in self.enterScalar(&c, 12) }),
            ("after feet",   { c in self.enter(&c, feet: 12) }),
            ("mid-fraction", { c in self.enter(&c, inches: 5, num: 1, den: 16) }),
            ("pending op",   { c in self.enter(&c, feet: 8); c.setOp(.mul) }),
            ("after equals", { c in self.enter(&c, feet: 8); c.setOp(.add)
                                    self.enter(&c, feet: 2); c.equals() }),
            ("after error",  { c in self.enter(&c, feet: 8); c.setOp(.div)
                                    self.enterScalar(&c, 0); c.equals() }),
        ]
        for (name, build) in states {
            var c = TapeCalc()
            build(&c)
            c.clear(); c.clear()
            #expect(c.displayValue == .zero, "clear x2 from \(name) did not reach zero")
            #expect(c.error == nil, "clear must dismiss the error (\(name))")
            #expect(c.pendingOp == nil, "clear left an operator pending (\(name))")
        }
    }

    /// Backspace must unwind entry in the exact reverse of how it was typed, and stop at empty
    /// rather than underflowing into the accumulator.
    @Test("backspace unwinds a fraction and stops at empty")
    func backspaceUnwinds() {
        var c = TapeCalc()
        enter(&c, feet: 12, inches: 5, num: 3, den: 16)
        for _ in 0..<20 { c.backspace() }          // far more than were typed
        #expect(c.displayValue == .zero, "backspace did not empty the entry")
        #expect(c.error == nil, "backspace past empty must not error")
    }

    // MARK: - Refusals

    /// Division by zero, from both a scalar and a length, must name itself.
    @Test("division by zero is refused from every entry kind")
    func divideByZero() {
        for tagged in [true, false] {
            var c = TapeCalc()
            enter(&c, feet: 8)
            c.setOp(.div)
            if tagged { enter(&c, inches: 0) } else { enterScalar(&c, 0) }
            c.equals()
            #expect(c.error == .divisionByZero,
                    "÷0 (\(tagged ? "tagged" : "scalar")) was not refused")
        }
    }

    /// A refusal must be RECOVERABLE — the next keystroke has to work, or the app is bricked until
    /// a relaunch.
    @Test("the keypad recovers from every error")
    func errorsAreRecoverable() {
        var c = TapeCalc()
        enter(&c, feet: 8); c.setOp(.div); enterScalar(&c, 0); c.equals()
        #expect(c.error != nil)
        c.clear(); c.clear()
        enter(&c, feet: 3, inches: 6)
        c.setOp(.add); enter(&c, inches: 6); c.equals()
        #expect(c.error == nil, "the keypad stayed broken after an error")
        #expect(c.displayValue == FeetInch(feet: 4, inches: 0, num: 0, den: 1))
    }

    // MARK: - The tape graphic's own branch

    /// `tape` returns nil rather than a fallback for anything that is not a drawable length —
    /// every dimension, and a length past the longest real tape.
    @Test("no tape is offered for anything that is not a drawable length")
    func tapeIsNilOffLadder() {
        var c = TapeCalc()
        enter(&c, feet: 10); c.setOp(.mul); enter(&c, feet: 8); c.equals()
        #expect(c.tape == nil, "an area has no tape")

        c.clear(); c.clear()
        enter(&c, feet: 400)
        #expect(c.tape == nil, "400 ft is longer than any tape in the catalogue")

        c.clear(); c.clear()
        enter(&c, feet: 8)
        #expect(c.tape != nil, "8 ft must land on a real tape")
    }
}

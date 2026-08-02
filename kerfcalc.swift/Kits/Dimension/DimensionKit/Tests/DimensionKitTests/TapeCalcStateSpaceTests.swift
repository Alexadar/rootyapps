import Testing
import Foundation
@testable import DimensionKit

/// `TapeCalc` — the STATE SPACE, not the happy path.
///
/// ## Why this file exists
///
/// The 54 assertions already covering this Kit are all worked examples in the default state: enter
/// two values, press one operator, check the number. Not one of them flips a control twice, chains a
/// second operator, or asks what happens at a boundary. That is how a shipped watch app got a
/// measurement-unit toggle that did nothing — every number correct, every screen rendering, the suite
/// green, because controls get tested in their default state or not at all.
///
/// The same coverage through XCUITest is unaffordable: **~1.1 s per keypad tap**, so the 4×4 chained
/// operator pairs alone would cost minutes on a simulator. Here they cost microseconds, which is why
/// this file can afford the *product* of the states rather than a sample of them.
///
/// | layer | proves |
/// |---|---|
/// | this file | every operator, every dimension transition, every entry mode, every reset path |
/// | the UI suite | that a key reaches this model and this model's answer reaches the screen |
///
/// ## Three tests here are EXPECTED TO FAIL
///
/// `TapeCalc` has no error type, and its refusals are silent clamps — a divide by zero returns the
/// dividend, and a fourth power clamps to cubic. Those tests assert the behaviour that is *owed*, not
/// the behaviour that ships, so they are red until the refusal is implemented. That is deliberate: a
/// test pinned to the current behaviour would certify a wrong answer as correct. See the section at
/// the bottom.
@Suite("TapeCalc — the state space")
struct TapeCalcStateSpaceTests {

    // MARK: - Drivers, mirroring the keypad's vocabulary

    /// Type a measurement: `12`, feet, `4`, inch, `1`, ⁄, `2` → 12' 4-1/2".
    private func enter(_ c: inout TapeCalc, feet: Int? = nil, inches: Int? = nil,
                       num: Int? = nil, den: Int? = nil) {
        if let feet { String(feet).forEach { c.digit(Int(String($0))!) }; c.feetKey() }
        if let inches { String(inches).forEach { c.digit(Int(String($0))!) }; c.inchKey() }
        if let num, let den {
            String(num).forEach { c.digit(Int(String($0))!) }
            c.fractionKey()                                  // numerator FIRST
            String(den).forEach { c.digit(Int(String($0))!) }
        }
    }

    /// A bare number — no Feet/Inch tag, so it stays a scalar multiplier.
    private func enterScalar(_ c: inout TapeCalc, _ n: Int) {
        String(n).forEach { c.digit(Int(String($0))!) }
    }

    // MARK: - Cross product: display precision × typed precision

    /// Entering a fraction FINER than the display precision, at every display precision.
    ///
    /// This is the case a UI test cannot afford — 9 combinations at ~1.1 s per tap — and the one where
    /// a rounding bug hides: a 1/32 typed at a 1/8 display must not round itself away to nothing.
    @Test("every typed denominator survives every display precision",
          arguments: TapeCalc.denominators, TapeCalc.denominators)
    func everyDenominatorSurvives(display: Int64, typed: Int64) {
        var c = TapeCalc()
        c.setDenominator(display)
        enter(&c, inches: 5, num: 1, den: Int(typed))
        c.equals()
        let shown = c.displayValue.formatted(toDenominator: c.denominator)
        // Either the fraction survives, or the display rounds it to a coarser one — but the VALUE
        // must never collapse to a bare 5", which is the keystrokes vanishing with no error.
        #expect(c.displayValue.inchesValue > 5.0,
                "1/\(typed) typed at a 1/\(display) display vanished: got \(shown)")
    }

    /// The denominator is a *display* choice: it must never alter the stored value.
    @Test("changing the display precision does not change the value",
          arguments: TapeCalc.denominators)
    func denominatorIsDisplayOnly(den: Int64) {
        var c = TapeCalc()
        enter(&c, feet: 8, inches: 4, num: 1, den: 2)
        c.equals()
        let before = c.displayValue
        c.setDenominator(den)
        #expect(c.displayValue == before, "setDenominator(\(den)) mutated the value")
    }

    // MARK: - Operators

    /// Every operator commits: pressing it then `=` must never leave the operator pending.
    @Test("every operator commits", arguments: TapeCalc.Op.allCases)
    func everyOperatorCommits(op: TapeCalc.Op) {
        var c = TapeCalc()
        enter(&c, feet: 12)
        c.setOp(op)
        enterScalar(&c, 3)
        c.equals()
        #expect(!c.hasPendingOp, "\(op) was still pending after =")
        #expect(c.tape.isEmpty, "\(op) left a tape line after =")
    }

    /// The inverse property, over every operator that has one.
    ///
    /// This is what catches a sign dropped or a subtraction implemented as an addition — a worked
    /// example cannot, because the wrong implementation still returns a plausible number.
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

    /// `×` then `÷` by the same scalar returns the original length.
    @Test("scaling inverts")
    func scaleInverts() {
        var c = TapeCalc()
        enter(&c, feet: 10, inches: 6)
        let start = c.displayValue
        c.setOp(.mul); enterScalar(&c, 4); c.equals()
        #expect(c.displayValue != start, "× 4 did nothing")
        c.setOp(.div); enterScalar(&c, 4); c.equals()
        #expect(c.displayValue == start, "× 4 ÷ 4 did not return to the start")
    }

    /// Every ordered pair of operators, chained. This is where accumulators rot: the second operator
    /// sees state the first left behind.
    @Test("every chained operator pair leaves a defined state",
          arguments: TapeCalc.Op.allCases, TapeCalc.Op.allCases)
    func chainedPairs(first: TapeCalc.Op, second: TapeCalc.Op) {
        var c = TapeCalc()
        enter(&c, feet: 12)
        c.setOp(first);  enterScalar(&c, 3)
        c.setOp(second); enterScalar(&c, 2)
        c.equals()
        #expect(!c.hasPendingOp, "\(first) then \(second) left an operator pending")
        // Scalars on both sides must keep the running value a length — never silently promote it.
        #expect(c.currentDimension == .linear,
                "\(first) then \(second) on scalars became \(c.currentDimension)")
    }

    // MARK: - The dimension ladder

    /// linear → square → cubic, the app's headline behaviour (10' × 8' = 80 sq ft, × 4" = volume).
    @Test("the dimension ladder climbs")
    func dimensionLadderUp() {
        var c = TapeCalc()
        enter(&c, feet: 10)
        #expect(c.currentDimension == .linear)

        c.setOp(.mul); enter(&c, feet: 8); c.equals()
        #expect(c.currentDimension == .square, "length × length must be an area")
        #expect(c.areaFt2 != nil)
        #expect(abs((c.areaFt2 ?? 0) - 80) < 1e-9, "10' × 8' must be 80 sq ft")

        c.setOp(.mul); enter(&c, inches: 4); c.equals()
        #expect(c.currentDimension == .cubic, "area × length must be a volume, not another area")
        #expect(c.volumeFt3 != nil)
    }

    /// …and descends. Note `length ÷ length` is a RATIO — a scalar, correctly not a length.
    @Test("the dimension ladder descends")
    func dimensionLadderDown() {
        var c = TapeCalc()
        enter(&c, feet: 10)
        c.setOp(.mul); enter(&c, feet: 8); c.equals()      // 80 sq ft
        c.setOp(.div); enter(&c, feet: 8); c.equals()      // ÷ length → back to a length
        #expect(c.currentDimension == .linear, "area ÷ length must be a length")

        c.setOp(.div); enter(&c, feet: 2); c.equals()      // length ÷ length → a ratio
        #expect(c.currentDimension == .scalar, "length ÷ length is a ratio, not a length")
    }

    /// A scalar multiply must not promote the dimension: 10' × 3 is 30 feet, not an area.
    @Test("a bare number stays a scalar multiplier")
    func scalarDoesNotPromote() {
        var c = TapeCalc()
        enter(&c, feet: 10)
        c.setOp(.mul); enterScalar(&c, 3); c.equals()
        #expect(c.currentDimension == .linear, "× 3 must not become an area")
        #expect(c.areaFt2 == nil)
        #expect(abs(c.displayValue.inchesValue - 360) < 1e-9, "10' × 3 must be 30'")
    }

    // MARK: - Reset paths

    /// `clear()` from every entry state the user can be in. Any of these leaving residue means the
    /// next calculation silently starts from the wrong place.
    @Test("clear works from every state")
    func clearFromEveryState() {
        let states: [(String, (inout TapeCalc) -> Void)] = [
            ("mid-number",   { c in self.enterScalar(&c, 12) }),
            ("after feet",   { c in self.enter(&c, feet: 12) }),
            ("mid-fraction", { c in self.enter(&c, inches: 5, num: 1, den: 16) }),
            ("pending op",   { c in self.enter(&c, feet: 8); c.setOp(.mul) }),
            ("after equals", { c in self.enter(&c, feet: 8); c.setOp(.add)
                                    self.enter(&c, feet: 2); c.equals() }),
            ("after divide by zero", { c in self.enter(&c, feet: 8); c.setOp(.div)
                                           self.enterScalar(&c, 0); c.equals() }),
        ]
        for (name, drive) in states {
            var c = TapeCalc()
            drive(&c)
            c.clear(); c.clear()          // first clears the entry, second resets the accumulator
            #expect(c.displayValue.inchesValue == 0, "clear from \(name) left \(c.display)")
            #expect(!c.hasPendingOp, "clear from \(name) left an operator pending")
            #expect(c.currentDimension == .linear, "clear from \(name) left dim \(c.currentDimension)")
        }
    }

    /// `=` pressed twice must not re-apply the operator.
    @Test("equals twice does not reapply")
    func equalsTwiceDoesNotReapply() {
        var c = TapeCalc()
        enter(&c, feet: 8)
        c.setOp(.add); enter(&c, feet: 2); c.equals()
        let once = c.displayValue
        c.equals()
        #expect(c.displayValue == once, "the second = re-applied the operator")
    }

    /// Backspace past the start must stop at empty, not underflow.
    @Test("backspace unwinds without underflowing")
    func backspaceUnwinds() {
        var c = TapeCalc()
        enter(&c, feet: 12, inches: 4)
        for _ in 0..<20 { c.backspace() }
        #expect(c.displayValue.inchesValue == 0, "20 backspaces left \(c.display)")
        c.digit(7)                                   // must still accept input afterwards
        #expect(c.displayValue.inchesValue == 7, "the calculator was bricked by backspacing")
    }

    // MARK: - Entry-mode transitions

    /// Typing after `=` starts a NEW calculation rather than appending to the answer.
    @Test("typing after equals starts fresh")
    func typingAfterEqualsStartsFresh() {
        var c = TapeCalc()
        enter(&c, feet: 8); c.setOp(.add); enter(&c, feet: 2); c.equals()
        let answer = c.displayValue
        enter(&c, feet: 3)
        #expect(c.displayValue != answer, "3' appended to the previous answer instead of replacing it")
        #expect(abs(c.displayValue.inchesValue - 36) < 1e-9, "expected a fresh 3'")
    }

    /// A conversion is a view of the value, never a mutation of it.
    @Test("convert does not mutate the value", arguments: [LengthUnit.millimeter, .meter, .yard])
    func convertDoesNotMutate(unit: LengthUnit) {
        var c = TapeCalc()
        enter(&c, feet: 10)
        c.equals()
        let before = c.displayValue
        c.convert(to: unit)
        #expect(c.displayValue == before, "convert(to: \(unit)) changed the stored value")
    }

    // MARK: - Boundaries and refusals — THESE THREE ARE EXPECTED TO FAIL
    //
    // `TapeCalc` has no error type. Every refusal below is currently a silent clamp that returns a
    // plausible wrong number, which for a tool a tradesman cuts material against is the worst
    // possible failure mode: nothing looks broken. These assert what is OWED. Fixing them needs a
    // visible error state, which invalidates every store screenshot — an owner decision, not a
    // drive-by change. Until then they stay red on purpose.

    /// TapeCalc.swift:135 — `guard bMag != Rational(0) else { return (aMag, aDim) }`.
    /// `12' ÷ 0 =` currently displays `12'`.
    @Test("divide by zero is refused, not answered with the dividend")
    func divideByZeroIsRefused() {
        var c = TapeCalc()
        enter(&c, feet: 12)
        let dividend = c.displayValue
        c.setOp(.div); enterScalar(&c, 0); c.equals()
        #expect(c.displayValue != dividend,
                "12' ÷ 0 returned the dividend (12') as though it were an answer")
    }

    /// TapeCalc.swift:133 — `min(aDim.rawValue + bDim.rawValue, 3)` clamps a 4th power to cubic, so
    /// the app reports a volume for something that is not one.
    @Test("a fourth power is refused, not clamped to cubic")
    func fourthPowerIsRefused() {
        var c = TapeCalc()
        enter(&c, feet: 2)
        c.setOp(.mul); enter(&c, feet: 2); c.equals()      // square
        c.setOp(.mul); enter(&c, feet: 2); c.equals()      // cubic
        c.setOp(.mul); enter(&c, feet: 2); c.equals()      // would be a 4th power
        #expect(c.volumeFt3 == nil,
                "length⁴ clamped to cubic and is being reported as a volume of \(c.volumeFt3 ?? -1) ft³")
    }

    /// TapeCalc.swift:136 — `max(aDim.rawValue - bDim.rawValue, 0)` clamps underflow to scalar, so
    /// dividing an area by a volume quietly yields a plain number.
    @Test("dimension underflow is refused, not clamped to scalar")
    func underflowIsRefused() {
        var c = TapeCalc()
        enter(&c, feet: 4)
        c.setOp(.mul); enter(&c, feet: 4); c.equals()      // square
        // ÷ a cubic value: 2 - 3 = -1, clamped to .scalar rather than refused.
        var vol = TapeCalc()
        enter(&vol, feet: 2)
        vol.setOp(.mul); enter(&vol, feet: 2); vol.equals()
        vol.setOp(.mul); enter(&vol, feet: 2); vol.equals()
        #expect(vol.currentDimension == .cubic, "precondition: needed a cubic value")

        c.setOp(.div); enter(&c, feet: 2); c.equals()      // area ÷ length = length (legal)
        c.setOp(.div); enter(&c, feet: 2); c.equals()      // length ÷ length = scalar (legal)
        c.setOp(.div); enter(&c, feet: 2); c.equals()      // scalar ÷ length — UNDERFLOW, owed a refusal
        #expect(c.currentDimension != .scalar,
                "scalar ÷ length clamped to scalar instead of refusing the underflow")
    }
}

import Foundation

/// Feet-inch-fraction calculator, Construction-Master style, with no UI.
///
/// Immediate execution: type digits, tag them Feet / Inch / fraction, choose an operator, enter the
/// next value, `=`. The running value carries a `Dim`, so multiplying two lengths gives an area
/// and the feet/inch keys stay live on **every** operand.
///
/// That last point is the whole reason this type differs from the one it was ported from. In the
/// incumbent, dimensioned multiplication has never worked, for twelve years:
///
/// > *"I hit the 'X' multiplication symbol then go to put in the 2nd measurement of 11 feet 4
/// > inches, I cannot do it because the **FEET and INCHES buttons are GRAYED OUT** ... it works
/// > with subtraction and addition, just not multiplication and division."* — 2★ 2014-08-04
/// > *"I can not multiply 12'-4" X 12'-4" ... I need feet and inches by feet and inches."* — 2★ 2016-09-24
/// > *"Awful app can't even multiply for square footage."* — 1★ 2025-11-22
///
/// Pure value type, no Foundation UI, no SwiftUI.
public struct TapeCalc: Sendable {
    public enum Op: String, Sendable, CaseIterable {
        case add = "+", sub = "−", mul = "×", div = "÷"
    }

    /// Why the last operation could not be performed. `nil` means the state is good.
    ///
    /// Errors are surfaced, never swallowed by clamping — `12' × 12' × 12' × 12'` is not a volume.
    public enum CalcError: String, Sendable {
        case dimensionOverflow  = "beyond cubic"
        case dimensionUnderflow = "not a dimension"
        case divisionByZero     = "divide by zero"
    }

    public var denominator: Int64 = 16
    public var rule: RoundingRule = .halfToEven

    private var feet = "", inch = "", frNum = "", frDen = "", buf = ""
    private var typingFraction = false          // a fraction is being typed: numerator FIRST
    private var hasEntry = false
    private var entryTagged = false             // Feet/Inch/fraction pressed → linear; else scalar
    private var acc: FeetInch?
    private var accDim: Dim = .linear
    private var op: Op?
    private var justEvaluated = false

    public private(set) var error: CalcError?

    public init() {}

    // MARK: - Entry

    public mutating func digit(_ d: Int) {
        precondition((0...9).contains(d), "digit must be 0...9")
        if justEvaluated { resetAll() }
        error = nil
        if typingFraction {
            frDen += String(d)
            raiseDenominatorIfFinerWasTyped()
        } else {
            buf += String(d)
        }
        hasEntry = true
    }

    /// Typing a fraction finer than the display precision raises the precision to match.
    ///
    /// Without this the app silently throws away what you just typed: at a 1/16 display, entering
    /// 5" 1/32 rounds straight back to 5" — the 1/32 is exactly half a sixteenth, so it rounds to
    /// even and vanishes. You would watch your own keystrokes disappear. Never discard entered
    /// precision; widen to hold it instead. (Coarser fractions are left alone: typing 1/2 at a
    /// 1/16 display is not a request to lose resolution.)
    private mutating func raiseDenominatorIfFinerWasTyped() {
        guard let typed = Int64(frDen), typed > denominator,
              Self.denominators.contains(typed) else { return }
        denominator = typed
    }

    /// The precisions the app offers, and the only ones entry will auto-raise to.
    public static let denominators: [Int64] = [2, 4, 8, 16, 32, 64]

    public mutating func feetKey() {
        if justEvaluated { resetAll() }
        error = nil
        if !buf.isEmpty { feet = buf; buf = "" }
        hasEntry = true; entryTagged = true
    }

    public mutating func inchKey() {
        if justEvaluated { resetAll() }
        error = nil
        if !buf.isEmpty && !typingFraction { inch = buf; buf = "" }
        hasEntry = true; entryTagged = true
    }

    /// The `/` key. **Numerator first**, then this key, then the denominator — the way a fraction
    /// is spoken and written. The incumbent forces denominator-first through a spinner and three
    /// separate reviewers call it backwards:
    /// *"wish it didn't make me do the denominator first"* (5★ 2022-02-04);
    /// *"This is backwards and takes a slight bit of mental adjustment"* (4★ 2021-01-03);
    /// *"too time consuming to use the fraction spin things in the shop"* (3★ 2019-06-04).
    public mutating func fractionKey() {
        if justEvaluated { resetAll() }
        error = nil
        if !buf.isEmpty { frNum = buf; buf = ""; typingFraction = true }
        hasEntry = true; entryTagged = true
    }

    public mutating func setOp(_ o: Op) {
        error = nil
        commitEntryIntoAccumulator()
        guard error == nil else { return }
        op = o; justEvaluated = false
        clearEntry()
    }

    public mutating func equals() {
        error = nil
        guard op != nil else { commitEntryIntoAccumulator(); justEvaluated = true; return }
        commitEntryIntoAccumulator()
        justEvaluated = true
        clearEntry()
    }

    public mutating func clear() {
        if hasEntry || !buf.isEmpty { clearEntry() } else { resetAll() }
        error = nil
    }

    public mutating func backspace() {
        error = nil
        if typingFraction {
            if !frDen.isEmpty { frDen.removeLast() }
            else { typingFraction = false; buf = frNum; frNum = "" }
        } else if !buf.isEmpty { buf.removeLast() }
        else if !inch.isEmpty { inch.removeLast() }
        else if !feet.isEmpty { feet.removeLast() }
    }

    public mutating func setDenominator(_ d: Int64) {
        precondition(d > 0, "denominator must be positive")
        denominator = d
    }

    /// Seed the readout with an existing length — this is how a previous result is recalled into
    /// the next calculation: *"I would like to be able click on a measurement I just calculated and
    /// be able to add or subtract from that as well"* (5★ 2020-04-17).
    public mutating func preload(_ v: FeetInch) {
        resetAll(); acc = v; accDim = .linear; justEvaluated = true
    }

    // MARK: - Output

    /// The linear magnitude (inches) of whatever is on screen.
    public var displayValue: FeetInch { hasEntry ? buildEntry() : (acc ?? .zero) }

    public var currentDimension: Dim { hasEntry ? .linear : accDim }

    /// Area in ft², when the running value is square.
    public var areaFt2: Double? {
        (!hasEntry && accDim == .square) ? (acc ?? .zero).inchesValue / Dim.square.displayDivisor : nil
    }

    /// Volume in ft³, when the running value is cubic.
    public var volumeFt3: Double? {
        (!hasEntry && accDim == .cubic) ? (acc ?? .zero).inchesValue / Dim.cubic.displayDivisor : nil
    }

    /// The tape the result should be drawn on, or `nil` when it is not a length that fits one.
    /// See `Tape` — a `nil` means the graphic is not drawn at all.
    public var tape: Tape? {
        guard !hasEntry || entryTagged, currentDimension == .linear else { return nil }
        return Tape.smallest(for: displayValue)
    }

    public var pendingOp: Op? { op }

    // MARK: - Internals

    private func buildEntry() -> FeetInch {
        let f = Int64(feet) ?? 0
        var i = Int64(inch) ?? 0
        if !buf.isEmpty && !typingFraction { i += Int64(buf) ?? 0 }
        let n = Int64(frNum) ?? 0
        let dRaw = Int64(frDen) ?? 0
        let d = dRaw == 0 ? 1 : dRaw
        let nn = dRaw == 0 ? 0 : n
        return FeetInch(feet: f, inches: i, num: nn, den: d)
    }

    /// Combine the accumulator with the entry. Returns `nil` — and sets `error` — when the
    /// dimensions do not admit the operation, rather than clamping to a plausible-looking lie.
    private mutating func combine(_ o: Op, _ a: FeetInch, _ aDim: Dim,
                                  _ b: FeetInch, _ bDim: Dim) -> (FeetInch, Dim)? {
        switch o {
        case .add: return (a + b, aDim)
        case .sub: return (a - b, aDim)
        case .mul:
            guard let d = aDim * bDim else { error = .dimensionOverflow; return nil }
            return (FeetInch(inches: a.inches * b.inches), d)
        case .div:
            guard !b.inches.isZero else { error = .divisionByZero; return nil }
            guard let d = aDim / bDim else { error = .dimensionUnderflow; return nil }
            return (FeetInch(inches: a.inches / b.inches), d)
        }
    }

    private mutating func commitEntryIntoAccumulator() {
        if let o = op, let a = acc {
            let entry = hasEntry ? buildEntry() : a
            // A bare number under × or ÷ is a scalar multiplier; a tagged value is a length.
            let entryDim: Dim = (hasEntry && !entryTagged) ? .scalar : .linear
            let bDim: Dim = (o == .mul || o == .div) ? entryDim : .linear
            guard let r = combine(o, a, accDim, entry, bDim) else { return }
            acc = r.0; accDim = r.1; op = nil
        } else if hasEntry {
            acc = buildEntry(); accDim = .linear
        }
        // Otherwise there is nothing to commit — no pending operator and no new entry — so the
        // accumulator AND ITS DIMENSION are left alone. Overwriting `accDim` with `.linear` here
        // is what made `10' × 8' = ` followed by `× 4"` compute an area again instead of a volume.
    }

    private mutating func clearEntry() {
        feet = ""; inch = ""; frNum = ""; frDen = ""; buf = ""
        typingFraction = false; hasEntry = false; entryTagged = false
    }

    private mutating func resetAll() {
        clearEntry(); acc = nil; accDim = .linear; op = nil; justEvaluated = false; error = nil
    }
}

public extension FeetInch {
    static var zero: FeetInch { FeetInch(inches: Rational(0)) }
}

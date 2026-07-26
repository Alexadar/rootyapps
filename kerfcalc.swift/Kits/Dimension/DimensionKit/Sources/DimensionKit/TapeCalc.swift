import Foundation

/// Pure feet-inch-fraction tape calculator (no SwiftUI), Construction-Master style. Immediate
/// execution: type digits, tag them Feet / Inch / `/`, choose an operator, enter the next value, `=`.
///
/// Dimension math (CM-Pro parity): the running value carries a dimension — linear, square, or cubic.
/// A number entered WITHOUT a Feet/Inch tag is a **scalar** (a multiplier); a tagged value is linear.
///   linear × linear = square (10' × 8' = 80 sq ft) · square × linear = cubic (× 4" = 26.67 cu ft)
///   any × scalar = same dimension (10' × 3 = 30') · linear ÷ linear = scalar ratio · cubic ÷ square = linear
public struct TapeCalc {
    public enum Op: String, Sendable { case add = "+", sub = "−", mul = "×", div = "÷" }
    public enum Dim: Int, Sendable { case scalar = 0, linear = 1, square = 2, cubic = 3 }

    public var denominator: Int64 = 16

    private var feet = "", inch = "", frNum = "", frDen = "", buf = ""
    private var typingDen = false
    private var hasEntry = false
    private var entryTagged = false             // Feet/Inch/frac pressed → linear; else scalar
    private var acc: FeetInch? = nil            // magnitude in inches^dim, held exactly as a Rational
    private var accDim: Dim = .linear
    private var op: Op? = nil
    private var justEvaluated = false
    private var conversion: String? = nil

    private var riseReg: FeetInch? = nil
    private var runReg: FeetInch? = nil

    public init() {}

    // MARK: input
    public mutating func digit(_ d: Int) {
        if justEvaluated { resetAll() }
        conversion = nil
        if typingDen { frDen += String(d) } else { buf += String(d) }
        hasEntry = true
    }
    public mutating func feetKey() { if justEvaluated { resetAll() }; conversion = nil; if !buf.isEmpty { feet = buf; buf = "" }; hasEntry = true; entryTagged = true }
    public mutating func inchKey() { if justEvaluated { resetAll() }; conversion = nil; if !buf.isEmpty && !typingDen { inch = buf; buf = "" }; hasEntry = true; entryTagged = true }
    public mutating func fractionKey() { if justEvaluated { resetAll() }; conversion = nil; if !buf.isEmpty { frNum = buf; buf = ""; typingDen = true }; hasEntry = true; entryTagged = true }

    public mutating func setOp(_ o: Op) {
        conversion = nil
        commitEntryIntoAccumulator()
        op = o; justEvaluated = false
        clearEntry()
    }

    public mutating func equals() {
        conversion = nil
        guard op != nil else { commitEntryIntoAccumulator(); justEvaluated = true; return }
        commitEntryIntoAccumulator()
        justEvaluated = true; clearEntry()
    }

    public mutating func clear() {
        if hasEntry || !buf.isEmpty { clearEntry() } else { resetAll() }
        conversion = nil
    }

    public mutating func backspace() {
        conversion = nil
        if typingDen { if !frDen.isEmpty { frDen.removeLast() } else { typingDen = false; buf = frNum; frNum = "" } }
        else if !buf.isEmpty { buf.removeLast() }
        else if !inch.isEmpty { inch.removeLast() }
        else if !feet.isEmpty { feet.removeLast() }
    }

    public mutating func convert(to unit: LengthUnit) {
        let v = displayValue.inchesValue
        let out = Units.convert(v, from: .inch, to: unit)
        let s = abs(out - out.rounded()) < 1e-9 ? String(Int(out.rounded())) : String((out * 1000).rounded() / 1000)
        conversion = "\(s) \(unit.symbol)"
    }

    public mutating func setDenominator(_ d: Int64) { denominator = d }

    /// Seed the readout with an existing length for editing (first digit replaces it).
    public mutating func preload(_ v: FeetInch) { resetAll(); acc = v; accDim = .linear; justEvaluated = true }

    // MARK: right-triangle registers
    public mutating func storeRise() { riseReg = displayValue; clearEntry(); conversion = nil }
    public mutating func storeRun() { runReg = displayValue; clearEntry(); conversion = nil }
    public mutating func solveDiagonal() {
        guard let r = riseReg, let u = runReg else { return }
        let d = (r.inchesValue * r.inchesValue + u.inchesValue * u.inchesValue).squareRoot()
        acc = FeetInch.approx(inches: d, den: denominator); accDim = .linear
        op = nil; justEvaluated = true; clearEntry(); conversion = nil
    }
    public mutating func solvePitch() {
        guard let r = riseReg, let u = runReg, u.inchesValue != 0 else { return }
        conversion = String(format: "%.2f", r.inchesValue / u.inchesValue * 12) + " /12"
    }

    // MARK: output
    /// The linear magnitude (inches) — used by registers/convert/field-commit.
    public var displayValue: FeetInch { hasEntry ? buildEntry() : (acc ?? zero) }
    public var currentDimension: Dim { hasEntry ? .linear : accDim }
    /// Area in ft² when the running value is square, else nil.
    public var areaFt2: Double? { (!hasEntry && accDim == .square) ? (acc ?? zero).inchesValue / 144 : nil }
    /// Volume in ft³ when the running value is cubic, else nil.
    public var volumeFt3: Double? { (!hasEntry && accDim == .cubic) ? (acc ?? zero).inchesValue / 1728 : nil }

    public var display: String {
        if let conversion { return conversion }
        if hasEntry { return buildEntry().formatted(toDenominator: denominator) }
        return format(acc ?? zero, dim: accDim)
    }
    public var tape: String { op.map { "\(format(acc ?? zero, dim: accDim))  \($0.rawValue)" } ?? "" }
    public var riseDisplay: String? { riseReg?.formatted(toDenominator: denominator) }
    public var runDisplay: String? { runReg?.formatted(toDenominator: denominator) }

    // MARK: internals
    private var zero: FeetInch { FeetInch(inches: Rational(0)) }

    private func format(_ v: FeetInch, dim: Dim) -> String {
        switch dim {
        case .square: return trim(v.inchesValue / 144) + " sq ft"
        case .cubic:  return trim(v.inchesValue / 1728) + " cu ft"
        case .scalar: return trim(v.inchesValue)
        case .linear: return v.formatted(toDenominator: denominator)
        }
    }
    private func trim(_ x: Double) -> String {
        abs(x - x.rounded()) < 1e-6 ? String(Int(x.rounded())) : String(format: "%.2f", x)
    }

    /// Combine accumulator (mag,dim) with the entry (mag,dim) under `o`.
    private func combine(_ o: Op, _ aMag: Rational, _ aDim: Dim, _ bMag: Rational, _ bDim: Dim) -> (Rational, Dim) {
        switch o {
        case .add: return (aMag + bMag, aDim)
        case .sub: return (aMag - bMag, aDim)
        case .mul: return (aMag * bMag, Dim(rawValue: min(aDim.rawValue + bDim.rawValue, 3)) ?? .cubic)
        case .div:
            guard bMag != Rational(0) else { return (aMag, aDim) }
            return (aMag / bMag, Dim(rawValue: max(aDim.rawValue - bDim.rawValue, 0)) ?? .scalar)
        }
    }

    private mutating func commitEntryIntoAccumulator() {
        let entryMag = currentEntryOrZero().inches
        // A bare number under × / ÷ is a scalar multiplier; a tagged value is linear.
        let entryDim: Dim = (hasEntry && !entryTagged) ? .scalar : .linear
        if let o = op, let a = acc {
            let bDim: Dim = (o == .mul || o == .div) ? entryDim : .linear
            let r = combine(o, a.inches, accDim, entryMag, bDim)
            acc = FeetInch(inches: r.0); accDim = r.1; op = nil
        } else {
            acc = FeetInch(inches: entryMag); accDim = .linear
        }
    }

    private func buildEntry() -> FeetInch {
        let f = Int64(feet) ?? 0
        var i = Int64(inch) ?? 0
        if !buf.isEmpty && !typingDen { i += Int64(buf) ?? 0 }
        let n = Int64(frNum) ?? 0
        let dRaw = Int64(frDen) ?? 0
        let d = dRaw == 0 ? 1 : dRaw
        let nn = dRaw == 0 ? 0 : n
        return FeetInch(feet: f, inches: i, num: nn, den: d)
    }
    private func currentEntryOrZero() -> FeetInch { hasEntry ? buildEntry() : (acc ?? zero) }
    private mutating func clearEntry() { feet = ""; inch = ""; frNum = ""; frDen = ""; buf = ""; typingDen = false; hasEntry = false; entryTagged = false }
    private mutating func resetAll() { clearEntry(); acc = nil; accDim = .linear; op = nil; justEvaluated = false; conversion = nil; riseReg = nil; runReg = nil }
}

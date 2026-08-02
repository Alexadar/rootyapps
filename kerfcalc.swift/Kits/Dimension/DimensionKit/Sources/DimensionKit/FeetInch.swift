import Foundation

/// A linear dimension stored as an **exact** number of inches (`Rational`), the way a carpenter
/// thinks in feet-inch-fraction. Parse `12' 6 1/2"`, add/subtract dimensions, scale by a number,
/// and format back to the nearest set fraction — all without ever touching a decimal.
public struct FeetInch: Equatable, Comparable, CustomStringConvertible {
    /// Total length in inches, exact.
    public var inches: Rational

    public init(inches: Rational) { self.inches = inches }

    /// Build from a decimal inch value, rounded to the nearest `1/den` — for results of irrational
    /// operations (√, trig) that can't be an exact rational. Keeps the readout on a clean fraction.
    public static func approx(inches x: Double, den: Int64 = 16) -> FeetInch {
        let d = den > 0 ? den : 1
        let k = Int64((x * Double(d)).rounded())
        return FeetInch(inches: Rational(k, d))
    }

    /// Build from mixed feet / whole-inch / fractional-inch parts (e.g. 12 ft, 6 in, 1/2).
    public init(feet: Int64 = 0, inches wholeInches: Int64 = 0, num: Int64 = 0, den: Int64 = 1) {
        let sign: Int64 = feet < 0 || wholeInches < 0 || num < 0 ? -1 : 1
        let mag = Rational(abs(feet) * 12 + abs(wholeInches)) + Rational(abs(num), den)
        self.inches = sign < 0 ? -mag : mag
    }

    public var feetValue: Double { inches.doubleValue / 12 }
    public var inchesValue: Double { inches.doubleValue }
    public var description: String { formatted() }

    // MARK: Dimension arithmetic

    public static func + (a: FeetInch, b: FeetInch) -> FeetInch { FeetInch(inches: a.inches + b.inches) }
    public static func - (a: FeetInch, b: FeetInch) -> FeetInch { FeetInch(inches: a.inches - b.inches) }
    public static prefix func - (a: FeetInch) -> FeetInch { FeetInch(inches: -a.inches) }

    /// Scale a dimension by a dimensionless number (e.g. ×3 joists, half a span).
    public static func * (a: FeetInch, k: Rational) -> FeetInch { FeetInch(inches: a.inches * k) }
    public static func / (a: FeetInch, k: Rational) -> FeetInch { FeetInch(inches: a.inches / k) }

    /// Ratio of two dimensions — a pure number (how many of `b` fit in `a`).
    public static func / (a: FeetInch, b: FeetInch) -> Rational { a.inches / b.inches }

    public static func < (a: FeetInch, b: FeetInch) -> Bool { a.inches < b.inches }

    // MARK: Rounding & formatting

    /// A copy rounded to the nearest `1/denominator` inch.
    public func rounded(toDenominator d: Int64) -> FeetInch { FeetInch(inches: inches.rounded(toDenominator: d)) }

    /// Format as feet-inch-fraction rounded to `1/denominator`, e.g. `12' 6-1/2"`.
    /// Negative dimensions get a leading `-`; whole feet / whole inches / fraction are omitted
    /// when zero (but `0"` shows for a true zero).
    public func formatted(toDenominator d: Int64 = 16) -> String {
        let r = inches.rounded(toDenominator: d)
        let negative = r.num < 0
        let totalSixteenthsLike = r.num < 0 ? -r.num : r.num     // magnitude, numerator over r.den
        // magnitude in inches as an exact fraction m/den
        let m = totalSixteenthsLike, den = r.den
        let wholeInchesTotal = m / den
        let fracNum = m % den                                    // remaining fraction numerator over den
        let feet = wholeInchesTotal / 12
        let inch = wholeInchesTotal % 12

        var parts: [String] = []
        if feet != 0 { parts.append("\(feet)'") }
        var inchPart = ""
        if inch != 0 { inchPart = "\(inch)" }
        if fracNum != 0 {
            inchPart += inchPart.isEmpty ? "\(fracNum)/\(den)" : "-\(fracNum)/\(den)"
        }
        if !inchPart.isEmpty { parts.append("\(inchPart)\"") }
        if parts.isEmpty { return "0\"" }
        return (negative ? "-" : "") + parts.joined(separator: " ")
    }

    // MARK: Parsing

    /// Parse feet-inch-fraction text. Accepts, in any combination:
    /// `12'`, `6"`, `1/2"`, `6 1/2"`, `12' 6"`, `12' 6 1/2"`, `12'6-1/2"`, plain inches `18`,
    /// and a leading `-`. Feet marked with `'` or `ft`, inches with `"` or `in`.
    /// Returns `nil` on anything it cannot fully consume.
    public static func parse(_ raw: String) -> FeetInch? {
        var s = raw.trimmingCharacters(in: .whitespaces).lowercased()
        if s.isEmpty { return nil }
        var sign: Int64 = 1
        if s.hasPrefix("-") { sign = -1; s.removeFirst() }
        s = s.replacingOccurrences(of: "ft", with: "'")
             .replacingOccurrences(of: "in", with: "\"")
             .replacingOccurrences(of: "-", with: " ")   // 6-1/2" → 6 1/2"

        var feet: Rational = Rational(0)
        var inchesAccum: Rational = Rational(0)
        var sawAnything = false

        // Feet: digits (possibly decimal) before a `'`
        if let q = s.firstIndex(of: "'") {
            let feetStr = String(s[s.startIndex..<q]).trimmingCharacters(in: .whitespaces)
            guard let f = parseNumber(feetStr) else { return nil }
            feet = f; sawAnything = true
            s = String(s[s.index(after: q)...])
        }

        // Inches: strip a trailing " if present, then parse "W", "N/D", or "W N/D"
        s = s.replacingOccurrences(of: "\"", with: " ").trimmingCharacters(in: .whitespaces)
        if !s.isEmpty {
            let toks = s.split(separator: " ").map(String.init)
            switch toks.count {
            case 1:
                guard let v = parseNumberOrFraction(toks[0]) else { return nil }
                inchesAccum = v; sawAnything = true
            case 2:
                guard let w = parseNumber(toks[0]), let fr = parseFraction(toks[1]) else { return nil }
                inchesAccum = w + fr; sawAnything = true
            default:
                return nil
            }
        }

        guard sawAnything else { return nil }
        let total = feet * Rational(12) + inchesAccum
        return FeetInch(inches: sign < 0 ? -total : total)
    }

    // "12", "12.5" → Rational (decimal allowed for feet/inches wholes)
    private static func parseNumber(_ t: String) -> Rational? {
        if t.isEmpty { return Rational(0) }
        if let i = Int64(t) { return Rational(i) }
        // decimal
        guard let dot = t.firstIndex(of: "."), t.filter({ $0 == "." }).count == 1 else { return nil }
        let intPart = String(t[t.startIndex..<dot])
        let fracPart = String(t[t.index(after: dot)...])
        guard fracPart.allSatisfy(\.isNumber), intPart.isEmpty || intPart.allSatisfy(\.isNumber) else { return nil }
        let whole = Int64(intPart.isEmpty ? "0" : intPart) ?? 0
        guard let fracDigits = Int64(fracPart.isEmpty ? "0" : fracPart) else { return nil }
        var den: Int64 = 1
        for _ in 0..<fracPart.count { den *= 10 }
        return Rational(whole) + Rational(fracDigits, den)
    }

    private static func parseFraction(_ t: String) -> Rational? {
        let parts = t.split(separator: "/").map(String.init)
        guard parts.count == 2, let n = Int64(parts[0]), let d = Int64(parts[1]), d != 0 else { return nil }
        return Rational(n, d)
    }

    private static func parseNumberOrFraction(_ t: String) -> Rational? {
        t.contains("/") ? parseFraction(t) : parseNumber(t)
    }
}

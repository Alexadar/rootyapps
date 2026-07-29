import Foundation

/// A linear dimension stored as an **exact** number of inches (`Rational`), the way a tradesman
/// reads a tape: feet, inches, and a fraction. Parse `12' 6 1/2"`, add and subtract dimensions,
/// scale by a number, and format back to a chosen fraction — never touching a decimal.
///
/// Pure, stateless.
public struct FeetInch: Equatable, Hashable, Comparable, CustomStringConvertible, Sendable {
    /// Total length in inches, exact.
    public var inches: Rational

    public init(inches: Rational) { self.inches = inches }

    /// Build from mixed feet / whole-inch / fractional-inch parts (e.g. 12 ft, 6 in, 1/2).
    /// A negative in any component makes the whole dimension negative.
    public init(feet: Int64 = 0, inches wholeInches: Int64 = 0, num: Int64 = 0, den: Int64 = 1) {
        let negative = feet < 0 || wholeInches < 0 || num < 0
        let mag = Rational(feet.magnitudeInt64 * 12 + wholeInches.magnitudeInt64)
                + Rational(num.magnitudeInt64, den)
        self.inches = negative ? -mag : mag
    }

    /// Build from a decimal inch value, rounded to the nearest `1/den` — for results of irrational
    /// operations (√, trig) that cannot be an exact rational. Keeps the readout on a clean fraction.
    ///
    /// The rounding rule is explicit here for the same reason it is everywhere else: a √ result
    /// landing exactly on a half-sixteenth must resolve the same way the rest of the app does.
    public static func approx(inches x: Double, den: Int64 = 16, rule: RoundingRule = .halfToEven) -> FeetInch {
        let d = den > 0 ? den : 1
        let scaled = x * Double(d)
        guard scaled.isFinite, scaled.magnitude < 9.2e18 else { return FeetInch(inches: Rational(0)) }
        // Round the scaled value under the same rule, then divide back down.
        let floor = scaled.rounded(.down)
        let frac = scaled - floor
        var k = Int64(floor)
        if frac > 0.5 {
            k += 1
        } else if frac == 0.5 {
            switch rule {
            // Candidates are k and k+1. Away from zero is k+1 when positive, and k when negative
            // (floor has already gone away from zero on the negative side).
            case .halfAwayFromZero: if scaled > 0 { k += 1 }
            case .halfToEven:       if k % 2 != 0 { k += 1 }   // take whichever candidate is even
            }
        }
        return FeetInch(inches: Rational(k, d))
    }

    public var feetValue: Double { inches.doubleValue / 12 }
    public var inchesValue: Double { inches.doubleValue }
    public var isNegative: Bool { inches.num < 0 }
    public var description: String { formatted() }

    // MARK: - Dimension arithmetic

    public static func + (a: FeetInch, b: FeetInch) -> FeetInch { FeetInch(inches: a.inches + b.inches) }
    public static func - (a: FeetInch, b: FeetInch) -> FeetInch { FeetInch(inches: a.inches - b.inches) }
    public static prefix func - (a: FeetInch) -> FeetInch { FeetInch(inches: -a.inches) }

    /// Scale by a dimensionless number (×3 joists, half a span).
    public static func * (a: FeetInch, k: Rational) -> FeetInch { FeetInch(inches: a.inches * k) }
    public static func / (a: FeetInch, k: Rational) -> FeetInch { FeetInch(inches: a.inches / k) }

    /// Ratio of two dimensions — a pure number (how many of `b` fit in `a`).
    public static func / (a: FeetInch, b: FeetInch) -> Rational { a.inches / b.inches }

    public static func < (a: FeetInch, b: FeetInch) -> Bool { a.inches < b.inches }

    // MARK: - Rounding & formatting

    public func rounded(toDenominator d: Int64, rule: RoundingRule = .halfToEven) -> FeetInch {
        FeetInch(inches: inches.rounded(toDenominator: d, rule: rule))
    }

    /// Format as feet-inch-fraction, e.g. `12' 6-1/2"`, `-7-1/8"`, `0"`.
    ///
    /// The sign is taken from the magnitude and re-applied, never from a truncating division —
    /// that is the bug behind the incumbent's *"it would show -7 7/8 but it should be -7 1/8 due
    /// to the directional problem"* (5★ 2016-04-25). `FeetInchTests` asserts the round-trip.
    public func formatted(toDenominator d: Int64 = 16, rule: RoundingRule = .halfToEven) -> String {
        let r = inches.rounded(toDenominator: d, rule: rule)
        let negative = r.num < 0
        let m = Int64(r.num.magnitude)            // work in magnitude, re-apply the sign at the end
        let den = r.den
        let wholeInchesTotal = m / den
        let fracNum = m % den
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

    /// Decimal inches, on request only. Fractions are the default everywhere — the trade's own
    /// convention, and defect ④: *"Normal carpentrs do not use decimals we use fractions."*
    public func formattedDecimalInches(places: Int = 4) -> String {
        String(format: "%.\(places)f\"", inchesValue)
    }

    // MARK: - Parsing

    /// Parse feet-inch-fraction text. Accepts, in any combination:
    /// `12'`, `6"`, `1/2"`, `6 1/2"`, `12' 6"`, `12' 6 1/2"`, `12'6-1/2"`, plain inches `18`,
    /// `ft`/`in` word forms, and a leading `-`. Returns `nil` on anything it cannot fully consume.
    public static func parse(_ raw: String) -> FeetInch? {
        var s = raw.trimmingCharacters(in: .whitespaces).lowercased()
        if s.isEmpty { return nil }
        var negative = false
        if s.hasPrefix("-") { negative = true; s.removeFirst() }
        s = s.replacingOccurrences(of: "ft", with: "'")
             .replacingOccurrences(of: "in", with: "\"")
             .replacingOccurrences(of: "-", with: " ")      // 6-1/2" → 6 1/2"

        var feet = Rational(0)
        var inchesAccum = Rational(0)
        var sawAnything = false

        if let q = s.firstIndex(of: "'") {
            let feetStr = String(s[s.startIndex..<q]).trimmingCharacters(in: .whitespaces)
            guard let f = parseNumber(feetStr) else { return nil }
            feet = f; sawAnything = true
            s = String(s[s.index(after: q)...])
        }

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
        return FeetInch(inches: negative ? -total : total)
    }

    private static func parseNumber(_ t: String) -> Rational? {
        if t.isEmpty { return Rational(0) }
        if let i = Int64(t) { return Rational(i) }
        guard let dot = t.firstIndex(of: "."), t.filter({ $0 == "." }).count == 1 else { return nil }
        let intPart = String(t[t.startIndex..<dot])
        let fracPart = String(t[t.index(after: dot)...])
        guard fracPart.allSatisfy(\.isNumber), intPart.isEmpty || intPart.allSatisfy(\.isNumber) else { return nil }
        guard fracPart.count <= 18 else { return nil }
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

extension Int64 {
    /// `magnitude` as an `Int64`, saturating at `Int64.max` so `Int64.min` cannot trap.
    var magnitudeInt64: Int64 { self == Int64.min ? Int64.max : (self < 0 ? -self : self) }
}

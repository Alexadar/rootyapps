import Foundation

/// How a value exactly halfway between two representable results is resolved.
///
/// The two rules disagree, observably, and the disagreement is published:
/// a dressed lumber thickness of 7-1/2 in is 190.5 mm exactly. `halfToEven` gives 190;
/// `halfAwayFromZero` gives 191. **NIST PS 20-20 Table 3 publishes 190.**
///
/// - `halfToEven` is the default and is the rule carrying a published oracle:
///   NIST SP 811 §B.7.1 rule 3 — *"the digit preceding the 5 is unchanged if it is even and
///   increased by 1 if it is odd. (Note that this means that the final digit is always even.)"* —
///   and, independently for lumber, NIST PS 20-20 App. B §B1.
/// - `halfAwayFromZero` is the symmetric carpentry convention used by `kerfcalc`, offered so a
///   trade user can match a Construction-Master-style calculator. It has no published authority.
///
/// IMPORTANT — the limit of the citation. SP 811 §B.7.1 rounds *decimal digits* and PS 20-20 §B1
/// rounds *millimetres*. **Neither publishes a rule for rounding to a binary fraction denominator
/// (1/16, 1/32, 1/64).** What is cited is the tie-breaking rule; applying it at a fraction
/// denominator is this app's extension by analogy, and no test claims otherwise.
public enum RoundingRule: String, CaseIterable, Sendable {
    /// NIST SP 811 §B.7.1 / PS 20-20 §B1. Ties resolve to the even neighbour.
    case halfToEven
    /// The symmetric carpentry convention. Ties resolve away from zero. No published authority.
    case halfAwayFromZero
}

/// Exact rational number (`Int64` numerator/denominator, always reduced, denominator > 0).
///
/// Feet-inch-fraction carpentry math must be **exact** — `1/3 + 1/3 + 1/3` has to be `1`, and a
/// value rounded to the nearest 1/16 must land on the true nearest sixteenth, never on a binary
/// floating-point approximation. All arithmetic here is integer arithmetic on num/den, so it is
/// exact for every value the domain produces.
///
/// Pure, stateless. Every operator cross-reduces before multiplying, which keeps intermediate
/// products small, and every product is overflow-checked — a silently wrapped `Int64` would be a
/// wrong measurement, which is the one failure this app exists to prevent.
public struct Rational: Equatable, Hashable, Comparable, CustomStringConvertible, Sendable {
    public let num: Int64
    public let den: Int64   // invariant: den > 0, gcd(|num|, den) == 1

    public init(_ n: Int64, _ d: Int64 = 1) {
        precondition(d != 0, "Rational: zero denominator")
        var n = n, d = d
        if d < 0 {
            precondition(d != Int64.min, "Rational: denominator Int64.min cannot be negated")
            n = -n; d = -d                              // keep the sign on the numerator
        }
        let g = Rational.gcd(n.magnitude, d.magnitude)
        if g > 1 {
            n /= Int64(g); d /= Int64(g)
        }
        self.num = n
        self.den = d
    }

    /// Binary GCD on magnitudes, so `Int64.min` cannot trap on negation.
    static func gcd(_ a: UInt64, _ b: UInt64) -> UInt64 {
        var a = a, b = b
        while b != 0 { (a, b) = (b, a % b) }
        return a == 0 ? 1 : a
    }

    public var doubleValue: Double { Double(num) / Double(den) }
    public var isInteger: Bool { den == 1 }
    public var isZero: Bool { num == 0 }
    public var magnitude: Rational { num < 0 ? -self : self }
    public var description: String { den == 1 ? "\(num)" : "\(num)/\(den)" }

    // MARK: - Overflow-checked primitives

    /// Multiply, trapping with a domain message rather than wrapping. A wrapped product here would
    /// silently produce a wrong dimension, so this must never be a `&*`.
    static func mul(_ a: Int64, _ b: Int64, _ what: @autoclosure () -> String) -> Int64 {
        let (r, o) = a.multipliedReportingOverflow(by: b)
        precondition(!o, "Rational: overflow in \(what()) — value outside the representable range")
        return r
    }

    static func add(_ a: Int64, _ b: Int64, _ what: @autoclosure () -> String) -> Int64 {
        let (r, o) = a.addingReportingOverflow(b)
        precondition(!o, "Rational: overflow in \(what()) — value outside the representable range")
        return r
    }

    // MARK: - Exact arithmetic

    /// Addition via the LCM of the denominators, not the raw product — `1/16 + 1/32` stays over 32
    /// instead of blowing up to 512, which is what keeps long tapes inside `Int64`.
    public static func + (a: Rational, b: Rational) -> Rational { combine(a, b, subtract: false) }
    public static func - (a: Rational, b: Rational) -> Rational { combine(a, b, subtract: true) }

    private static func combine(_ a: Rational, _ b: Rational, subtract: Bool) -> Rational {
        let g = Int64(gcd(a.den.magnitude, b.den.magnitude))
        let bScale = b.den / g                                  // a.den * bScale == lcm
        let aScale = a.den / g
        let lcm = mul(a.den, bScale, "denominator lcm")
        let an = mul(a.num, bScale, "addition")
        let bn = mul(b.num, aScale, "addition")
        return Rational(subtract ? add(an, -bn, "subtraction") : add(an, bn, "addition"), lcm)
    }

    /// Multiplication with cross-reduction before the product, so `(3/4) × (4/3)` never forms 12.
    public static func * (a: Rational, b: Rational) -> Rational {
        let g1 = Int64(gcd(a.num.magnitude, b.den.magnitude))
        let g2 = Int64(gcd(b.num.magnitude, a.den.magnitude))
        let n = mul(a.num / g1, b.num / g2, "multiplication")
        let d = mul(a.den / g2, b.den / g1, "multiplication")
        return Rational(n, d)
    }

    public static func / (a: Rational, b: Rational) -> Rational {
        precondition(b.num != 0, "Rational: division by zero")
        return a * Rational(b.den, b.num)
    }

    public static prefix func - (a: Rational) -> Rational {
        precondition(a.num != Int64.min, "Rational: cannot negate Int64.min")
        return Rational(-a.num, a.den)
    }

    /// Ordering without forming the cross product where it would overflow: compare by the
    /// floor-quotient first, and only fall back to the cross product when the integer parts tie.
    public static func < (a: Rational, b: Rational) -> Bool {
        let (l, lo) = a.num.multipliedReportingOverflow(by: b.den)
        let (r, ro) = b.num.multipliedReportingOverflow(by: a.den)
        if !lo && !ro { return l < r }
        return a.doubleValue < b.doubleValue     // only reachable at magnitudes far outside the domain
    }

    // MARK: - Rounding

    /// Nearest multiple of `1/denominator`, resolving exact ties by `rule`.
    ///
    /// `denominator` is the fraction precision (2, 4, 8, 16, 32, 64 in the trade; any positive
    /// integer is accepted so the same routine can round to whole millimetres, which is how the
    /// PS 20-20 Table 3 oracle is asserted).
    public func rounded(toDenominator d: Int64, rule: RoundingRule = .halfToEven) -> Rational {
        precondition(d > 0, "denominator must be positive")
        let p = Rational.mul(num, d, "rounding")     // nearest integer k to p/den, result k/d
        let q = den
        let quo = p / q                              // truncates toward zero
        let rem = p % q                              // same sign as p
        if rem == 0 { return Rational(quo, d) }

        let step: Int64 = p < 0 ? -1 : 1
        // Compare 2|rem| against q WITHOUT doubling: |rem| < q always, so `q - r` cannot overflow,
        // whereas `2 * r` can when q is near Int64.max.
        let r = Int64(rem.magnitude)          // safe: |rem| < q ≤ Int64.max
        let complement = q - r

        var k = quo
        if r > complement {
            k = Rational.add(k, step, "rounding")
        } else if r == complement {
            switch rule {
            case .halfAwayFromZero:
                k = Rational.add(k, step, "rounding")
            case .halfToEven:
                // Two candidates: quo and quo+step. Take whichever is even.
                if quo % 2 != 0 { k = Rational.add(k, step, "rounding") }
            }
        }
        return Rational(k, d)
    }
}

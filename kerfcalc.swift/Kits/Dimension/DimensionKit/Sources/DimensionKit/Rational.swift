import Foundation

/// Exact rational number (Int64 numerator/denominator, always reduced, denominator > 0).
///
/// Feet-inch-fraction carpentry math must be **exact** — `1/3 + 1/3 + 1/3` has to be `1`, and a
/// value rounded to the nearest 1/16 must land on the true nearest sixteenth, never on a binary
/// floating-point approximation. All arithmetic here is integer arithmetic on num/den, so it is
/// exact for every value the domain produces (dimensions of a building, denominators ≤ 64).
public struct Rational: Equatable, Comparable, CustomStringConvertible {
    public let num: Int64
    public let den: Int64   // invariant: den > 0, gcd(|num|, den) == 1

    public init(_ n: Int64, _ d: Int64 = 1) {
        precondition(d != 0, "Rational: zero denominator")
        var n = n, d = d
        if d < 0 { n = -n; d = -d }                 // keep the sign on the numerator
        let g = Rational.gcd(n < 0 ? -n : n, d)
        if g > 1 { n /= g; d /= g }
        self.num = n
        self.den = d
    }

    static func gcd(_ a: Int64, _ b: Int64) -> Int64 {
        var a = a, b = b
        while b != 0 { (a, b) = (b, a % b) }
        return a == 0 ? 1 : a
    }

    public var doubleValue: Double { Double(num) / Double(den) }
    public var isInteger: Bool { den == 1 }
    public var description: String { den == 1 ? "\(num)" : "\(num)/\(den)" }

    // Exact arithmetic. Reductions in `init` keep the operands small for the construction domain.
    public static func + (a: Rational, b: Rational) -> Rational { Rational(a.num * b.den + b.num * a.den, a.den * b.den) }
    public static func - (a: Rational, b: Rational) -> Rational { Rational(a.num * b.den - b.num * a.den, a.den * b.den) }
    public static func * (a: Rational, b: Rational) -> Rational { Rational(a.num * b.num, a.den * b.den) }
    public static func / (a: Rational, b: Rational) -> Rational {
        precondition(b.num != 0, "Rational: division by zero")
        return Rational(a.num * b.den, a.den * b.num)
    }
    public static prefix func - (a: Rational) -> Rational { Rational(-a.num, a.den) }

    public static func < (a: Rational, b: Rational) -> Bool { a.num * b.den < b.num * a.den }

    /// Nearest multiple of `1/denominator`, ties rounded **away from zero** (the symmetric
    /// carpentry convention: a value exactly halfway between two sixteenths rounds up in
    /// magnitude). `denominator` is the fraction precision (2, 4, 8, 16, 32, 64).
    public func rounded(toDenominator d: Int64) -> Rational {
        precondition(d > 0, "denominator must be positive")
        let p = num * d                 // we want the nearest integer k to p/den, then k/d
        let q = den
        let quo = p / q                 // truncates toward zero
        let rem = p % q                 // same sign as p
        let twiceRem = (rem < 0 ? -rem : rem) * 2
        var k = quo
        if twiceRem >= q { k += (p < 0 ? -1 : 1) }   // round half away from zero
        return Rational(k, d)
    }
}

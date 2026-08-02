import Foundation

/// The dimensionality of a running value: a pure number, a length, an area, or a volume.
///
/// This is the type that closes the incumbent's longest-standing defect. Reviewers have asked for
/// dimensioned multiplication since 2014 and it has never worked — *"I hit the 'X' multiplication
/// symbol then go to put in the 2nd measurement ... the FEET and INCHES buttons are GRAYED OUT"*
/// (2★ 2014-08-04) — right through to *"can't even multiply for square footage"* (1★ 2025-11-22).
///
/// Pure, stateless. The algebra is exponent arithmetic on the length unit:
/// `linear × linear = square`, `square × linear = cubic`, `cubic ÷ square = linear`,
/// `anything × scalar = anything`.
///
/// **Undefined results are `nil`, never clamped.** `kerfcalc`'s equivalent clamps with
/// `min(a + b, 3)` / `max(a - b, 0)`, so a fourth power silently reports itself as a volume and a
/// negative power reports itself as a pure number. Both are wrong answers presented as right ones,
/// which is the exact failure this app exists to prevent. Here the caller must handle `nil`.
public enum Dim: Int, CaseIterable, Sendable {
    case scalar = 0, linear = 1, square = 2, cubic = 3

    /// Exponent of length: 0 for a pure number, 1 for a length, 2 for an area, 3 for a volume.
    public var exponent: Int { rawValue }

    public var symbol: String {
        switch self {
        case .scalar: return ""
        case .linear: return "in"
        case .square: return "sq ft"
        case .cubic:  return "cu ft"
        }
    }

    /// Product of two dimensions, or `nil` if the result is beyond a volume.
    public static func * (a: Dim, b: Dim) -> Dim? { Dim(rawValue: a.exponent + b.exponent) }

    /// Quotient of two dimensions, or `nil` if the result would be a negative power of length.
    public static func / (a: Dim, b: Dim) -> Dim? { Dim(rawValue: a.exponent - b.exponent) }

    /// Divisor to take a magnitude held in inches^n to the unit this dimension displays in:
    /// inches for a length, ft² for an area (144 in²), ft³ for a volume (1728 in³).
    public var displayDivisor: Double {
        switch self {
        case .scalar, .linear: return 1
        case .square:          return 144
        case .cubic:           return 1728
        }
    }
}

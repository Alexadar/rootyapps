import Foundation

/// Right-triangle math — squaring up a layout, and the 3-4-5 check.
/// Pure, stateless. Units are whatever the caller supplies, kept consistent.
///
/// Oracle class: IDENTITY — the Pythagorean theorem, cross-checked numerically against the
/// 3-4-5 and 5-12-13 integer triples.
public enum Diagonal {

    /// Hypotenuse from two legs.
    public static func hypotenuse(_ a: Double, _ b: Double) -> Double { (a * a + b * b).squareRoot() }

    /// Missing leg given the diagonal and one leg. Returns 0 rather than NaN for an impossible set.
    public static func leg(diagonal d: Double, otherLeg a: Double) -> Double {
        let s = d * d - a * a
        return s > 0 ? s.squareRoot() : 0
    }

    /// Is this rectangle square? Compares the measured diagonal against the true one.
    /// `tolerance` is in the same units — a framer works to 1/8″ over a room.
    public static func isSquare(length l: Double, width w: Double,
                                measuredDiagonal d: Double, tolerance: Double) -> Bool {
        abs(hypotenuse(l, w) - d) <= tolerance
    }

    /// How far out of square a rectangle is: measured diagonal minus true diagonal.
    /// Positive means the measured diagonal is long.
    public static func outOfSquare(length l: Double, width w: Double, measuredDiagonal d: Double) -> Double {
        d - hypotenuse(l, w)
    }

    /// The 3-4-5 check scaled to a chosen leg — the oldest layout trick there is.
    /// A leg of `3 × k` and `4 × k` must give a diagonal of `5 × k`.
    public static func threeFourFive(scale k: Double) -> (a: Double, b: Double, c: Double) {
        (3 * k, 4 * k, 5 * k)
    }
}

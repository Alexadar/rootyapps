import Foundation
import DimensionKit

/// Divide a span into equal parts and emit **the list of marks to make on the tape**.
///
/// Pure, stateless.
///
/// ## Oracle class: IDENTITY / INVARIANT — deliberately not PUBLISHED
///
/// There is no published authority for this arithmetic and none is claimed. It is exact rational
/// division, and it is proved by invariants instead: the marks are strictly increasing, the first
/// is 0, the last is the span, there are `parts + 1` of them, and **the bays sum to the span
/// exactly**. That last property is why this Kit depends on `DimensionKit` rather than computing
/// in `Double` — see `docs/storypole_oracle_gate_2026-07-29.md` §4 for the decision to ship this
/// as an identity.
///
/// Every other calculator returns a spacing *number*. Returning the marks is the differentiator,
/// and it is what users actually ask for:
/// *"The only thing I wish it had was an automatic halving setting."* (5★ 2024-03-14)
/// *"where are the 4 quarters of a drawer face that measures 17 7/16\""* (5★ 2014-07-28)
/// *"Works perfectly if you need to break up an elevation into equals"* (5★ 2016-10-28)
public enum EqualSpacing {

    /// The width of one bay when `span` is divided into `parts` equal pieces. Exact.
    public static func bay(span: FeetInch, parts: Int) -> FeetInch {
        precondition(parts > 0, "parts must be positive")
        return span / Rational(Int64(parts))
    }

    /// Every mark, including both ends: `parts + 1` values from 0 to `span`.
    ///
    /// Exact — mark *i* is `i × span / parts`, never an accumulated sum, so rounding can never
    /// creep along the run.
    public static func marks(span: FeetInch, parts: Int) -> [FeetInch] {
        precondition(parts > 0, "parts must be positive")
        return (0...parts).map { i in
            FeetInch(inches: span.inches * Rational(Int64(i), Int64(parts)))
        }
    }

    /// The interior marks only — what you actually pencil on the board, with the two ends dropped.
    public static func interiorMarks(span: FeetInch, parts: Int) -> [FeetInch] {
        let all = marks(span: span, parts: parts)
        guard all.count > 2 else { return [] }
        return Array(all.dropFirst().dropLast())
    }

    /// The midpoint. The single most-requested missing feature on the incumbent.
    public static func half(_ v: FeetInch) -> FeetInch { v / Rational(2) }

    /// The three interior quarter marks of a span — the drawer-face case, verbatim from a review.
    public static func quarters(_ v: FeetInch) -> [FeetInch] { interiorMarks(span: v, parts: 4) }

    /// Centre marks for `count` evenly spaced items of `itemWidth` inside `span`, with equal gaps
    /// at both ends and between items — the baluster / picket / cabinet-pull layout.
    ///
    /// `gap = (span − count × itemWidth) / (count + 1)`. Returns `nil` if the items cannot fit,
    /// rather than emitting negative gaps that would read as a valid layout.
    public static func itemCentres(span: FeetInch, count: Int, itemWidth: FeetInch) -> [FeetInch]? {
        precondition(count > 0, "count must be positive")
        let occupied = itemWidth * Rational(Int64(count))
        let free = span - occupied
        guard !free.isNegative else { return nil }
        let gap = free / Rational(Int64(count + 1))
        let half = itemWidth / Rational(2)
        return (1...count).map { i in
            gap * Rational(Int64(i)) + itemWidth * Rational(Int64(i - 1)) + half
        }
    }

    /// The equal gap between items in the layout above, or `nil` if they do not fit.
    public static func itemGap(span: FeetInch, count: Int, itemWidth: FeetInch) -> FeetInch? {
        precondition(count > 0, "count must be positive")
        let free = span - itemWidth * Rational(Int64(count))
        guard !free.isNegative else { return nil }
        return free / Rational(Int64(count + 1))
    }
}

import Foundation
import DimensionKit

/// On-center layout across a real span, including the odd last bay.
///
/// Pure, stateless.
///
/// ## Oracle class: mixed, and the split is deliberate
///
/// - **The spacing VALUES 16″ and 24″ are PUBLISHED.** USDA Agriculture Handbook 73,
///   *Wood-Frame House Construction* (US Government work, public domain):
///   *"joists ... spaced 16 inches on center"*; *"The joist spacing should not exceed 16 inches on
///   center when finish flooring ... is used; nor exceed 24 inches on center"*;
///   *"2- by 4-inch studs spaced 16 inches on center"*.
/// - **19.2″ is NOT in AH-73** and is not claimed as published. It is the 8-foot sheet module
///   divided into five bays: 96″ ÷ 5 = 19.2″ exactly. Labelled as a derived convention.
/// - **The mark arithmetic is IDENTITY/INVARIANT**, like `EqualSpacing`.
///
/// See `docs/storypole_oracle_gate_2026-07-29.md` §4.
public enum OnCenter {

    /// The standard framing spacings. `rawValue` is the spacing in sixteenths of an inch, so every
    /// case is an exact `FeetInch` — including 19.2″, which is 307.2 sixteenths and therefore NOT
    /// representable in sixteenths at all. That is precisely why it is held as a rational.
    public enum Spacing: String, CaseIterable, Sendable {
        case sixteen      = "16\" o.c."
        case nineteenTwo  = "19.2\" o.c."
        case twentyFour   = "24\" o.c."

        /// Exact spacing in inches.
        public var inches: Rational {
            switch self {
            case .sixteen:     return Rational(16)
            case .nineteenTwo: return Rational(96, 5)     // the 8-ft sheet in five bays, exactly 19.2"
            case .twentyFour:  return Rational(24)
            }
        }

        public var dimension: FeetInch { FeetInch(inches: inches) }

        /// Whether the value itself is published, as opposed to derived.
        /// 16″ and 24″ appear verbatim in USDA Agriculture Handbook 73; 19.2″ does not.
        public var isPublished: Bool { self != .nineteenTwo }

        public var provenance: String {
            switch self {
            case .sixteen, .twentyFour:
                return "USDA Agriculture Handbook 73, Wood-Frame House Construction (public domain)"
            case .nineteenTwo:
                return "Derived: the 96\" sheet module in five bays (96 ÷ 5). Not published in AH-73."
            }
        }
    }

    /// A laid-out run: where the members go, and what is left over at the end.
    public struct Layout: Equatable, Sendable {
        /// Every member centre from 0 up to and including the last full-spacing mark.
        public let marks: [FeetInch]
        /// The leftover distance from the last mark to the end of the span. Zero when it divides evenly.
        public let lastBay: FeetInch
        /// True when the span is an exact multiple of the spacing.
        public var isEven: Bool { lastBay.inches.isZero }
        /// Number of members, i.e. `marks.count`.
        public var memberCount: Int { marks.count }
    }

    /// Lay out `span` at `spacing`, marking from zero.
    ///
    /// The last bay is reported rather than hidden. A framer needs to know the odd bay exists —
    /// that is the whole reason on-center layout is error-prone by hand.
    public static func layout(span: FeetInch, spacing: FeetInch) -> Layout {
        precondition(!spacing.inches.isZero, "spacing must be non-zero")
        precondition(!spacing.isNegative, "spacing must be positive")
        precondition(!span.isNegative, "span must not be negative")

        var marks: [FeetInch] = []
        var i: Int64 = 0
        while true {
            let at = FeetInch(inches: spacing.inches * Rational(i))
            if span < at { break }
            marks.append(at)
            i += 1
            if i > 100_000 { break }          // a span this long is not a building; do not hang
        }
        let last = marks.last ?? .zero
        return Layout(marks: marks, lastBay: span - last)
    }

    public static func layout(span: FeetInch, spacing: Spacing) -> Layout {
        layout(span: span, spacing: spacing.dimension)
    }

    /// Number of members needed for a span at a spacing, counting the one at zero.
    public static func memberCount(span: FeetInch, spacing: FeetInch) -> Int {
        layout(span: span, spacing: spacing).memberCount
    }
}

import Foundation

/// A real tape measure, and the rule that the drawn tape must behave like one.
///
/// This type exists to make **defect ④** unshippable. The incumbent draws a tape marked in raw
/// inches running past 200", which no physical tape does, and a carpenter said so plainly:
///
/// > *"Normal carpentrs do not use decimals we use fractions. The tape at the end is in inches for
/// > some crazy reason. **No tape goes into the 200s that I've ever seen.** This should be feet and
/// > inches."* — 3★ 2025-10-14, Tape Measure Calculator Pro v4.9
///
/// So the renderer never chooses its own extent. It asks `Tape.smallest(for:)`, and if that returns
/// `nil` the value is longer than any tape sold and **must not be drawn as one** — the UI shows the
/// number alone. A `nil` here is not an error to route around; it is the answer.
///
/// Pure, stateless.
public struct Tape: Equatable, Hashable, Sendable, CustomStringConvertible {
    /// Blade length in feet.
    public let lengthFeet: Int

    public init(lengthFeet: Int) {
        precondition(lengthFeet > 0, "a tape has a positive length")
        self.lengthFeet = lengthFeet
    }

    /// Blade length as an exact dimension.
    public var length: FeetInch { FeetInch(feet: Int64(lengthFeet)) }

    public var description: String { "\(lengthFeet) ft tape" }

    /// The tape lengths actually sold in the US trade, shortest first.
    ///
    /// IDENTITY/CONVENTION, not PUBLISHED — these are the common retail blade lengths, not a
    /// standardised list, and they are labelled as such. Nothing computes from them except the
    /// drawing extent, so a disagreement about whether 35 ft belongs changes no measurement.
    public static let catalogue: [Tape] = [
        Tape(lengthFeet: 12),
        Tape(lengthFeet: 16),
        Tape(lengthFeet: 25),
        Tape(lengthFeet: 30),
        Tape(lengthFeet: 35),
    ]

    /// The longest tape in the catalogue — the absolute drawing limit.
    public static var longest: Tape { catalogue.last! }

    /// True if `value` falls on this blade. Negative values never fit: a tape has no negative side.
    public func contains(_ value: FeetInch) -> Bool {
        !value.isNegative && !(length < value)
    }

    /// The shortest real tape that can show `value`, or **`nil` if no real tape can**.
    ///
    /// `nil` is the signal that the tape graphic must not be drawn. Callers must handle it; there
    /// is deliberately no "just use the longest" fallback, because that is the defect.
    public static func smallest(for value: FeetInch) -> Tape? {
        catalogue.first { $0.contains(value) }
    }

    /// Fractional position of `value` along this blade, `0...1`, or `nil` if it does not fit.
    ///
    /// This is the whole tape graphic reduced to one testable function. **Defect ②** — *"Wrong
    /// result showing in tape measure graphic"* (1★ 2025-09-26), *"It's an 1" short on every
    /// measurement. This app cost me hundreds of dollars in miscut wood."* (1★ 2020-11-13) — is a
    /// bug in exactly this arithmetic, so it is unit-tested before any pixel is drawn.
    public func position(of value: FeetInch) -> Double? {
        guard contains(value) else { return nil }
        return value.inchesValue / length.inchesValue
    }

    /// Inch marks along the blade — every whole inch, `0...lengthFeet × 12`.
    /// The renderer labels these in **feet and inches**, never a raw running inch count, which is
    /// the other half of defect ④.
    public func inchMarks() -> [FeetInch] {
        (0...(lengthFeet * 12)).map { FeetInch(inches: Rational(Int64($0))) }
    }

    // MARK: - Scrubbing: the blade as an input

    /// The inverse of `position(of:)` — the value at a fractional position along the blade,
    /// **snapped to `denominator`**. `p` is clamped to `0...1`.
    ///
    /// The snap is not a nicety, it is what makes the round trip exact. `position(of:)` divides
    /// through `Double`, so `value(atPosition: position(of: v)!)` comes back carrying ~1e-13 of
    /// float error; rounding to the display denominator absorbs it and returns `v` itself. The
    /// round-trip is asserted for every sixteenth on every blade in `TapeTests`.
    public func value(atPosition p: Double, denominator: Int64 = 16,
                      rule: RoundingRule = .halfToEven) -> FeetInch {
        precondition(denominator > 0, "denominator must be positive")
        let clamped = p.isFinite ? min(max(p, 0), 1) : 0
        return FeetInch.approx(inches: clamped * length.inchesValue, den: denominator, rule: rule)
    }

    /// How much blade one full drag across the view covers.
    ///
    /// A single fixed window forces a bad trade: fine enough to pick a sixteenth is too fine to
    /// travel twenty feet. So the scale is chosen by how far the finger has moved *away* from the
    /// blade — the variable-scrubbing idiom iOS media players and YouTube use, **inverted**.
    ///
    /// Media players put hi-speed at the control and fine scrubbing further away. A tape is the
    /// other way round: precision lives *on* the blade, where the graduations are, so a finger on
    /// the tape works in sixteenths and pulling away is how you travel. Keep your finger on the
    /// blade to place a mark; drag off it to cover twenty feet.
    ///
    /// The tier names are shown in the UI, because the finger covers the blade while dragging and
    /// there is otherwise no way to tell which scale is in force.
    public enum ScrubScale: Int, CaseIterable, Sendable, Comparable {
        case coarse, normal, fine, precise

        /// Blade covered by one full-width drag.
        public var span: FeetInch {
            switch self {
            case .coarse:  return FeetInch(feet: 8)
            case .normal:  return FeetInch(feet: 2)
            case .fine:    return FeetInch(inches: 6)
            case .precise: return FeetInch(inches: 2)
            }
        }

        public var name: String {
            switch self {
            case .coarse:  return "coarse"
            case .normal:  return "normal"
            case .fine:    return "fine"
            case .precise: return "precise"
            }
        }

        /// Pick a scale from how far the finger has drifted off the blade, in points.
        ///
        /// **On the blade is precise; away is coarse.** Thresholds are deliberately generous — a
        /// drag that wanders 20 pt while you are placing a sixteenth must not change scale.
        public static func forVerticalDrift(_ points: Double) -> ScrubScale {
            let d = abs(points)
            if d < 44  { return .precise }
            if d < 100 { return .fine }
            if d < 170 { return .normal }
            return .coarse
        }

        public static func < (a: ScrubScale, b: ScrubScale) -> Bool { a.rawValue < b.rawValue }
    }

    /// Scrub a zoomed window of the blade: drag by `fraction` of the window's width and get the
    /// new value, snapped to `denominator` and clamped to this blade.
    ///
    /// **Why a window and not the whole blade.** On a 25 ft tape drawn across a phone, one inch is
    /// barely a point and 1/16" is under a tenth of a point — a fingertip covers about three feet
    /// of blade, so dragging a cursor along the full length cannot resolve a sixteenth at all. It
    /// would reproduce the incumbent's worst review verbatim: *"The display tape on the app always
    /// shows your measurement 1/16 of an inch off and it's infuriating"* (1★ 2020-12-25).
    ///
    /// So the gesture moves a *window* — typically 12–24 inches — under a fixed cursor, which is
    /// also how a tape is really read: you look at the few inches around the mark, not the whole
    /// blade. At 12" across a phone, 1/16" is about 2 points, which a finger can actually hold.
    ///
    /// `fraction` is the drag distance over the view's width; dragging left (negative) increases
    /// the value, matching a tape being pulled out.
    public func scrubbing(from value: FeetInch, byFraction fraction: Double,
                          windowSpan: FeetInch, denominator: Int64 = 16,
                          rule: RoundingRule = .halfToEven) -> FeetInch {
        precondition(denominator > 0, "denominator must be positive")
        precondition(!windowSpan.isNegative && !windowSpan.inches.isZero, "window span must be positive")
        guard fraction.isFinite else { return value }
        let deltaInches = -fraction * windowSpan.inchesValue
        let moved = value.inchesValue + deltaInches
        let snapped = FeetInch.approx(inches: moved, den: denominator, rule: rule)
        // A tape has no negative side, and nothing past the hook end of this blade.
        if snapped.isNegative { return .zero }
        if length < snapped { return length.rounded(toDenominator: denominator, rule: rule) }
        return snapped
    }
}

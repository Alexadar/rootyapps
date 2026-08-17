import Foundation

/// One of the four named positions on the strength rail.
///
/// The design handoff (`1i`) names them and explains each one; the names are what VoiceOver
/// announces and what the label under the slider reads. A bare number tells the user nothing about
/// what is about to happen to their photo — "Balanced" does.
public enum Detent: Double, CaseIterable, Sendable, Codable, Hashable {
    case whisper = 15
    case subtle = 35
    case balanced = 55
    case strong = 80

    /// The default. Board `1i` marks it with a star and the reasoning is in the handoff: the top
    /// category complaint is "it doesn't look like my photo", so the dial starts low.
    public static let `default` = Detent.subtle

    public var name: String {
        switch self {
        case .whisper:  return "Whisper"
        case .subtle:   return "Subtle"
        case .balanced: return "Balanced"
        case .strong:   return "Strong"
        }
    }

    /// The one-line explanation shown beside the detent, verbatim from `1i`.
    public var explanation: String {
        switch self {
        case .whisper:  return "Noise, micro-contrast. Pixel-faithful."
        case .subtle:   return "Light, colour, sharpness. Faces untouched in structure."
        case .balanced: return "Reconstructs fine detail. Still recognisably the same shot."
        case .strong:   return "Full re-render."
        }
    }

    /// Only `Strong` carries an inline warning, and it is the handoff's wording.
    public var warning: String? {
        self == .strong ? "May alter fine details." : nil
    }

    public var strength: Strength { Strength(rawValue) }
}

/// A position on the 0–100 rail.
///
/// A value type rather than a bare `Double` for one reason: every place in the app that shows a
/// strength must show its **detent name**, and every place that hands one to the model must pass a
/// clamped number. Both of those are easy to forget with a `Double` and impossible to forget here.
public struct Strength: Hashable, Sendable, Codable, Comparable, CustomStringConvertible {

    public static let minimum: Double = 0
    public static let maximum: Double = 100

    /// How near the rail has to be to a detent for the slider to settle on it. Three points either
    /// side: close enough that a deliberate 35 always lands, far enough that 20 and 45 stay where
    /// the user put them.
    public static let snapTolerance: Double = 3

    public let value: Double

    /// Clamps. A strength outside the rail is not an error the user should ever see — it is a
    /// caller bug, and trapping on it would turn a rounding slip into a crash mid-edit.
    ///
    /// NaN is the only value with no sensible end of the rail to fall to, so it becomes zero — the
    /// original, which is always the safe answer here. Infinities clamp by sign like any other
    /// out-of-range number; sending +∞ to zero would be the surprising choice.
    public init(_ value: Double) {
        guard !value.isNaN else { self.value = Self.minimum; return }
        self.value = min(max(value, Self.minimum), Self.maximum)
    }

    public init(from decoder: Decoder) throws {
        self.init(try decoder.singleValueContainer().decode(Double.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }

    public static let zero = Strength(0)
    public static let whisper = Strength(Detent.whisper.rawValue)
    public static let subtle = Strength(Detent.subtle.rawValue)
    public static let balanced = Strength(Detent.balanced.rawValue)
    public static let strong = Strength(Detent.strong.rawValue)
    public static let full = Strength(100)

    /// The starting position of a fresh edit.
    public static let `default` = Strength(Detent.default.rawValue)

    public static func < (lhs: Strength, rhs: Strength) -> Bool { lhs.value < rhs.value }

    /// 0…1, for anything that wants a fill width. Not what crosses the enhancer seam — that takes
    /// the 0–100 number, because that is what the design and the model both speak.
    public var fraction: Double { value / Self.maximum }

    public var isZero: Bool { value == 0 }

    /// The detent this value *is*, exactly. `nil` between detents.
    public var detent: Detent? { Detent.allCases.first { $0.rawValue == value } }

    /// The detent a raw drag should settle on, or `nil` if the drag ended too far from all of them.
    public func snappingDetent(tolerance: Double = Strength.snapTolerance) -> Detent? {
        Detent.allCases
            .map { ($0, abs($0.rawValue - value)) }
            .filter { $0.1 <= tolerance }
            .min { $0.1 < $1.1 }?.0
    }

    /// Slider behaviour: settle onto a detent when the drag ends near one, otherwise stay put.
    public func snapped(tolerance: Double = Strength.snapTolerance) -> Strength {
        snappingDetent(tolerance: tolerance).map { Strength($0.rawValue) } ?? self
    }

    /// "Subtle · 35" on a detent, "42" between them, "Off" at zero.
    public var displayName: String {
        if isZero { return "Off" }
        if let detent { return "\(detent.name) · \(Self.formatted(value))" }
        return Self.formatted(value)
    }

    /// ⚠️ VoiceOver announces **names, not bare numbers** (`1j`). Between detents there is no name
    /// to give, so it names the two the value sits between — a naked figure would tell a VoiceOver
    /// user nothing at all about what is about to happen to their photo.
    public var accessibilityValue: String {
        if isZero { return "Off. Showing the original." }
        if let detent { return detent.name }

        let below = Detent.allCases.last { $0.rawValue < value }
        let above = Detent.allCases.first { $0.rawValue > value }
        switch (below, above) {
        case let (.some(below), .some(above)):
            return "\(Self.formatted(value)), between \(below.name) and \(above.name)"
        case let (.some(below), .none):
            return "\(Self.formatted(value)), above \(below.name)"
        case let (.none, .some(above)):
            return "\(Self.formatted(value)), below \(above.name)"
        case (.none, .none):
            return Self.formatted(value)
        }
    }

    /// Only shown at or above `Strong`. Below it there is nothing honest to warn about.
    public var warning: String? {
        value >= Detent.strong.rawValue ? Detent.strong.warning : nil
    }

    public var description: String { displayName }

    private static func formatted(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value.rounded())) : String(format: "%.1f", value)
    }
}

import Foundation

/// A boundary event in a body's synodic cycle relative to the Sun.
public struct SynodicEvent: Identifiable, Hashable {
    public enum Kind: String, CaseIterable {
        case inferiorConjunction    // λ = λ☉, retrograde, near side (inner planets)
        case superiorConjunction    // λ = λ☉, direct, far side (inner planets)
        case conjunction            // λ = λ☉ (outer planets / generic)
        case opposition             // λ = λ☉ + 180° (outer planets)
        case stationRetrograde      // direct → retrograde ("U-turn")
        case stationDirect          // retrograde → direct ("U-turn")
        case greatestElongationEast // max separation, evening star
        case greatestElongationWest // max separation, morning star

        public var label: String {
            switch self {
            case .inferiorConjunction: "Inferior conjunction"
            case .superiorConjunction: "Superior conjunction"
            case .conjunction: "Conjunction with Sun"
            case .opposition: "Opposition"
            case .stationRetrograde: "Station retrograde"
            case .stationDirect: "Station direct"
            case .greatestElongationEast: "Greatest elongation E"
            case .greatestElongationWest: "Greatest elongation W"
            }
        }

        public var short: String {
            switch self {
            case .inferiorConjunction: "Inf. ☌"
            case .superiorConjunction: "Sup. ☌"
            case .conjunction: "☌ Sun"
            case .opposition: "☍ Sun"
            case .stationRetrograde: "Station ℞"
            case .stationDirect: "Station D"
            case .greatestElongationEast: "Gr. elong. E"
            case .greatestElongationWest: "Gr. elong. W"
            }
        }

        public var glyph: String {
            switch self {
            case .inferiorConjunction, .superiorConjunction, .conjunction: "☌"
            case .opposition: "☍"
            case .stationRetrograde: "℞"
            case .stationDirect: "D"
            case .greatestElongationEast: "E"
            case .greatestElongationWest: "W"
            }
        }
    }

    public let kind: Kind
    public let date: Date
    public let longitude: Double   // body's ecliptic longitude at the event

    public init(kind: Kind, date: Date, longitude: Double) {
        self.kind = kind; self.date = date; self.longitude = longitude
    }

    public var id: String { "\(kind.rawValue)-\(Int(date.timeIntervalSince1970))" }
}

/// The segment of the cycle a moment falls in, between two events.
///
/// `title` and `detail` are pre-composed English sentences, which makes them useful for export and
/// tests but unusable for display: a runtime-composed string can never be a localization key. The
/// UI therefore reads `visibility`, `retrograde` and `start`/`end` and composes its own translated
/// version. The two strings stay for the CSV contract and are deliberately not shown as-is.
public struct SynodicPhase {
    /// Which side of the Sun an inferior planet is on — the part of `title` that isn't derivable
    /// from `retrograde` alone. Nil for superior planets, which are never morning/evening stars.
    public enum Visibility: String, Codable, Hashable { case eveningStar, morningStar }

    public let body: CelestialBody
    public let title: String       // e.g. "Morning star · retrograde"
    public let detail: String      // e.g. "Inferior conjunction → Station direct"
    public let retrograde: Bool
    public let visibility: Visibility?
    public let start: SynodicEvent?
    public let end: SynodicEvent?
    public let dayInPhase: Int?
    public let phaseLengthDays: Int?

    public init(body: CelestialBody, title: String, detail: String, retrograde: Bool,
                visibility: Visibility? = nil,
                start: SynodicEvent?, end: SynodicEvent?, dayInPhase: Int?, phaseLengthDays: Int?) {
        self.body = body; self.title = title; self.detail = detail; self.retrograde = retrograde
        self.visibility = visibility
        self.start = start; self.end = end; self.dayInPhase = dayInPhase; self.phaseLengthDays = phaseLengthDays
    }
}

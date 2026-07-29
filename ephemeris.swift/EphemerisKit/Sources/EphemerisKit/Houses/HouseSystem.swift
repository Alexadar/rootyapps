import Foundation

/// How the twelve houses are carved out of the sky.
///
/// Two families, and the difference matters mathematically:
///  - **Quadrant** systems (Placidus, Koch, Campanus, Regiomontanus) anchor cusp 1 to the
///    Ascendant *and* cusp 10 to the Midheaven, dividing each quadrant by some rule. The
///    quadrants are generally unequal, so houses vary in size.
///  - **Ecliptic** systems (Whole Sign, Equal) step 30° at a time from a starting point, so
///    every house is exactly 30° and cusp 10 is *not* the MC.
public enum HouseSystem: String, CaseIterable, Identifiable, Hashable, Codable, Sendable {
    case placidus
    case koch
    case wholeSign
    case equal
    case campanus
    case regiomontanus

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .placidus:      return "Placidus"
        case .koch:          return "Koch"
        case .wholeSign:     return "Whole Sign"
        case .equal:         return "Equal"
        case .campanus:      return "Campanus"
        case .regiomontanus: return "Regiomontanus"
        }
    }

    /// One-line description of the dividing principle, for the UI picker.
    public var detail: String {
        switch self {
        case .placidus:      return "Divides each point's time above the horizon"
        case .koch:          return "Birthplace houses, from the ascending degree"
        case .wholeSign:     return "One whole sign per house"
        case .equal:         return "30° per house from the Ascendant"
        case .campanus:      return "Divides the prime vertical"
        case .regiomontanus: return "Divides the celestial equator"
        }
    }

    /// True when cusp 1 == Ascendant **and** cusp 10 == Midheaven.
    /// False for the ecliptic systems, where the MC floats between houses.
    public var isQuadrant: Bool {
        switch self {
        case .placidus, .koch, .campanus, .regiomontanus: return true
        case .wholeSign, .equal:                          return false
        }
    }

    /// Time-based systems that are undefined for circumpolar cusps — they fail inside the
    /// polar circles and must degrade to another system there.
    public var failsAtHighLatitude: Bool {
        self == .placidus || self == .koch
    }
}

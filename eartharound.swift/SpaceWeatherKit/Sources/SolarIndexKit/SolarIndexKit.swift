import Foundation

/// Solar-activity indices: the Wolf (relative) sunspot number and the F10.7 cm
/// radio flux.
///
/// Pure and deterministic. Oracle-tested against the SILSO/Wolf definition and the
/// F10.7 solar-flux-unit convention.
public enum SolarIndex {

    /// Wolf / International relative sunspot number:  R = k·(10·g + s)
    ///   g = number of sunspot groups, s = number of individual spots,
    ///   k = observer/instrument reduction factor (1.0 by definition of the reference).
    public static func wolfNumber(groups g: Int, spots s: Int, k: Double = 1.0) -> Double {
        k * Double(10 * g + s)
    }

    /// Activity band without the wording, so the app can localize it.
    public enum Band: String, CaseIterable, Sendable {
        case spotless, low, moderate, high, veryHigh
    }

    public static func activityBand(sunspotNumber r: Double) -> Band {
        switch r {
        case ..<1: return .spotless
        case ..<25: return .low
        case ..<75: return .moderate
        case ..<150: return .high
        default: return .veryHigh
        }
    }

    /// F10.7 band. Shares `Band` but starts at `.low` — a radio flux is never "spotless".
    public static func f107Band(_ sfu: Double) -> Band {
        switch sfu {
        case ..<70: return .spotless    // rendered as "Very low" for F10.7
        case ..<100: return .low
        case ..<150: return .moderate
        case ..<200: return .high
        default: return .veryHigh
        }
    }

    /// Plain-language solar activity from the sunspot number.
    public static func activity(sunspotNumber r: Double) -> String {
        switch r {
        case ..<1: return "Spotless"
        case ..<25: return "Low"
        case ..<75: return "Moderate"
        case ..<150: return "High"
        default: return "Very high"
        }
    }

    // MARK: - F10.7 cm radio flux
    //
    // Measured in solar flux units (sfu); 1 sfu = 1e-22 W·m⁻²·Hz⁻¹.
    // The quiet-Sun floor sits near ~67 sfu; it rises with cycle activity.

    public static let sfuInWattsPerM2Hz = 1e-22

    /// Solar-cycle activity level from the F10.7 flux (sfu).
    public static func f107Level(_ sfu: Double) -> String {
        switch sfu {
        case ..<70: return "Very low"
        case ..<100: return "Low"
        case ..<150: return "Moderate"
        case ..<200: return "High"
        default: return "Very high"
        }
    }

    /// Convert an F10.7 value in sfu to W·m⁻²·Hz⁻¹.
    public static func f107InSI(_ sfu: Double) -> Double { sfu * sfuInWattsPerM2Hz }
}

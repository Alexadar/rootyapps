import Foundation

/// Why a moist-air state could not be produced.
///
/// Every failure is an error, never a plausible-looking number. A calculator that returns 55.1 °F
/// for an impossible input is worse than one that refuses: the user has no way to tell.
public enum PsychroError: Error, Equatable, Sendable, CustomStringConvertible {

    /// Dry bulb, wet bulb or dew point outside the correlation's published validity range.
    case temperatureOutOfRange(Double)
    /// Barometric pressure outside a physically sensible range.
    case pressureOutOfRange(Double)
    /// Relative humidity outside 0…1.
    case relativeHumidityOutOfRange(Double)
    /// Humidity ratio negative, or not finite.
    case humidityRatioOutOfRange(Double)
    /// Specific volume zero, negative or not finite.
    case specificVolumeOutOfRange(Double)

    /// The moisture content exceeds saturation at this dry bulb and pressure — fog, not moist air.
    /// Carries the offending ratio and the saturation ratio, both kg/kg dry air.
    case supersaturated(humidityRatio: Double, saturation: Double)

    /// Both knowns are the same property, so they cannot determine a state.
    case duplicateInput
    /// Both knowns fix moisture without fixing temperature (e.g. dew point + humidity ratio):
    /// they describe a vertical line on the chart, not a point.
    case underdetermined
    /// The two knowns trace lines that lie almost on top of each other, so their intersection is
    /// not a usable answer — a rounding-level change in either input moves the state by degrees.
    case degeneratePair(PsychroInput.Kind, PsychroInput.Kind)
    /// The two knowns describe no physically reachable state.
    case unsolvable

    public var description: String {
        switch self {
        case .temperatureOutOfRange(let t):
            return "temperature \(t) °C is outside the valid range \(Psychrometrics.temperatureRange)"
        case .pressureOutOfRange(let p):
            return "pressure \(p) Pa is outside the valid range \(Psychrometrics.pressureRange)"
        case .relativeHumidityOutOfRange(let r):
            return "relative humidity \(r) is outside 0…1"
        case .humidityRatioOutOfRange(let w):
            return "humidity ratio \(w) kg/kg is not a valid moisture content"
        case .specificVolumeOutOfRange(let v):
            return "specific volume \(v) m³/kg is not a valid volume"
        case .supersaturated(let w, let ws):
            return "humidity ratio \(w) kg/kg exceeds saturation \(ws) kg/kg at this dry bulb"
        case .duplicateInput:
            return "the two knowns are the same property"
        case .underdetermined:
            return "the two knowns fix moisture but not temperature"
        case .degeneratePair(let a, let b):
            return "\(a.rawValue) and \(b.rawValue) describe almost the same line on the chart, "
                 + "so together they cannot fix a state"
        case .unsolvable:
            return "the two knowns describe no reachable state"
        }
    }
}

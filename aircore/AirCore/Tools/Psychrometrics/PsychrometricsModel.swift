import Foundation
import Observation
import SwiftUI
import PsychroKit
import UnitsKit

extension PsychroInput.Kind {

    var title: LocalizedStringKey {
        switch self {
        case .dryBulb:          return "Dry bulb"
        case .wetBulb:          return "Wet bulb"
        case .dewPoint:         return "Dew point"
        case .relativeHumidity: return "Relative humidity"
        case .humidityRatio:    return "Humidity ratio"
        case .enthalpy:         return "Enthalpy"
        case .specificVolume:   return "Specific volume"
        }
    }

    var plainTitle: String {
        switch self {
        case .dryBulb:          return "Dry bulb"
        case .wetBulb:          return "Wet bulb"
        case .dewPoint:         return "Dew point"
        case .relativeHumidity: return "Relative humidity"
        case .humidityRatio:    return "Humidity ratio"
        case .enthalpy:         return "Enthalpy"
        case .specificVolume:   return "Specific volume"
        }
    }

    var quantity: Quantity {
        switch self {
        case .dryBulb, .wetBulb, .dewPoint: return .temperature
        case .relativeHumidity:             return .relativeHumidity
        case .humidityRatio:                return .humidityRatio
        case .enthalpy:                     return .enthalpy
        case .specificVolume:               return .specificVolume
        }
    }

    /// Read this property off a solved state, so changing which knowns are selected carries the
    /// current air over instead of resetting the screen.
    func value(of state: MoistAir) -> Double? {
        switch self {
        case .dryBulb:          return state.dryBulb
        case .wetBulb:          return state.wetBulb
        case .dewPoint:         return state.dewPoint
        case .relativeHumidity: return state.relativeHumidity
        case .humidityRatio:    return state.humidityRatio
        case .enthalpy:         return state.enthalpy
        case .specificVolume:   return state.specificVolume
        }
    }

    func input(_ value: Double) -> PsychroInput {
        switch self {
        case .dryBulb:          return .dryBulb(value)
        case .wetBulb:          return .wetBulb(value)
        case .dewPoint:         return .dewPoint(value)
        case .relativeHumidity: return .relativeHumidity(value)
        case .humidityRatio:    return .humidityRatio(value)
        case .enthalpy:         return .enthalpy(value)
        case .specificVolume:   return .specificVolume(value)
        }
    }
}

/// The anchor tool: any two knowns, the whole state.
///
/// ## Why the state is a `Result`
///
/// Half of what this screen must do is refuse. Wet bulb above dry bulb, relative humidity of 150 %,
/// dew point and humidity ratio chosen together, wet bulb paired with enthalpy — each of those is a
/// question with no answer, and the screen has to say so rather than print a plausible number. So
/// the model holds either a state or the reason there isn't one, and the view renders both.
@Observable
final class PsychrometricsModel {

    private static let key = "AirCore.tool.psychrometrics"

    var firstKnown: PsychroInput.Kind {
        didSet { resolveClash(changed: \.firstKnown, previous: oldValue) }
    }
    var secondKnown: PsychroInput.Kind {
        didSet { resolveClash(changed: \.secondKnown, previous: oldValue) }
    }
    /// SI, always.
    var firstValue: Double
    var secondValue: Double

    init(firstKnown: PsychroInput.Kind = .dryBulb,
         secondKnown: PsychroInput.Kind = .relativeHumidity,
         firstValue: Double = 23.888888888888889,   // 75 °F
         secondValue: Double = 0.5) {
        self.firstKnown = firstKnown
        self.secondKnown = secondKnown
        self.firstValue = firstValue
        self.secondValue = secondValue
    }

    /// The solved state, or why there isn't one.
    func solved(pressure: Double) -> Result<MoistAir, PsychroError> {
        do {
            return .success(try MoistAir.solve(firstKnown.input(firstValue),
                                               secondKnown.input(secondValue),
                                               pressure: pressure))
        } catch let error as PsychroError {
            return .failure(error)
        } catch {
            return .failure(.unsolvable)
        }
    }

    /// Which pairs the solver will refuse, so the picker can grey them out instead of letting the
    /// user choose an error.
    func isUnavailable(_ kind: PsychroInput.Kind, opposite: PsychroInput.Kind) -> Bool {
        if kind == opposite { return true }
        let bothMoistureOnly: Set<PsychroInput.Kind> = [.dewPoint, .humidityRatio]
        if bothMoistureOnly.contains(kind) && bothMoistureOnly.contains(opposite) { return true }
        return PsychroInput.degeneratePairs.contains([kind, opposite])
    }

    /// When a picker lands on a pair the solver refuses, move the *other* known somewhere legal
    /// rather than silently showing an error the user did not ask for.
    private func resolveClash(changed: KeyPath<PsychrometricsModel, PsychroInput.Kind>,
                              previous: PsychroInput.Kind) {
        guard isUnavailable(firstKnown, opposite: secondKnown) else { return }
        if changed == \PsychrometricsModel.firstKnown {
            secondKnown = fallback(avoiding: firstKnown, notReturning: previous)
        } else {
            firstKnown = fallback(avoiding: secondKnown, notReturning: previous)
        }
    }

    private func fallback(avoiding kind: PsychroInput.Kind,
                          notReturning previous: PsychroInput.Kind) -> PsychroInput.Kind {
        let preference: [PsychroInput.Kind] = [.dryBulb, .relativeHumidity, .wetBulb, .dewPoint,
                                               .humidityRatio, .enthalpy, .specificVolume]
        return preference.first { !isUnavailable($0, opposite: kind) } ?? previous
    }

    /// Change which property a slot holds, carrying the current air across so the screen does not
    /// jump to an unrelated state.
    func changeFirst(to kind: PsychroInput.Kind, pressure: Double) {
        if case .success(let state) = solved(pressure: pressure),
           let carried = kind.value(of: state) {
            firstValue = carried
        }
        firstKnown = kind
    }

    func changeSecond(to kind: PsychroInput.Kind, pressure: Double) {
        if case .success(let state) = solved(pressure: pressure),
           let carried = kind.value(of: state) {
            secondValue = carried
        }
        secondKnown = kind
    }

    /// Move the state point on the chart. Dragging sets dry bulb and humidity ratio directly,
    /// whatever the two selected knowns happen to be — otherwise the point would fight the
    /// pickers, and the brief requires both directions to work equally.
    func setFromChart(dryBulb: Double, humidityRatio: Double) {
        firstKnown = .dryBulb
        firstValue = dryBulb
        secondKnown = .humidityRatio
        secondValue = humidityRatio
    }

    // MARK: - Persistence

    private struct Snapshot: Codable {
        var firstKnown: String
        var secondKnown: String
        var firstValue: Double
        var secondValue: Double
    }

    func save() {
        Persistence.save(Snapshot(firstKnown: firstKnown.rawValue,
                                  secondKnown: secondKnown.rawValue,
                                  firstValue: firstValue,
                                  secondValue: secondValue),
                         key: Self.key)
    }

    static func loaded() -> PsychrometricsModel {
        guard let snapshot = Persistence.load(Snapshot.self, key: key),
              let first = PsychroInput.Kind(rawValue: snapshot.firstKnown),
              let second = PsychroInput.Kind(rawValue: snapshot.secondKnown)
        else { return PsychrometricsModel() }
        return PsychrometricsModel(firstKnown: first, secondKnown: second,
                                   firstValue: snapshot.firstValue,
                                   secondValue: snapshot.secondValue)
    }
}

extension PsychroError: PsychroErrorReadable {
    /// What the banner says. Plain, specific, and never "invalid input".
    var readableTitle: String {
        switch self {
        case .supersaturated:              return "That air would be fog"
        case .relativeHumidityOutOfRange:  return "Relative humidity is a percentage"
        case .temperatureOutOfRange:       return "Temperature out of range"
        case .pressureOutOfRange:          return "Pressure out of range"
        case .humidityRatioOutOfRange:     return "Moisture content out of range"
        case .specificVolumeOutOfRange:    return "Specific volume out of range"
        case .duplicateInput:              return "Pick two different properties"
        case .underdetermined:             return "Those two fix moisture but not temperature"
        case .degeneratePair:              return "Those two cannot fix a state"
        case .unsolvable:                  return "No air is like that"
        }
    }

    var readableDetail: String {
        switch self {
        case .supersaturated:
            return "The moisture is above saturation for this dry bulb — check which value is which."
        case .relativeHumidityOutOfRange:
            return "It has to sit between 0 and 100 %."
        case .temperatureOutOfRange:
            return "The correlations are published for −100 °C to 200 °C."
        case .underdetermined:
            return "Dew point and humidity ratio say the same thing. Add a temperature."
        case .degeneratePair:
            return "Wet bulb and enthalpy trace almost the same line, so their crossing is not a "
                 + "usable answer. Pick one of them and a temperature."
        default:
            return description
        }
    }
}

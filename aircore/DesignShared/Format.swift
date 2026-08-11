import Foundation
import UnitsKit

/// Formatting for numbers that are the point of the screen.
public enum Fmt {

    /// A value in display units, fixed to its quantity's decimals.
    public static func number(_ value: Double, decimals: Int) -> String {
        guard value.isFinite else { return "—" }
        return value.formatted(.number.precision(.fractionLength(decimals)).grouping(.automatic))
    }

    /// An SI value, converted and formatted for a quantity and unit system.
    public static func value(si: Double, _ quantity: Quantity, _ system: UnitSystem) -> String {
        number(quantity.display(si: si, in: system), decimals: quantity.decimals(system))
    }

    /// The same value with **no grouping separator**, for export.
    ///
    /// On screen "1,609 ft" is easier to read than "1609 ft". In a CSV it is a field containing a
    /// comma, which a spreadsheet will either split or refuse to treat as a number — so the file
    /// gets the ungrouped form and the screen keeps the readable one.
    public static func exportValue(si: Double, _ quantity: Quantity,
                                   _ system: UnitSystem) -> String {
        let value = quantity.display(si: si, in: system)
        guard value.isFinite else { return "" }
        return value.formatted(
            .number.precision(.fractionLength(quantity.decimals(system))).grouping(.never))
    }

    /// An SI value with its unit, ungrouped — the form that goes in a file.
    public static func exportValueWithUnit(si: Double, _ quantity: Quantity,
                                           _ system: UnitSystem) -> String {
        let symbol = quantity.symbol(system)
        let text = exportValue(si: si, quantity, system)
        return symbol.isEmpty ? text : "\(text) \(symbol)"
    }

    /// An SI value with its unit appended — for copying, exporting and VoiceOver, never for the
    /// hero readouts, which draw the unit in its own smaller style.
    public static func valueWithUnit(si: Double, _ quantity: Quantity,
                                     _ system: UnitSystem) -> String {
        let symbol = quantity.symbol(system)
        let text = value(si: si, quantity, system)
        return symbol.isEmpty ? text : "\(text) \(symbol)"
    }

    /// What VoiceOver says. Symbols are spelled out — "degrees Fahrenheit", not "°F" — because a
    /// screen reader pronounces a degree sign as "degree" and a slash as "slash", which turns
    /// "13.7 ft³/lb" into noise.
    public static func spoken(si: Double, _ quantity: Quantity, _ system: UnitSystem) -> String {
        let text = value(si: si, quantity, system)
        let unit = spokenUnit(quantity, system)
        return unit.isEmpty ? text : "\(text) \(unit)"
    }

    static func spokenUnit(_ quantity: Quantity, _ system: UnitSystem) -> String {
        switch (quantity, system) {
        case (.temperature, .ip), (.temperatureDifference, .ip): return "degrees Fahrenheit"
        case (.temperature, .si):                                return "degrees Celsius"
        case (.temperatureDifference, .si):                      return "kelvin"
        case (.relativeHumidity, _):                             return "percent"
        case (.humidityRatio, .ip):                              return "grains per pound"
        case (.humidityRatio, .si):                              return "grams per kilogram"
        case (.enthalpy, .ip), (.enthalpyDifference, .ip):       return "BTU per pound"
        case (.enthalpy, .si), (.enthalpyDifference, .si):       return "kilojoules per kilogram"
        case (.specificVolume, .ip):                             return "cubic feet per pound"
        case (.specificVolume, .si):                             return "cubic metres per kilogram"
        case (.density, .ip):                                    return "pounds per cubic foot"
        case (.density, .si):                                    return "kilograms per cubic metre"
        case (.elevation, .ip):                                  return "feet"
        case (.elevation, .si):                                  return "metres"
        case (.barometricPressure, .ip):                         return "inches of mercury"
        case (.barometricPressure, .si):                         return "kilopascals"
        case (.airFlow, .ip):                                    return "cubic feet per minute"
        case (.airFlow, .si), (.waterFlow, .si):                 return "litres per second"
        case (.waterFlow, .ip):                                  return "gallons per minute"
        case (.airVelocity, .ip):                                return "feet per minute"
        case (.airVelocity, .si), (.waterVelocity, .si):         return "metres per second"
        case (.waterVelocity, .ip):                              return "feet per second"
        case (.ductSize, .ip):                                   return "inches"
        case (.ductSize, .si):                                   return "millimetres"
        case (.ductFrictionRate, .ip):    return "inches water gauge per hundred feet"
        case (.ductFrictionRate, .si):    return "pascals per metre"
        case (.waterHeadGradient, .ip):   return "feet of head per hundred feet"
        case (.waterHeadGradient, .si):   return "kilopascals per metre"
        case (.heatLoad, .ip):                                   return "BTU per hour"
        case (.heatLoad, .si):                                   return "watts"
        case (.fanPressure, .ip):                                return "inches water gauge"
        case (.fanPressure, .si):                                return "pascals"
        case (.fanSpeed, _):                                     return "revolutions per minute"
        case (.fanPower, .ip):                                   return "horsepower"
        case (.fanPower, .si):                                   return "kilowatts"
        case (.dimensionless, _):                                return ""
        }
    }

    /// Parse what the user typed, in display units, into SI. Returns nil for anything that is not
    /// a number — an empty field is not zero, and must not be treated as zero.
    public static func parse(_ text: String, _ quantity: Quantity,
                             _ system: UnitSystem) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        guard let value = Double(trimmed) ?? localisedDouble(trimmed), value.isFinite else {
            return nil
        }
        return quantity.si(display: value, in: system)
    }

    /// A comma-decimal locale types "23,5". `Double("23,5")` is nil, and rejecting it would make
    /// the app unusable across most of Europe.
    static func localisedDouble(_ text: String) -> Double? {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = .current
        return formatter.number(from: text)?.doubleValue
    }
}

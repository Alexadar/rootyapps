import Foundation

/// Bridges a tool field's `Double` (a length in some `LengthUnit`) to feet-inch text and back, so
/// the same machinery (`FeetInch` + `Units`) drives both the keypad and every dimension field.
///
/// Pure, stateless.
public enum LengthEntry {
    /// Format a value (given in `unit`) as feet-inch-fraction text at a fraction precision.
    public static func text(_ value: Double, unit: LengthUnit,
                            denominator: Int64 = 16, rule: RoundingRule = .halfToEven) -> String {
        let inches = Units.convert(value, from: unit, to: .inch)
        return FeetInch.approx(inches: inches, den: denominator, rule: rule)
            .formatted(toDenominator: denominator, rule: rule)
    }

    /// Parse feet-inch text into a value in `unit`; `nil` if it cannot be parsed.
    public static func value(fromText text: String, unit: LengthUnit) -> Double? {
        guard let fi = FeetInch.parse(text) else { return nil }
        return Units.convert(fi.inchesValue, from: .inch, to: unit)
    }

    /// Convert a `FeetInch` (the keypad's output) to a value in `unit`.
    public static func value(_ fi: FeetInch, unit: LengthUnit) -> Double {
        Units.convert(fi.inchesValue, from: .inch, to: unit)
    }

    /// A `FeetInch` representing `value` (given in `unit`) — to preload the keypad.
    public static func feetInch(_ value: Double, unit: LengthUnit,
                                denominator: Int64 = 16, rule: RoundingRule = .halfToEven) -> FeetInch {
        FeetInch.approx(inches: Units.convert(value, from: unit, to: .inch), den: denominator, rule: rule)
    }
}

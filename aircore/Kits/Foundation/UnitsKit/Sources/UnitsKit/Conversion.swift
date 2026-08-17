import Foundation

/// A linear conversion between one unit and its SI counterpart: `si = value × factor + offset`.
///
/// ## Why a type, and not a pile of functions
///
/// Two of these conversions carry a datum offset — temperature, and **enthalpy** — and the
/// enthalpy one is easy to miss, because the scale factor alone looks like the whole answer. It is
/// not: SI puts the enthalpy zero at 0 °C and IP puts it at 0 °F, so a Btu/lb figure differs from
/// its kJ/kg counterpart by 7.69 Btu/lb before any scaling. That is 27 % at room temperature.
///
/// Holding factor and offset together in one value makes the offset impossible to leave behind,
/// and makes `fromSI(toSI(x)) == x` a property of the type rather than a discipline.
public struct Conversion: Equatable, Sendable {

    /// SI units per unit of this scale.
    public let factor: Double
    /// The SI value this scale calls zero.
    public let offset: Double

    public init(factor: Double, offset: Double = 0) {
        self.factor = factor
        self.offset = offset
    }

    /// Convert a value in this unit to SI.
    public func toSI(_ value: Double) -> Double { value * factor + offset }

    /// Convert an SI value to this unit.
    public func fromSI(_ value: Double) -> Double { (value - offset) / factor }

    /// The same scale with its datum dropped — the conversion for a *difference* rather than a
    /// reading. A 10 °F temperature rise is 5.6 °C, not −12.2 °C, and a duct calculator that gets
    /// this wrong is wrong by the whole datum.
    public var asDifference: Conversion { Conversion(factor: factor) }
}

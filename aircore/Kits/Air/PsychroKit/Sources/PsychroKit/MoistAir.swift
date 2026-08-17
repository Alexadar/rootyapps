import Foundation

/// A fully solved moist-air state, in SI.
///
/// Canonical form is (dry bulb, humidity ratio, barometric pressure); everything else is derived
/// from those three at construction, so a `MoistAir` value cannot hold an internally inconsistent
/// set of numbers. Construction validates, which means every property on a `MoistAir` is one the
/// Kit has already proved reachable.
public struct MoistAir: Equatable, Sendable, Codable {

    /// Barometric pressure, Pa.
    public let pressure: Double
    /// Dry-bulb temperature, °C.
    public let dryBulb: Double
    /// Humidity ratio, kg water per kg dry air.
    public let humidityRatio: Double
    /// Thermodynamic wet-bulb temperature, °C.
    public let wetBulb: Double
    /// Dew point, °C — the frost point below 0 °C. `nil` for perfectly dry air, which has none.
    public let dewPoint: Double?
    /// Relative humidity, 0…1.
    public let relativeHumidity: Double
    /// Specific enthalpy, kJ per kg dry air.
    public let enthalpy: Double
    /// Specific volume, m³ per kg dry air.
    public let specificVolume: Double
    /// Degree of saturation W / Ws, 0…1.
    public let degreeOfSaturation: Double
    /// Humidity ratio at saturation for this dry bulb and pressure, kg/kg.
    public let saturationHumidityRatio: Double

    /// Density of the moist air itself, kg per m³ — mass of dry air *and* its water vapour.
    /// This is the density the air-side heat and duct-friction Kits want.
    public var density: Double { (1 + humidityRatio) / specificVolume }

    /// Build a state from its three canonical values, validating as it goes.
    ///
    /// - Throws: ``PsychroError`` if any input is out of range, or if the moisture content
    ///   exceeds saturation — fog is not a moist-air state this Kit will represent.
    public init(dryBulb t: Double, humidityRatio w: Double, pressure p: Double) throws {
        try Psychrometrics.validate(pressure: p)
        guard t.isFinite, Psychrometrics.temperatureRange.contains(t) else {
            throw PsychroError.temperatureOutOfRange(t)
        }
        try Psychrometrics.validate(humidityRatio: w)

        let ws = try Psychrometrics.saturationHumidityRatio(dryBulb: t, pressure: p)
        guard w <= ws * (1 + Psychrometrics.saturationTolerance) else {
            throw PsychroError.supersaturated(humidityRatio: w, saturation: ws)
        }
        let w = min(w, ws)

        self.pressure = p
        self.dryBulb = t
        self.humidityRatio = w
        self.saturationHumidityRatio = ws
        self.degreeOfSaturation = ws > 0 ? w / ws : 0
        self.enthalpy = Psychrometrics.enthalpy(dryBulb: t, humidityRatio: w)
        self.specificVolume = Psychrometrics.specificVolume(dryBulb: t, humidityRatio: w, pressure: p)
        self.wetBulb = try Psychrometrics.wetBulb(dryBulb: t, humidityRatio: w, pressure: p)
        self.dewPoint = w > 0 ? try Psychrometrics.dewPoint(humidityRatio: w, pressure: p) : nil

        let pw = try Psychrometrics.vapourPressure(humidityRatio: w, pressure: p)
        let pws = try Psychrometrics.saturationPressure(dryBulb: t)
        self.relativeHumidity = pws > 0 ? min(pw / pws, 1) : 0
    }

    /// Convenience: the everyday pair, dry bulb and relative humidity.
    public init(dryBulb t: Double, relativeHumidity r: Double, pressure p: Double) throws {
        try Psychrometrics.validate(relativeHumidity: r)
        let pw = r * (try Psychrometrics.saturationPressure(dryBulb: t))
        let w = try Psychrometrics.humidityRatio(vapourPressure: pw, pressure: p)
        try self.init(dryBulb: t, humidityRatio: w, pressure: p)
    }

    /// Is this state on the saturation curve, within the tolerance the chart draws at?
    public var isSaturated: Bool { degreeOfSaturation >= 0.9999 }
}

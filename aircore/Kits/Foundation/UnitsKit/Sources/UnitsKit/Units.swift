import Foundation

/// Which unit system the app is displaying in. Switching is free and reversible: the stored value
/// is always SI, so a switch converts the presentation and never re-rounds the number.
public enum UnitSystem: String, Codable, Sendable, CaseIterable, Hashable, Identifiable {
    case ip = "IP"
    case si = "SI"

    public var id: String { rawValue }

    public var other: UnitSystem { self == .ip ? .si : .ip }
}

/// The conversions this app needs, SI-canonical throughout.
///
/// ## Sources
///
/// Every factor below is either **exact by definition** or taken from **NIST Special Publication
/// 811**, *Guide for the Use of the International System of Units*, Appendix B. Nothing here is
/// rounded from a textbook: the inch is 0.0254 m exactly, the pound is 0.45359237 kg exactly, the
/// international-table Btu is 1055.05585262 J exactly, and every compound factor is built from
/// those rather than typed in.
public enum Units {

    // MARK: - Exact defining constants

    /// Metres per inch — exact by international agreement (1959).
    public static let metresPerInch = 0.0254
    /// Metres per foot — exact.
    public static let metresPerFoot = 0.3048
    /// Kilograms per pound (avoirdupois) — exact.
    public static let kilogramsPerPound = 0.45359237
    /// Joules per international-table Btu — exact.
    public static let joulesPerBtu = 1055.05585262
    /// Cubic metres per US liquid gallon — exact.
    public static let cubicMetresPerGallon = 3.785411784e-3
    /// Grains per pound — exact.
    public static let grainsPerPound = 7000.0

    // MARK: - Temperature

    /// °F as an absolute reading. Use ``Conversion/asDifference`` for a ΔT.
    public static let fahrenheit = Conversion(factor: 1 / 1.8, offset: -32 / 1.8)
    /// °C is SI here; present for symmetry so call sites can be written generically.
    public static let celsius = Conversion(factor: 1)

    // MARK: - Pressure

    /// Pounds per square inch → Pa. Built from the pound-force and the square inch.
    public static let poundsPerSquareInch =
        Conversion(factor: kilogramsPerPound * 9.80665 / (metresPerInch * metresPerInch))
    /// Inch of water gauge → Pa, at the HVAC reference temperature of 60 °F.
    ///
    /// The trade's "inch w.g." is a 60 °F column; the metrology tables' "inch of water" is usually
    /// a 4 °C column at 249.082 Pa. Using the wrong one is a 0.1 % error in every duct static
    /// pressure, so the choice is stated rather than left to whichever table was to hand.
    public static let inchOfWaterGauge = Conversion(factor: 248.84)
    /// Inch of mercury at 32 °F → Pa.
    public static let inchOfMercury = Conversion(factor: 3386.389)

    // MARK: - Moisture

    /// Grains of water per pound of dry air → kg/kg.
    public static let grainsPerPoundDryAir = Conversion(factor: 1 / grainsPerPound)
    /// Grams of water per kilogram of dry air → kg/kg. The SI trade unit.
    public static let gramsPerKilogramDryAir = Conversion(factor: 1e-3)

    // MARK: - Energy and enthalpy

    /// Btu per pound of dry air → kJ per kg of dry air.
    ///
    /// The factor works out to exactly 2.326. **The offset is the part that gets forgotten:** the
    /// IP enthalpy datum is 0 °F and the SI datum is 0 °C, a gap of 1.006 × 32/1.8 = 17.88 kJ/kg.
    /// Convert 47.54 kJ/kg with the factor alone and you get 20.44 Btu/lb where the chart says
    /// 28.13 — a 27 % error that looks entirely plausible on screen.
    public static let btuPerPoundDryAir =
        Conversion(factor: joulesPerBtu / kilogramsPerPound / 1000,
                   offset: -1.006 * 32 / 1.8)

    // MARK: - Volume, density, flow

    /// Cubic feet per pound → m³/kg.
    public static let cubicFeetPerPound =
        Conversion(factor: pow(metresPerFoot, 3) / kilogramsPerPound)
    /// Pounds per cubic foot → kg/m³.
    public static let poundsPerCubicFoot =
        Conversion(factor: kilogramsPerPound / pow(metresPerFoot, 3))
    /// Cubic feet per minute → m³/s.
    public static let cubicFeetPerMinute = Conversion(factor: pow(metresPerFoot, 3) / 60)
    /// Litres per second → m³/s. The SI trade unit for air flow.
    public static let litresPerSecond = Conversion(factor: 1e-3)
    /// US gallons per minute → m³/s.
    public static let gallonsPerMinute = Conversion(factor: cubicMetresPerGallon / 60)

    // MARK: - Length and velocity

    public static let feet = Conversion(factor: metresPerFoot)
    public static let inches = Conversion(factor: metresPerInch)
    public static let millimetres = Conversion(factor: 1e-3)
    /// Feet per minute → m/s.
    public static let feetPerMinute = Conversion(factor: metresPerFoot / 60)
    /// Feet per second → m/s.
    public static let feetPerSecond = Conversion(factor: metresPerFoot)

    // MARK: - Power

    /// Btu per hour → W.
    public static let btuPerHour = Conversion(factor: joulesPerBtu / 3600)
    /// Tons of refrigeration → W. One ton is 12,000 Btu/h by definition.
    public static let tonsOfRefrigeration = Conversion(factor: 12_000 * joulesPerBtu / 3600)
    public static let kilowatts = Conversion(factor: 1000)

    // MARK: - Water-side head

    /// Standard gravity, m/s².
    public static let standardGravity = 9.80665
    /// The reference water density behind "a foot of water", kg/m³.
    public static let referenceWaterDensity = 1000.0

    /// One foot of water column → Pa, at the 4 °C reference density.
    public static let footOfWater =
        Conversion(factor: referenceWaterDensity * standardGravity * metresPerFoot)
    /// Feet of water per 100 feet of pipe → Pa/m. The unit a hydronic run is sized in.
    public static let footOfWaterPer100Feet =
        Conversion(factor: referenceWaterDensity * standardGravity / 100)
    /// Kilopascals per metre → Pa/m. The SI counterpart.
    public static let kilopascalsPerMetre = Conversion(factor: 1000)

    // MARK: - Duct friction

    /// Inches of water gauge per 100 feet → Pa per metre. The friction rate a duct is sized at.
    public static let inchesOfWaterPer100Feet =
        Conversion(factor: inchOfWaterGauge.factor / (100 * metresPerFoot))
    /// Pascals per metre — SI is the identity, present so call sites stay symmetric.
    public static let pascalsPerMetre = Conversion(factor: 1)
}

import Foundation
@testable import PsychroKit

/// # The oracle
///
/// Every fixture below is an **independently produced** number, never one this Kit computed.
///
/// * Saturation pressures come from **IAPWS-95** (the international formulation for the
///   thermodynamic properties of water) via CoolProp 7, an MIT-licensed library. Hyland–Wexler,
///   which PsychroKit implements, is a separate correlation fitted decades earlier — so agreement
///   between them is evidence, not circular.
/// * Moist-air states come from **CoolProp's `HAPropsSI`**, a real-gas humid-air model built on
///   ASHRAE RP-1485. It is a different model from the ideal-gas relations PsychroKit implements,
///   which is exactly what makes it a usable oracle: where the two agree the implementation is
///   right, and where they differ the difference is the enhancement factor, quantified below.
/// * The IP anchor points (75 °F / 50 % RH → 62.5 °F wet bulb, 55.1 °F dew point, 28.1 Btu/lb)
///   are the published psychrometric-table values, and are asserted separately in
///   ``PublishedTableTests``.
///
/// Regenerate with `aircore/tools/gen_psychro_fixtures.py`; do not hand-edit the numbers. A
/// hand-edited oracle is no longer an oracle — it is a record of what the implementation printed.
enum Reference {

    // Barometric pressures, Pa. Sea level is the standard-atmosphere definition; the other two
    // are the standard atmosphere evaluated at Denver (5,280 ft) and Mexico City (7,350 ft).
    static let seaLevel = 101_325.0
    static let denver = 83_427.5113
    static let mexicoCity = 77_151.9526

    struct State {
        let name: String
        let pressure: Double
        let dryBulb: Double
        let relativeHumidity: Double
        let wetBulb: Double
        let dewPoint: Double
        let humidityRatio: Double
        let enthalpy: Double
        let specificVolume: Double
    }

    /// CoolProp `HAPropsSI` states spanning both unit systems' everyday range, all three
    /// altitudes, saturation, and both sides of freezing.
    static let states: [State] = [
        .init(name: "75 °F / 50 % sea level", pressure: seaLevel,
              dryBulb: 23.8888888889, relativeHumidity: 0.50,
              wetBulb: 16.970392, dewPoint: 12.847074,
              humidityRatio: 0.009277199, enthalpy: 47.634904, specificVolume: 0.8537081),
        .init(name: "95 °F / 40 % sea level", pressure: seaLevel,
              dryBulb: 35.0, relativeHumidity: 0.40,
              wetBulb: 23.930282, dewPoint: 19.391367,
              humidityRatio: 0.014200454, enthalpy: 71.637681, specificVolume: 0.8926173),
        .init(name: "55 °F / 90 % sea level", pressure: seaLevel,
              dryBulb: 12.7777777778, relativeHumidity: 0.90,
              wetBulb: 11.852233, dewPoint: 11.180574,
              humidityRatio: 0.008298765, enthalpy: 33.793566, specificVolume: 0.8204093),
        .init(name: "20 °F / 60 % sea level (below freezing)", pressure: seaLevel,
              dryBulb: -6.6666666667, relativeHumidity: 0.60,
              wetBulb: -8.292205, dewPoint: -12.440317,
              humidityRatio: 0.001290087, enthalpy: -3.494721, specificVolume: 0.7559558),
        .init(name: "0 °F / 70 % sea level (deep cold)", pressure: seaLevel,
              dryBulb: -17.7777777778, relativeHumidity: 0.70,
              wetBulb: -18.330949, dewPoint: -21.505779,
              humidityRatio: 0.000551006, enthalpy: -16.517443, specificVolume: 0.7234538),
        .init(name: "110 °F / 20 % sea level (hot dry)", pressure: seaLevel,
              dryBulb: 43.3333333333, relativeHumidity: 0.20,
              wetBulb: 24.138144, dewPoint: 15.504078,
              humidityRatio: 0.011052248, enthalpy: 72.128451, specificVolume: 0.9122945),
        .init(name: "85 °F / 5 % sea level (frost point below 0 °C)", pressure: seaLevel,
              dryBulb: 29.4444444444, relativeHumidity: 0.05,
              wetBulb: 11.614294, dewPoint: -12.608980,
              humidityRatio: 0.001270505, enthalpy: 32.867723, specificVolume: 0.8587154),
        .init(name: "60 °F / 100 % sea level (saturated)", pressure: seaLevel,
              dryBulb: 15.5555555556, relativeHumidity: 1.00,
              wetBulb: 15.555556, dewPoint: 15.555556,
              humidityRatio: 0.011089458, enthalpy: 43.685682, specificVolume: 0.8320594),
        .init(name: "32 °F / 100 % sea level (saturated at freezing)", pressure: seaLevel,
              dryBulb: 0.0, relativeHumidity: 1.00,
              wetBulb: 0.0, dewPoint: 0.0,
              humidityRatio: 0.003790035, enthalpy: 9.474751, specificVolume: 0.7780377),
        .init(name: "75 °F / 50 % Denver", pressure: denver,
              dryBulb: 23.8888888889, relativeHumidity: 0.50,
              wetBulb: 16.507175, dewPoint: 12.847750,
              humidityRatio: 0.011297562, enthalpy: 52.818703, specificVolume: 1.0402302),
        .init(name: "95 °F / 40 % Denver", pressure: denver,
              dryBulb: 35.0, relativeHumidity: 0.40,
              wetBulb: 23.363133, dewPoint: 19.392056,
              humidityRatio: 0.017322886, enthalpy: 79.687791, specificVolume: 1.0894713),
        .init(name: "55 °F / 90 % Denver", pressure: denver,
              dryBulb: 12.7777777778, relativeHumidity: 0.90,
              wetBulb: 11.777951, dewPoint: 11.180687,
              humidityRatio: 0.010102179, enthalpy: 38.391022, specificVolume: 0.9993376),
        .init(name: "20 °F / 60 % Denver (below freezing, at altitude)", pressure: denver,
              dryBulb: -6.6666666667, relativeHumidity: 0.60,
              wetBulb: -8.516711, dewPoint: -12.439878,
              humidityRatio: 0.001566454, enthalpy: -2.755403, specificVolume: 0.9186480),
        .init(name: "75 °F / 50 % Mexico City", pressure: mexicoCity,
              dryBulb: 23.8888888889, relativeHumidity: 0.50,
              wetBulb: 16.327516, dewPoint: 12.847977,
              humidityRatio: 0.012232284, enthalpy: 55.212356, specificVolume: 1.1265255),
        .init(name: "95 °F / 40 % Mexico City", pressure: mexicoCity,
              dryBulb: 35.0, relativeHumidity: 0.40,
              wetBulb: 23.146925, dewPoint: 19.392261,
              humidityRatio: 0.018771044, enthalpy: 83.417030, specificVolume: 1.1807734),
    ]

    struct SaturationPoint {
        let t: Double
        let pws: Double
    }

    /// Saturation pressure over **liquid water**, IAPWS-95 via CoolProp, Pa.
    static let saturationOverWater: [SaturationPoint] = [
        .init(t: 0.01, pws: 611.6548), .init(t: 5, pws: 872.5751), .init(t: 10, pws: 1228.1989),
        .init(t: 20, pws: 2339.3182), .init(t: 25, pws: 3169.9293), .init(t: 30, pws: 4246.9708),
        .init(t: 40, pws: 7384.9381), .init(t: 50, pws: 12351.9458), .init(t: 60, pws: 19946.4343),
        .init(t: 80, pws: 47414.4740), .init(t: 100, pws: 101417.9967),
    ]

    /// # Tolerances, and why each is the size it is
    ///
    /// These are not round numbers picked to make the suite pass. Each is the measured worst-case
    /// disagreement between the ideal-gas relations and CoolProp's real-gas model across the
    /// fixture set, rounded up to the next sensible figure. Tightening one below its measured
    /// value would be asserting agreement the two models do not have; loosening one would let a
    /// real regression through.
    enum Tolerance {
        /// 0.05 % — Hyland–Wexler against IAPWS-95 differs by at most 0.023 % over 0…100 °C.
        static let saturationPressureRelative = 5e-4
        /// 0.03 °C. The enhancement factor very nearly cancels in the wet-bulb balance: across the
        /// everyday band the worst disagreement is 0.008 °C. It widens to 0.025 °C only at the dry
        /// extreme (85 °F / 5 % RH), where there is least moisture for the cancellation to work
        /// with. 0.054 °F on the number the user reads.
        static let wetBulb = 0.03
        /// 0.03 °C — worst measured 0.013 °C.
        static let dewPoint = 0.03
        /// 0.6 % — the enhancement factor in full: real-gas W runs 0.38–0.52 % above ideal-gas.
        static let humidityRatioRelative = 6e-3
        /// 0.3 kJ/kg absolute — worst measured 0.22. Absolute rather than relative because
        /// enthalpy passes through zero near 0 °C, where a relative bound is meaningless.
        static let enthalpy = 0.3
        /// 0.15 % — worst measured 0.086 %.
        static let specificVolumeRelative = 1.5e-3
        /// 0.5 % on relative humidity recovered from a state, worst measured 0.45 %.
        static let relativeHumidityRelative = 5e-3
    }
}

// MARK: - Assertion helpers

func relativeError(_ actual: Double, _ expected: Double) -> Double {
    expected == 0 ? abs(actual) : abs(actual - expected) / abs(expected)
}

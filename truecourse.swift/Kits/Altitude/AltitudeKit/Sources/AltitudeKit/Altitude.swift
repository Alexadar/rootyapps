import Foundation

/// Altitude and standard-atmosphere math for the E6B flight computer.
///
/// All altitudes are geopotential feet, temperatures °C, pressures inches of mercury.
/// The ISA relations are the ICAO / ISO 2533 troposphere model (valid to ~36,089 ft).
public enum Altitude {

    /// ISA sea-level reference temperature (°C).
    public static let seaLevelTempC = 15.0
    /// Standard altimeter setting (inHg).
    public static let standardAltimeterInHg = 29.92
    /// ISA temperature lapse rate (°C per 1,000 ft) — 6.5 K/km.
    public static let lapseCPer1000ft = 1.9812

    /// ISA ambient temperature at a pressure altitude.
    public static func isaTempC(altitudeFt: Double) -> Double {
        seaLevelTempC - lapseCPer1000ft * altitudeFt / 1000
    }

    /// ISA pressure ratio δ = P/P₀ at a pressure altitude.
    public static func isaPressureRatio(altitudeFt: Double) -> Double {
        pow(1 - 6.8755856e-6 * altitudeFt, 5.2558797)
    }

    /// ISA density ratio σ = ρ/ρ₀ at a (standard-temperature) pressure altitude.
    public static func isaDensityRatio(altitudeFt: Double) -> Double {
        let delta = isaPressureRatio(altitudeFt: altitudeFt)
        let theta = (isaTempC(altitudeFt: altitudeFt) + 273.15) / (seaLevelTempC + 273.15)
        return delta / theta
    }

    /// Pressure altitude from the indicated altitude and the current altimeter setting
    /// (≈1,000 ft per inHg away from 29.92).
    public static func pressureAltitudeFt(indicatedAltFt: Double, altimeterInHg: Double) -> Double {
        indicatedAltFt + (standardAltimeterInHg - altimeterInHg) * 1000
    }

    /// Density altitude — the ISA altitude at which the ambient air density is found.
    /// Uses the published NWS/ISA closed form on the actual density ratio.
    public static func densityAltitudeFt(pressureAltFt: Double, oatC: Double) -> Double {
        let delta = isaPressureRatio(altitudeFt: pressureAltFt)
        let theta = (oatC + 273.15) / (seaLevelTempC + 273.15)
        let sigma = delta / theta
        return 145442.16 * (1 - pow(sigma, 0.234969))
    }

    /// Convective cloud base (AGL, ft) from the surface temperature/dew-point spread
    /// (≈2.5 °C per 1,000 ft).
    public static func cloudBaseFt(tempC: Double, dewpointC: Double) -> Double {
        max(0, tempC - dewpointC) / 2.5 * 1000
    }

    /// Freezing-level altitude (MSL, ft) from a surface temperature and field elevation.
    public static func freezingLevelFt(surfaceTempC: Double, elevationFt: Double) -> Double {
        elevationFt + surfaceTempC / lapseCPer1000ft * 1000
    }

    /// Pivotal altitude (ft AGL) for eights-on-pylons — GS(kt)² / 11.3.
    public static func pivotalAltitudeFt(gsKt: Double) -> Double {
        gsKt * gsKt / 11.3
    }
}

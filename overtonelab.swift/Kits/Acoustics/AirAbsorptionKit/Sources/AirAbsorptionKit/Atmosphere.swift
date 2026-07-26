import Foundation

/// Atmospheric sound absorption (ISO 9613-1:1993) and the speed of sound vs temperature.
/// Pure, stateless. MODEL CAVEAT: pure-tone attenuation in still, homogeneous air; wind, turbulence
/// and gradients over long outdoor throws diverge from this.
public enum Atmosphere {
    /// Speed of sound in air (m/s) at temperature `Tc` (°C): 331.3·√(1 + Tc/273.15) → 343.2 at 20 °C.
    public static func speedOfSound(tempC Tc: Double) -> Double {
        331.3 * (1 + Tc / 273.15).squareRoot()
    }

    /// ISO 9613-1 pure-tone atmospheric absorption coefficient α (dB/m).
    /// `f` Hz, `Tc` °C, `hr` relative humidity %, `pa` ambient pressure kPa.
    public static func absorptionDBPerM(freqHz f: Double, tempC Tc: Double,
                                        humidityPct hr: Double, pressureKPa pa: Double = 101.325) -> Double {
        let T = Tc + 273.15            // K
        let T0 = 293.15               // reference K (20 °C)
        let T01 = 273.16              // triple-point K
        let pr = 101.325             // reference kPa

        // Saturation vapour pressure ratio and molar water-vapour concentration h (%).
        let C = -6.8346 * pow(T01 / T, 1.261) + 4.6151
        let psatRatio = pow(10, C)
        let h = hr * psatRatio * (pr / pa)

        // Relaxation frequencies of oxygen and nitrogen.
        let frO = (pa / pr) * (24 + 4.04e4 * h * (0.02 + h) / (0.391 + h))
        let frN = (pa / pr) * pow(T / T0, -0.5)
            * (9 + 280 * h * exp(-4.170 * (pow(T / T0, -1.0 / 3.0) - 1)))

        let a = 8.686 * f * f * (1.84e-11 * (pr / pa) * pow(T / T0, 0.5)
            + pow(T / T0, -2.5) * (0.01275 * exp(-2239.1 / T) / (frO + f * f / frO)
                                 + 0.1068 * exp(-3352.0 / T) / (frN + f * f / frN)))
        return a
    }

    /// Absorption in dB/km.
    public static func absorptionDBPerKm(freqHz f: Double, tempC Tc: Double,
                                         humidityPct hr: Double, pressureKPa pa: Double = 101.325) -> Double {
        1000 * absorptionDBPerM(freqHz: f, tempC: Tc, humidityPct: hr, pressureKPa: pa)
    }

    /// Total atmospheric attenuation (dB) over `distanceM` metres.
    public static func lossDB(freqHz f: Double, tempC Tc: Double, humidityPct hr: Double,
                              distanceM d: Double, pressureKPa pa: Double = 101.325) -> Double {
        absorptionDBPerM(freqHz: f, tempC: Tc, humidityPct: hr, pressureKPa: pa) * d
    }

    /// Octave-band centre frequencies used for the per-band table (Hz).
    public static let octaveBands: [Double] = [63, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
}

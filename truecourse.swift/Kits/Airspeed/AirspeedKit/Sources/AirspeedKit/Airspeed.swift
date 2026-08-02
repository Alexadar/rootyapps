import Foundation

/// Airspeed math for the E6B flight computer.
///
/// The E6B TAS solution corrects calibrated airspeed by the square root of the ISA
/// density ratio σ (from pressure altitude and outside air temperature).
public enum Airspeed {

    /// ISA density ratio σ = ρ/ρ₀ from a pressure altitude and the actual OAT.
    private static func densityRatio(pressureAltFt: Double, oatC: Double) -> Double {
        let delta = pow(1 - 6.8755856e-6 * pressureAltFt, 5.2558797)   // ISA pressure ratio
        let theta = (oatC + 273.15) / 288.15                          // actual temp ratio
        return delta / theta
    }

    /// True airspeed from calibrated airspeed, pressure altitude and OAT: TAS = CAS / √σ.
    public static func tas(casKt: Double, pressureAltFt: Double, oatC: Double) -> Double {
        casKt / densityRatio(pressureAltFt: pressureAltFt, oatC: oatC).squareRoot()
    }

    /// Calibrated airspeed from true airspeed (inverse of `tas`): CAS = TAS · √σ.
    public static func cas(tasKt: Double, pressureAltFt: Double, oatC: Double) -> Double {
        tasKt * densityRatio(pressureAltFt: pressureAltFt, oatC: oatC).squareRoot()
    }

    /// Local speed of sound (knots) at an outside air temperature: a = 38.967854·√(T_K).
    public static func speedOfSoundKt(oatC: Double) -> Double {
        38.967854 * (oatC + 273.15).squareRoot()
    }

    /// Mach number from true airspeed and OAT.
    public static func mach(tasKt: Double, oatC: Double) -> Double {
        tasKt / speedOfSoundKt(oatC: oatC)
    }
}

import Foundation

/// Sensible / latent / total air-side heat, all with altitude-corrected constants.
/// Solve in any direction: given a load find CFM, given CFM + load find ΔT.
public enum AirSideHeat {

    /// Qs = c_s · CFM · ΔT   (Btu/h)
    public static func sensible(cfm: Double, deltaTF: Double, altitude: Altitude) -> Double {
        altitude.sensibleConstant * cfm * deltaTF
    }

    /// Ql = c_l · CFM · ΔW   (ΔW in lb/lb) (Btu/h)
    public static func latent(cfm: Double, deltaWLbLb: Double, altitude: Altitude) -> Double {
        altitude.latentConstant * cfm * deltaWLbLb
    }

    /// Qt = c_t · CFM · Δh   (Δh in Btu/lb) (Btu/h)
    public static func total(cfm: Double, deltaHBtuLb: Double, altitude: Altitude) -> Double {
        altitude.totalConstant * cfm * deltaHBtuLb
    }

    /// Inverse: CFM required for a sensible load at ΔT.
    public static func cfmForSensible(qs: Double, deltaTF: Double, altitude: Altitude) -> Double {
        guard deltaTF != 0 else { return .nan }
        return qs / (altitude.sensibleConstant * deltaTF)
    }

    /// Inverse: ΔT achieved by a sensible load at CFM.
    public static func deltaTForSensible(qs: Double, cfm: Double, altitude: Altitude) -> Double {
        guard cfm != 0 else { return .nan }
        return qs / (altitude.sensibleConstant * cfm)
    }
}

import Foundation

public enum HeatError: Error, Equatable, Sendable, CustomStringConvertible {
    /// A quantity that must be positive and finite was not.
    case invalidInput(name: String, value: Double)
    /// Solving in this direction would divide by zero — e.g. asking what flow delivers a load
    /// across a zero temperature difference.
    case indeterminate(name: String)

    public var description: String {
        switch self {
        case .invalidInput(let name, let value): return "\(name) is \(value)"
        case .indeterminate(let name): return "\(name) is zero, so this cannot be solved for"
        }
    }
}

/// Sensible, latent and total air-side heat — in SI, from actual air density.
///
/// ## Why this Kit takes mass flow and not CFM
///
/// The trade computes air-side loads with three constants: `Qs = 1.08 × CFM × ΔT`,
/// `Ql = 4840 × CFM × ΔW`, `Qt = 4.5 × CFM × Δh`. Each of those bakes in a specific air
/// density — 0.075 lb/ft³, standard air at sea level — and each is therefore **wrong everywhere
/// else**. In Denver the sensible constant is 0.89, not 1.08: an 18 % error on every duct.
///
/// So this Kit works from the mass flow of dry air, which carries the density with it, and the
/// constants come *out* of it rather than going in. ``sensibleConstantPerVolumeFlow(specificVolume:humidityRatio:)``
/// re-derives the field constant for whatever air is actually in the duct, and the test suite
/// proves it lands on the published 1.08 at standard air — so the number the app displays and the
/// number it computes with are the same number.
///
/// ## Source
///
/// ASHRAE Fundamentals Ch. 1: moist-air specific heat `cp = 1.006 + 1.86 W` kJ/(kg·K), and the
/// enthalpy of water vapour `h_g = 2501 + 1.86 t` kJ/kg — the same relations PsychroKit uses, so
/// a load computed here and an enthalpy difference read off the chart agree by construction.
public enum AirSideHeat {

    /// Specific heat of dry air at constant pressure, kJ/(kg·K).
    public static let dryAirSpecificHeat = 1.006
    /// Specific heat of water vapour at constant pressure, kJ/(kg·K).
    public static let waterVapourSpecificHeat = 1.86
    /// Enthalpy of saturated water vapour at 0 °C, kJ/kg.
    public static let vaporisationEnthalpyAtZero = 2501.0

    // MARK: - Properties

    /// Specific heat of moist air, kJ per kg of **dry air** per K.
    ///
    /// The moisture is not free: at a typical indoor humidity ratio this is 1.7 % above the
    /// dry-air value, which is the difference between the trade's 1.08 constant and the 1.10 that
    /// better references print.
    public static func specificHeat(humidityRatio w: Double) throws -> Double {
        guard w.isFinite, w >= 0 else { throw HeatError.invalidInput(name: "humidity ratio", value: w) }
        return dryAirSpecificHeat + waterVapourSpecificHeat * w
    }

    /// Enthalpy of water vapour at a dry-bulb temperature, kJ/kg — the coefficient on a latent load.
    public static func vaporisationEnthalpy(dryBulb t: Double) throws -> Double {
        guard t.isFinite else { throw HeatError.invalidInput(name: "dry bulb", value: t) }
        return vaporisationEnthalpyAtZero + waterVapourSpecificHeat * t
    }

    /// Mass flow of dry air, kg/s, from a volumetric flow and the air's specific volume.
    public static func dryAirMassFlow(volumeFlow: Double, specificVolume v: Double) throws -> Double {
        guard volumeFlow.isFinite, volumeFlow >= 0 else {
            throw HeatError.invalidInput(name: "volume flow", value: volumeFlow)
        }
        guard v.isFinite, v > 0 else {
            throw HeatError.invalidInput(name: "specific volume", value: v)
        }
        return volumeFlow / v
    }

    // MARK: - Loads

    /// Sensible heat, W. `Qs = ṁ · cp · ΔT`
    public static func sensibleHeat(dryAirMassFlow m: Double, humidityRatio w: Double,
                                    temperatureDifference dt: Double) throws -> Double {
        try validate(massFlow: m)
        guard dt.isFinite else { throw HeatError.invalidInput(name: "ΔT", value: dt) }
        return m * (try specificHeat(humidityRatio: w)) * dt * 1000
    }

    /// Latent heat, W. `Ql = ṁ · h_g(t) · ΔW`
    public static func latentHeat(dryAirMassFlow m: Double, humidityRatioDifference dw: Double,
                                  meanDryBulb t: Double) throws -> Double {
        try validate(massFlow: m)
        guard dw.isFinite else { throw HeatError.invalidInput(name: "ΔW", value: dw) }
        return m * (try vaporisationEnthalpy(dryBulb: t)) * dw * 1000
    }

    /// Total heat, W. `Qt = ṁ · Δh` — the one that needs no separate sensible/latent split, and
    /// the one to prefer when both endpoints are known states.
    public static func totalHeat(dryAirMassFlow m: Double,
                                 enthalpyDifference dh: Double) throws -> Double {
        try validate(massFlow: m)
        guard dh.isFinite else { throw HeatError.invalidInput(name: "Δh", value: dh) }
        return m * dh * 1000
    }

    // MARK: - Solved the other way

    /// Dry-air mass flow needed to carry a sensible load across a temperature difference, kg/s.
    public static func dryAirMassFlow(sensibleHeat q: Double, humidityRatio w: Double,
                                      temperatureDifference dt: Double) throws -> Double {
        guard q.isFinite else { throw HeatError.invalidInput(name: "sensible heat", value: q) }
        guard dt != 0, dt.isFinite else { throw HeatError.indeterminate(name: "ΔT") }
        return q / ((try specificHeat(humidityRatio: w)) * dt * 1000)
    }

    /// Temperature difference a sensible load produces at a given flow, K.
    public static func temperatureDifference(sensibleHeat q: Double, dryAirMassFlow m: Double,
                                             humidityRatio w: Double) throws -> Double {
        guard q.isFinite else { throw HeatError.invalidInput(name: "sensible heat", value: q) }
        guard m != 0, m.isFinite else { throw HeatError.indeterminate(name: "mass flow") }
        return q / ((try specificHeat(humidityRatio: w)) * m * 1000)
    }

    /// Dry-air mass flow needed to carry a total load across an enthalpy difference, kg/s.
    public static func dryAirMassFlow(totalHeat q: Double,
                                      enthalpyDifference dh: Double) throws -> Double {
        guard q.isFinite else { throw HeatError.invalidInput(name: "total heat", value: q) }
        guard dh != 0, dh.isFinite else { throw HeatError.indeterminate(name: "Δh") }
        return q / (dh * 1000)
    }

    /// Enthalpy difference a total load produces at a given flow, kJ/kg dry air.
    public static func enthalpyDifference(totalHeat q: Double,
                                          dryAirMassFlow m: Double) throws -> Double {
        guard q.isFinite else { throw HeatError.invalidInput(name: "total heat", value: q) }
        guard m != 0, m.isFinite else { throw HeatError.indeterminate(name: "mass flow") }
        return q / (m * 1000)
    }

    /// Humidity-ratio difference a latent load produces at a given flow, kg/kg dry air.
    public static func humidityRatioDifference(latentHeat q: Double, dryAirMassFlow m: Double,
                                               meanDryBulb t: Double) throws -> Double {
        guard q.isFinite else { throw HeatError.invalidInput(name: "latent heat", value: q) }
        guard m != 0, m.isFinite else { throw HeatError.indeterminate(name: "mass flow") }
        return q / ((try vaporisationEnthalpy(dryBulb: t)) * m * 1000)
    }

    /// Sensible heat ratio — sensible over total. The number that says whether a coil is fighting
    /// heat or moisture.
    public static func sensibleHeatRatio(sensible: Double, total: Double) throws -> Double {
        guard total != 0, total.isFinite else { throw HeatError.indeterminate(name: "total heat") }
        return sensible / total
    }

    // MARK: - The field constants, re-derived

    /// The trade's sensible constant for the air actually in the duct: watts per (m³/s) per K.
    ///
    /// Multiply out to the IP form and this is the "1.08". It is returned rather than stored
    /// because it is a property of the air, not a constant of nature — see the type's discussion.
    public static func sensibleConstantPerVolumeFlow(specificVolume v: Double,
                                                     humidityRatio w: Double) throws -> Double {
        try sensibleHeat(dryAirMassFlow: try dryAirMassFlow(volumeFlow: 1, specificVolume: v),
                         humidityRatio: w, temperatureDifference: 1)
    }

    /// The trade's latent constant for this air: watts per (m³/s) per unit humidity ratio.
    public static func latentConstantPerVolumeFlow(specificVolume v: Double,
                                                   meanDryBulb t: Double) throws -> Double {
        try latentHeat(dryAirMassFlow: try dryAirMassFlow(volumeFlow: 1, specificVolume: v),
                       humidityRatioDifference: 1, meanDryBulb: t)
    }

    /// The trade's total constant for this air: watts per (m³/s) per (kJ/kg).
    public static func totalConstantPerVolumeFlow(specificVolume v: Double) throws -> Double {
        try totalHeat(dryAirMassFlow: try dryAirMassFlow(volumeFlow: 1, specificVolume: v),
                      enthalpyDifference: 1)
    }

    private static func validate(massFlow m: Double) throws {
        guard m.isFinite, m >= 0 else { throw HeatError.invalidInput(name: "mass flow", value: m) }
    }
}

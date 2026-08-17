import Foundation

/// A fully solved moist-air state. All temperatures in °F, W in grains/lb,
/// h in Btu/lb dry air, v in ft³/lb dry air. Convert for SI at the edge.
public struct PsychroState: Equatable, Sendable {
    public var dryBulb: Double
    public var relHumidity: Double   // %
    public var wetBulb: Double
    public var dewPoint: Double
    public var humidityRatio: Double // grains/lb
    public var enthalpy: Double      // Btu/lb
    public var specificVolume: Double // ft³/lb
    public var degreeOfSaturation: Double // %
}

public enum Psychrometrics {

    /// Saturation vapour pressure over water, Pa, for dry-bulb °F (Magnus form).
    public static func satPressure(dryBulbF: Double) -> Double {
        let c = Temp.fToC(dryBulbF)
        return 611.2 * exp(17.62 * c / (243.12 + c))
    }

    /// Humidity ratio (mass basis, lb/lb) from dry-bulb °F, RH fraction, pressure Pa.
    public static func humidityRatio(dryBulbF: Double, rh: Double, pressurePa P: Double) -> Double {
        let pw = rh * satPressure(dryBulbF: dryBulbF)
        return 0.62198 * pw / (P - pw)
    }

    /// Solve the full state from dry bulb + relative humidity at a given altitude.
    public static func solve(dryBulbF db: Double, relHumidityPercent rhPct: Double,
                             altitude: Altitude) -> PsychroState {
        let P = altitude.pressurePa
        let rh = rhPct / 100
        let pw = rh * satPressure(dryBulbF: db)
        let w = 0.62198 * pw / (P - pw)                       // lb/lb
        let ws = humidityRatio(dryBulbF: db, rh: 1, pressurePa: P)
        let h = 0.240 * db + w * (1061 + 0.444 * db)          // Btu/lb
        let pPsia = P / 6894.757
        let v = 53.352 * (db + 459.67) / (144 * pPsia) * (1 + 1.6078 * w)

        var dp = -60.0
        if pw > 1 {
            let l = log(pw / 611.2)
            dp = (243.12 * l / (17.62 - l)) * 1.8 + 32
        }

        // Wet bulb by bisection on the psychrometric energy balance.
        var lo = max(dp, -50.0), hi = db, wb = db
        for _ in 0..<40 {
            wb = (lo + hi) / 2
            let wsw = humidityRatio(dryBulbF: wb, rh: 1, pressurePa: P)
            let wCalc = ((1093 - 0.556 * wb) * wsw - 0.240 * (db - wb)) / (1093 + 0.444 * db - wb)
            if wCalc > w { hi = wb } else { lo = wb }
        }

        let mu = ws > 0 ? w / ws * 100 : 0
        return PsychroState(dryBulb: db, relHumidity: rhPct, wetBulb: wb, dewPoint: dp,
                            humidityRatio: w * 7000, enthalpy: h, specificVolume: v,
                            degreeOfSaturation: mu)
    }

    /// Adiabatic mix of two airstreams (CFM + state each) -> mixed dry bulb, W, RH proxy.
    public static func mix(_ a: PsychroState, cfmA: Double,
                           _ b: PsychroState, cfmB: Double,
                           altitude: Altitude) -> (dryBulb: Double, humidityRatio: Double) {
        let total = cfmA + cfmB
        guard total > 0 else { return (a.dryBulb, a.humidityRatio) }
        let db = (a.dryBulb * cfmA + b.dryBulb * cfmB) / total
        let w = (a.humidityRatio * cfmA + b.humidityRatio * cfmB) / total
        return (db, w)
    }
}

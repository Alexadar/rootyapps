import Foundation

/// The published moist-air relations, in SI throughout: °C, Pa, kg water / kg dry air,
/// kJ / kg dry air, m³ / kg dry air. IP conversion happens at the app edge, never here.
///
/// ## Sources
///
/// * Saturation pressure — **Hyland & Wexler (1983)**, the correlation ASHRAE Fundamentals
///   Ch. 1 adopts. Two branches: over ice below 0 °C, over liquid water at and above it.
///   Published validity −100 … 200 °C.
/// * Humidity ratio, degree of saturation, specific volume, enthalpy and the psychrometric
///   wet-bulb relation — **ASHRAE Fundamentals Ch. 1**, ideal-gas form.
///
/// ## The one deliberate approximation
///
/// These are the ideal-gas relations. They omit the real-gas **enhancement factor** (f ≈ 1.004),
/// so humidity ratio and enthalpy run about 0.4 % below a real-gas reference such as CoolProp
/// while wet bulb and dew point agree to better than 0.02 °C — the enhancement factor very nearly
/// cancels in the temperatures. That is the trade every published chart equation makes, and the
/// oracle suite pins the size of it rather than pretending it is absent. Mixing a real-gas humidity
/// ratio into an ideal-gas wet-bulb equation would break the round trips instead.
public enum Psychrometrics {

    /// Ratio of the molecular masses of water and dry air (ASHRAE Ch. 1).
    public static let molecularMassRatio = 0.621945
    /// Dry-air gas constant, kJ/(kg·K).
    public static let dryAirGasConstant = 0.287042

    /// Published validity range of the Hyland–Wexler correlations, °C.
    public static let temperatureRange = -100.0 ... 200.0
    /// Barometric pressures this Kit will accept, Pa. Well outside any habitable elevation,
    /// tight enough to reject zero, negatives and unit mistakes.
    public static let pressureRange = 10_000.0 ... 200_000.0

    /// How far above saturation a humidity ratio may sit before it is an error rather than a
    /// state sitting *on* the saturation curve, as a fraction of the saturation ratio.
    ///
    /// This is not a fudge factor, it is the size of a real discontinuity. Hyland–Wexler changes
    /// equation at 0 °C, and the ice and water branches disagree there by 9.7 × 10⁻⁵ — so the
    /// saturation curve has a step in it at exactly the temperature where a technician enters
    /// 32 °F / 100 %. Without this band, whether a saturated freezing state is accepted or
    /// rejected depends on which side of zero the last bit of a root find happens to land.
    ///
    /// 2 × 10⁻⁴ is twice that step and still 0.0008 gr/lb at a typical winter humidity ratio —
    /// two orders of magnitude below anything the app displays. Genuine supersaturation (mixing
    /// to fog, a dew point above the dry bulb) exceeds it by percent, not by parts per ten
    /// thousand, so nothing real slips through.
    public static let saturationTolerance = 2e-4

    // MARK: - Saturation pressure

    /// Saturation vapour pressure over water (≥ 0 °C) or ice (< 0 °C), Pa.
    ///
    /// Hyland & Wexler (1983). The two branches differ by 0.0097 % at 0 °C; that step is the
    /// correlation's own, not a defect introduced here.
    public static func saturationPressure(dryBulb t: Double) throws -> Double {
        guard t.isFinite, temperatureRange.contains(t) else {
            throw PsychroError.temperatureOutOfRange(t)
        }
        let T = t + 273.15
        let ln: Double
        if t < 0 {
            ln = -5.6745359e3 / T + 6.3925247
                + -9.677843e-3 * T + 6.2215701e-7 * T * T
                + 2.0747825e-9 * T * T * T + -9.484024e-13 * T * T * T * T
                + 4.1635019 * log(T)
        } else {
            ln = -5.8002206e3 / T + 1.3914993
                + -4.8640239e-2 * T + 4.1764768e-5 * T * T
                + -1.4452093e-8 * T * T * T
                + 6.5459673 * log(T)
        }
        return exp(ln)
    }

    /// The temperature at which `pressure` is the saturation pressure — i.e. the dew point
    /// (frost point below 0 °C). Numeric inverse of ``saturationPressure(dryBulb:)``.
    public static func saturationTemperature(pressure pw: Double) throws -> Double {
        guard pw.isFinite, pw > 0 else { throw PsychroError.humidityRatioOutOfRange(pw) }
        let loBound = try saturationPressure(dryBulb: temperatureRange.lowerBound)
        let hiBound = try saturationPressure(dryBulb: temperatureRange.upperBound)
        guard pw >= loBound, pw <= hiBound else { throw PsychroError.unsolvable }
        return bisect(temperatureRange.lowerBound, temperatureRange.upperBound) { t in
            ((try? saturationPressure(dryBulb: t)) ?? 0) - pw
        }
    }

    // MARK: - Moisture measures

    /// Humidity ratio from water-vapour partial pressure. ASHRAE Ch. 1 eq. 20.
    public static func humidityRatio(vapourPressure pw: Double, pressure p: Double) throws -> Double {
        try validate(pressure: p)
        guard pw.isFinite, pw >= 0, pw < p else { throw PsychroError.unsolvable }
        return molecularMassRatio * pw / (p - pw)
    }

    /// Water-vapour partial pressure from humidity ratio. Inverse of eq. 20.
    public static func vapourPressure(humidityRatio w: Double, pressure p: Double) throws -> Double {
        try validate(pressure: p)
        try validate(humidityRatio: w)
        return p * w / (molecularMassRatio + w)
    }

    /// Humidity ratio of saturated air at this dry bulb and pressure.
    public static func saturationHumidityRatio(dryBulb t: Double, pressure p: Double) throws -> Double {
        try humidityRatio(vapourPressure: try saturationPressure(dryBulb: t), pressure: p)
    }

    // MARK: - Derived properties

    /// Specific enthalpy, kJ per kg of dry air. ASHRAE Ch. 1 eq. 30.
    public static func enthalpy(dryBulb t: Double, humidityRatio w: Double) -> Double {
        1.006 * t + w * (2501.0 + 1.86 * t)
    }

    /// Specific volume, m³ per kg of dry air. ASHRAE Ch. 1 eq. 26.
    public static func specificVolume(dryBulb t: Double, humidityRatio w: Double,
                                      pressure p: Double) -> Double {
        dryAirGasConstant * (t + 273.15) * (1 + 1.607858 * w) / (p / 1000.0)
    }

    /// Dry bulb implied by an enthalpy and a humidity ratio. Inverse of eq. 30.
    public static func dryBulb(enthalpy h: Double, humidityRatio w: Double) -> Double {
        (h - 2501.0 * w) / (1.006 + 1.86 * w)
    }

    /// Humidity ratio implied by an enthalpy at a known dry bulb. Inverse of eq. 30.
    public static func humidityRatio(enthalpy h: Double, dryBulb t: Double) -> Double {
        (h - 1.006 * t) / (2501.0 + 1.86 * t)
    }

    /// Humidity ratio implied by a specific volume at a known dry bulb. Inverse of eq. 26.
    public static func humidityRatio(specificVolume v: Double, dryBulb t: Double,
                                     pressure p: Double) throws -> Double {
        try validate(pressure: p)
        guard v.isFinite, v > 0 else { throw PsychroError.specificVolumeOutOfRange(v) }
        let dryAirVolume = dryAirGasConstant * (t + 273.15) / (p / 1000.0)
        return (v / dryAirVolume - 1) / 1.607858
    }

    // MARK: - Wet bulb

    /// Humidity ratio of air at dry bulb `t` whose thermodynamic wet bulb is `tStar`.
    /// ASHRAE Ch. 1 eq. 33 above freezing, eq. 35 below.
    public static func humidityRatio(dryBulb t: Double, wetBulb tStar: Double,
                                     pressure p: Double) throws -> Double {
        let wsStar = try saturationHumidityRatio(dryBulb: tStar, pressure: p)
        if tStar >= 0 {
            return ((2501.0 - 2.326 * tStar) * wsStar - 1.006 * (t - tStar))
                 / (2501.0 + 1.86 * t - 4.186 * tStar)
        }
        return ((2830.0 - 0.24 * tStar) * wsStar - 1.006 * (t - tStar))
             / (2830.0 + 1.86 * t - 2.1 * tStar)
    }

    /// Thermodynamic wet bulb for a known dry bulb and humidity ratio.
    ///
    /// The psychrometric relation is monotonic in wet bulb, and the answer is bracketed below by
    /// the dew point and above by the dry bulb — so this is a bisection that cannot wander, unlike
    /// bracketing on a separately-derived dew point.
    public static func wetBulb(dryBulb t: Double, humidityRatio w: Double,
                               pressure p: Double) throws -> Double {
        let ws = try saturationHumidityRatio(dryBulb: t, pressure: p)
        guard w <= ws * (1 + saturationTolerance) else {
            throw PsychroError.supersaturated(humidityRatio: w, saturation: ws)
        }
        if w >= ws { return t }                       // saturated: wet bulb is the dry bulb
        // The dew point is the tightest valid lower bracket — but perfectly dry air has none,
        // and it still has a wet bulb, so fall back to the bottom of the correlation's range.
        let dewPoint = (try? dewPoint(humidityRatio: w, pressure: p)) ?? temperatureRange.lowerBound
        let lo = max(temperatureRange.lowerBound, dewPoint)
        guard lo < t else { return t }
        return bisect(lo, t) { tStar in
            ((try? humidityRatio(dryBulb: t, wetBulb: tStar, pressure: p)) ?? -.greatestFiniteMagnitude) - w
        }
    }

    /// Dew point (frost point below 0 °C) for a humidity ratio at a pressure.
    public static func dewPoint(humidityRatio w: Double, pressure p: Double) throws -> Double {
        let pw = try vapourPressure(humidityRatio: w, pressure: p)
        return try saturationTemperature(pressure: pw)
    }

    // MARK: - Validation

    static func validate(pressure p: Double) throws {
        guard p.isFinite, pressureRange.contains(p) else { throw PsychroError.pressureOutOfRange(p) }
    }

    static func validate(humidityRatio w: Double) throws {
        guard w.isFinite, w >= 0 else { throw PsychroError.humidityRatioOutOfRange(w) }
    }

    static func validate(relativeHumidity r: Double) throws {
        guard r.isFinite, r >= 0, r <= 1 else { throw PsychroError.relativeHumidityOutOfRange(r) }
    }

    // MARK: - Root finding

    /// Bisection on a function known to change sign once across `[lo, hi]`, run to the limit of
    /// Double resolution. Deterministic and allocation-free — the whole app's numbers come through
    /// here, so it must behave identically on every platform.
    static func bisect(_ lo: Double, _ hi: Double, _ f: (Double) -> Double) -> Double {
        var lo = lo, hi = hi
        let ascending = f(lo) < 0
        for _ in 0..<200 {
            let mid = (lo + hi) / 2
            if mid == lo || mid == hi { break }
            if (f(mid) < 0) == ascending { lo = mid } else { hi = mid }
        }
        return (lo + hi) / 2
    }
}

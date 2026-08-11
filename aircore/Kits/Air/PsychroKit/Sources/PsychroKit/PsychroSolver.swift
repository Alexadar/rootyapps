import Foundation

/// One known property of a moist-air state.
public enum PsychroInput: Equatable, Sendable, Hashable {
    /// Dry-bulb temperature, °C.
    case dryBulb(Double)
    /// Thermodynamic wet-bulb temperature, °C.
    case wetBulb(Double)
    /// Dew point (frost point below 0 °C), °C.
    case dewPoint(Double)
    /// Relative humidity, 0…1.
    case relativeHumidity(Double)
    /// Humidity ratio, kg water per kg dry air.
    case humidityRatio(Double)
    /// Specific enthalpy, kJ per kg dry air.
    case enthalpy(Double)
    /// Specific volume, m³ per kg dry air.
    case specificVolume(Double)

    /// Which property this is, ignoring its value — two knowns of the same kind determine nothing.
    public enum Kind: String, CaseIterable, Sendable, Hashable {
        case dryBulb, wetBulb, dewPoint, relativeHumidity, humidityRatio, enthalpy, specificVolume
    }

    public var kind: Kind {
        switch self {
        case .dryBulb:          return .dryBulb
        case .wetBulb:          return .wetBulb
        case .dewPoint:         return .dewPoint
        case .relativeHumidity: return .relativeHumidity
        case .humidityRatio:    return .humidityRatio
        case .enthalpy:         return .enthalpy
        case .specificVolume:   return .specificVolume
        }
    }

    public var value: Double {
        switch self {
        case .dryBulb(let v), .wetBulb(let v), .dewPoint(let v), .relativeHumidity(let v),
             .humidityRatio(let v), .enthalpy(let v), .specificVolume(let v):
            return v
        }
    }
}

extension PsychroInput {

    /// The dry bulb this known fixes outright, if it is the dry bulb.
    var fixedDryBulb: Double? {
        if case .dryBulb(let t) = self { return t }
        return nil
    }

    /// Pairs whose lines on the chart lie so nearly on top of each other that their intersection
    /// is worthless, however well the arithmetic behaves.
    ///
    /// **Wet bulb and enthalpy.** Constant-wet-bulb and constant-enthalpy lines on a psychrometric
    /// chart are famously near-coincident — that near-coincidence is why the chart can carry one
    /// oblique scale for both. Measured on this implementation at 75 °F / 50 %: moving the entered
    /// wet bulb by 0.05 °C moves the answer by **5.2 °C**, and moving the entered enthalpy by
    /// 0.5 kJ/kg moves it by **16.8 °C**. For saturated air the two are exactly degenerate and
    /// there is no intersection at all. A user typing rounded values off a gauge would get a
    /// confident, wildly wrong state — so the pair is refused rather than served.
    /// Public so a UI can grey the pair out rather than offer it and then explain the error.
    public static let degeneratePairs: Set<Set<Kind>> = [[.wetBulb, .enthalpy]]

    /// Does this known pin a humidity ratio without reference to the dry bulb?
    ///
    /// Dew point and humidity ratio both do. Two of them together describe a vertical line on the
    /// chart rather than a point, which is why the solver rejects that pair instead of picking a
    /// dry bulb for the user.
    var isDryBulbIndependent: Bool {
        switch self {
        case .dewPoint, .humidityRatio: return true
        default:                        return false
        }
    }

    /// The humidity ratio this known implies at a candidate dry bulb.
    ///
    /// Every known except the dry bulb reduces to this one function, which is what lets a single
    /// root find cover every pair rather than a switch over 21 combinations.
    func humidityRatio(atDryBulb t: Double, pressure p: Double) throws -> Double {
        switch self {
        case .dryBulb:
            throw PsychroError.duplicateInput

        case .relativeHumidity(let r):
            try Psychrometrics.validate(relativeHumidity: r)
            let pw = r * (try Psychrometrics.saturationPressure(dryBulb: t))
            return try Psychrometrics.humidityRatio(vapourPressure: pw, pressure: p)

        case .dewPoint(let td):
            let pw = try Psychrometrics.saturationPressure(dryBulb: td)
            return try Psychrometrics.humidityRatio(vapourPressure: pw, pressure: p)

        case .humidityRatio(let w):
            try Psychrometrics.validate(humidityRatio: w)
            return w

        case .wetBulb(let tStar):
            guard tStar.isFinite, Psychrometrics.temperatureRange.contains(tStar) else {
                throw PsychroError.temperatureOutOfRange(tStar)
            }
            return try Psychrometrics.humidityRatio(dryBulb: t, wetBulb: tStar, pressure: p)

        case .enthalpy(let h):
            guard h.isFinite else { throw PsychroError.unsolvable }
            return Psychrometrics.humidityRatio(enthalpy: h, dryBulb: t)

        case .specificVolume(let v):
            return try Psychrometrics.humidityRatio(specificVolume: v, dryBulb: t, pressure: p)
        }
    }
}

extension MoistAir {

    /// Solve the whole state from **any two knowns**.
    ///
    /// Where one known is the dry bulb this is a direct evaluation. Where neither is, the two
    /// knowns are both curves of humidity ratio against dry bulb, and the state is where they
    /// cross — found by scanning the valid temperature range for a sign change and bisecting it.
    /// The scan is what makes non-monotonic pairs safe: a Newton step would happily converge on
    /// the wrong branch and return a plausible number.
    ///
    /// - Throws: ``PsychroError/duplicateInput`` for two knowns of one kind,
    ///   ``PsychroError/underdetermined`` for two knowns that fix only moisture, and
    ///   ``PsychroError/unsolvable`` where the pair describes no reachable state.
    public static func solve(_ a: PsychroInput, _ b: PsychroInput,
                             pressure p: Double) throws -> MoistAir {
        try Psychrometrics.validate(pressure: p)
        guard a.kind != b.kind else { throw PsychroError.duplicateInput }

        if let t = a.fixedDryBulb {
            return try MoistAir(dryBulb: t, humidityRatio: b.humidityRatio(atDryBulb: t, pressure: p),
                                pressure: p)
        }
        if let t = b.fixedDryBulb {
            return try MoistAir(dryBulb: t, humidityRatio: a.humidityRatio(atDryBulb: t, pressure: p),
                                pressure: p)
        }
        guard !(a.isDryBulbIndependent && b.isDryBulbIndependent) else {
            throw PsychroError.underdetermined
        }
        guard !PsychroInput.degeneratePairs.contains([a.kind, b.kind]) else {
            throw PsychroError.degeneratePair(a.kind, b.kind)
        }

        let t = try dryBulbWhereKnownsAgree(a, b, pressure: p)
        let w = try a.humidityRatio(atDryBulb: t, pressure: p)
        return try MoistAir(dryBulb: t, humidityRatio: w, pressure: p)
    }

    /// Scan the valid range for the dry bulb at which both knowns imply the same humidity ratio.
    private static func dryBulbWhereKnownsAgree(_ a: PsychroInput, _ b: PsychroInput,
                                                pressure p: Double) throws -> Double {
        func gap(_ t: Double) -> Double? {
            guard let wa = try? a.humidityRatio(atDryBulb: t, pressure: p),
                  let wb = try? b.humidityRatio(atDryBulb: t, pressure: p),
                  wa.isFinite, wb.isFinite else { return nil }
            return wa - wb
        }

        // 0.25 °C over the published range: fine enough that no pair the app can produce hides a
        // sign change inside one step, cheap enough to run on every keystroke.
        let step = 0.25
        let lo = Psychrometrics.temperatureRange.lowerBound
        let hi = Psychrometrics.temperatureRange.upperBound

        /// Below this the two curves are the same curve to any precision the app can display —
        /// 1e-7 kg/kg is 0.0007 gr/lb. A "crossing" found inside that band is floating-point
        /// noise, and following it lands wherever the noise happens to flip sign: the scaffold's
        /// failure mode of a confident answer at the very bottom of the temperature range.
        let degenerateBand = 1e-7

        var previousT: Double?
        var previousGap: Double?
        var largestGap = 0.0
        var crossing: (lo: Double, hi: Double, gapAtLo: Double)?
        var t = lo
        while t <= hi {
            defer { t += step }
            guard let g = gap(t) else { previousT = nil; previousGap = nil; continue }
            largestGap = max(largestGap, abs(g))
            if crossing == nil {
                if g == 0 {
                    crossing = (t, t, 0)
                } else if let pt = previousT, let pg = previousGap, (pg < 0) != (g < 0) {
                    crossing = (pt, t, pg)
                }
            }
            previousT = t
            previousGap = g
        }

        guard largestGap > degenerateBand else {
            throw PsychroError.degeneratePair(a.kind, b.kind)
        }
        guard let crossing else { throw PsychroError.unsolvable }
        if crossing.lo == crossing.hi { return crossing.lo }
        return Psychrometrics.bisect(crossing.lo, crossing.hi) { gap($0) ?? crossing.gapAtLo }
    }
}

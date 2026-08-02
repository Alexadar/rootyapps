import Foundation

/// The four angles of a chart, in ecliptic longitude (degrees, [0, 360)).
public struct ChartAngles: Hashable, Sendable {
    /// Ascendant — the rising degree of the ecliptic on the eastern horizon.
    public let ascendant: Double
    /// Midheaven (Medium Coeli) — where the ecliptic meets the upper meridian.
    public let midheaven: Double
    /// Right Ascension of the Midheaven (= local sidereal time), degrees. Diagnostic.
    public let ramc: Double
    /// Mean obliquity of the ecliptic used for this moment, degrees. Diagnostic.
    public let obliquity: Double

    public var descendant: Double { AstroMath.norm360(ascendant + 180) }
    public var imumCoeli: Double  { AstroMath.norm360(midheaven + 180) }

    public var ascendantSign: ZodiacSign { ZodiacSign.from(longitude: ascendant) }
    public var midheavenSign: ZodiacSign { ZodiacSign.from(longitude: midheaven) }
}

/// Twelve house cusps plus the angles they were built from.
public struct HouseCusps: Hashable, Sendable {
    public let system: HouseSystem
    /// Ecliptic longitudes of cusps 1…12, `cusps[0]` = house 1. Degrees, [0, 360).
    public let cusps: [Double]
    public let angles: ChartAngles

    /// Cusp of house `n` (1…12); wraps, so `cusp(13) == cusp(1)`.
    public func cusp(_ n: Int) -> Double {
        cusps[((n - 1) % 12 + 12) % 12]
    }

    public func sign(ofCusp n: Int) -> ZodiacSign {
        ZodiacSign.from(longitude: cusp(n))
    }

    /// Which house (1…12) a given ecliptic longitude falls in.
    public func house(containing longitude: Double) -> Int {
        let l = AstroMath.norm360(longitude)
        for n in 1...12 {
            let start = cusp(n)
            let span = AstroMath.norm360(cusp(n + 1) - start)
            if AstroMath.norm360(l - start) < span { return n }
        }
        return 1
    }
}

/// House and angle computation.
///
/// Everything is built from one anchor — the Right Ascension of the Midheaven (RAMC, i.e. the
/// local sidereal time) — plus the observer's latitude and the obliquity of the ecliptic.
///
/// The four *quadrant* systems all belong to one family of great circles: every "house circle"
/// passes through the north and south points of the horizon (which are antipodal, so the family
/// is a pencil of circles). A member of that family is fixed by where it crosses the celestial
/// equator, an angle `H` east of the meridian, and the ecliptic longitude of its intersection is
///
///     λ = atan2( sin(OA),  cos(OA)·cos(ε) − tan(P)·sin(ε) ),
///     OA = RAMC + H,   tan(P) = tan(φ)·sin(H)
///
/// which collapses to the Midheaven at `H = 0` (P = 0) and to the Ascendant at `H = 90°`
/// (P = φ). The systems differ only in how they choose `H`:
///   - **Regiomontanus** divides the *equator* evenly:      `H = 30n`
///   - **Campanus** divides the *prime vertical* evenly:    `tan H = cos(φ)·cot(C)`, `C = 90 − 30n`
///
/// The two time-based systems instead trisect a diurnal arc and are defined by right ascension:
///   - **Placidus** trisects *each cusp's own* semi-arc (needs iteration)
///   - **Koch** trisects the *Ascendant's* semi-arc (closed form)
/// Both involve `asin(tan φ · tan δ)`, which has no solution when the point is circumpolar —
/// that is exactly why they fail at high latitudes, and why `compute` is optional.
public enum Houses {

    // MARK: Angles

    /// Ascendant, Midheaven and friends for a moment and a place.
    public static func angles(at date: Date, location: GeoLocation) -> ChartAngles {
        let ramc = SiderealTime.ramc(at: date, longitude: location.longitude)
        let eps = SiderealTime.meanObliquity(at: date)
        return ChartAngles(ascendant: ascendant(ramc: ramc, latitude: location.latitude, obliquity: eps),
                           midheaven: midheaven(ramc: ramc, obliquity: eps),
                           ramc: ramc,
                           obliquity: eps)
    }

    /// Ecliptic longitude of the upper meridian: tan(MC) = tan(RAMC) / cos(ε).
    /// Public so callers (and tests) can work in the pure frame, without a `Date`.
    public static func midheaven(ramc: Double, obliquity eps: Double) -> Double {
        AstroMath.norm360(AstroMath.atan2d(AstroMath.sind(ramc),
                                           AstroMath.cosd(ramc) * AstroMath.cosd(eps)))
    }

    /// Ecliptic longitude rising on the eastern horizon.
    /// Asc = atan2( cos(RAMC), −(sin(RAMC)·cos(ε) + tan(φ)·sin(ε)) )
    /// Public so callers (and tests) can work in the pure frame, without a `Date`.
    public static func ascendant(ramc: Double, latitude phi: Double, obliquity eps: Double) -> Double {
        let y = AstroMath.cosd(ramc)
        let x = -(AstroMath.sind(ramc) * AstroMath.cosd(eps) + AstroMath.tand(phi) * AstroMath.sind(eps))
        return AstroMath.norm360(AstroMath.atan2d(y, x))
    }

    // MARK: Cusps

    /// The twelve cusps for a system, or `nil` when the system is undefined there
    /// (Placidus/Koch inside the polar circles, where a cusp would be circumpolar).
    public static func compute(at date: Date,
                               location: GeoLocation,
                               system: HouseSystem) -> HouseCusps? {
        let a = angles(at: date, location: location)
        guard let cusps = cusps(system: system,
                                ramc: a.ramc,
                                latitude: location.latitude,
                                obliquity: a.obliquity,
                                ascendant: a.ascendant,
                                midheaven: a.midheaven) else { return nil }
        return HouseCusps(system: system, cusps: cusps, angles: a)
    }

    private static func cusps(system: HouseSystem,
                              ramc: Double,
                              latitude phi: Double,
                              obliquity eps: Double,
                              ascendant asc: Double,
                              midheaven mc: Double) -> [Double]? {
        switch system {
        case .wholeSign:
            // House 1 is the whole sign the Ascendant falls in.
            let start = Double(ZodiacSign.from(longitude: asc).rawValue) * 30
            return (0..<12).map { AstroMath.norm360(start + Double($0) * 30) }

        case .equal:
            // 30° per house, measured from the Ascendant itself.
            return (0..<12).map { AstroMath.norm360(asc + Double($0) * 30) }

        case .regiomontanus:
            // Equal 30° arcs of the celestial equator, measured from the meridian.
            return quadrantCusps(mc: mc, asc: asc) { n in
                houseCircleCusp(offset: 30 * Double(n), ramc: ramc, latitude: phi, obliquity: eps)
            }

        case .campanus:
            // Equal 30° arcs of the prime vertical: tan H = cos(φ)·cot(C), C = 90 − 30n.
            return quadrantCusps(mc: mc, asc: asc) { n in
                let c = 90 - 30 * Double(n)
                let h = AstroMath.atan2d(AstroMath.cosd(phi) * AstroMath.cosd(c), AstroMath.sind(c))
                return houseCircleCusp(offset: h, ramc: ramc, latitude: phi, obliquity: eps)
            }

        case .placidus:
            // Each cusp trisects its OWN semi-arc → solve by iteration.
            return placidusCusps(ramc: ramc, latitude: phi, obliquity: eps, mc: mc, asc: asc)

        case .koch:
            return kochCusps(ramc: ramc, latitude: phi, obliquity: eps, mc: mc, asc: asc)
        }
    }

    // MARK: Quadrant helpers

    /// Ecliptic longitude where the house circle crossing the equator `offset` degrees east of
    /// the meridian meets the ecliptic. See the type doc for the derivation.
    private static func houseCircleCusp(offset h: Double,
                                        ramc: Double,
                                        latitude phi: Double,
                                        obliquity eps: Double) -> Double {
        let oa = ramc + h
        let tanPole = AstroMath.tand(phi) * AstroMath.sind(h)
        let y = AstroMath.sind(oa)
        let x = AstroMath.cosd(oa) * AstroMath.cosd(eps) - tanPole * AstroMath.sind(eps)
        return AstroMath.norm360(AstroMath.atan2d(y, x))
    }

    /// Builds all 12 cusps from a generator giving houses 10, 11, 12, 1, 2, 3 (n = 0…5),
    /// pinning cusp 10 to the MC and cusp 1 to the Asc.
    private static func quadrantCusps(mc: Double,
                                      asc: Double,
                                      _ generate: (Int) -> Double) -> [Double] {
        assemble(mc: mc, asc: asc,
                 h11: generate(1), h12: generate(2),
                 h2: generate(4), h3: generate(5))
    }

    /// A great circle cuts the ecliptic twice, so a raw `atan2` may land on the antipodal
    /// branch. Pick whichever of `v` / `v+180` falls inside the arc that starts at `start` and
    /// runs `span` degrees counterclockwise.
    private static func branch(_ v: Double, after start: Double, span: Double) -> Double {
        let a = AstroMath.norm360(v)
        let b = AstroMath.norm360(v + 180)
        let da = AstroMath.norm360(a - start)
        let db = AstroMath.norm360(b - start)
        if da > 0 && da < span { return a }
        if db > 0 && db < span { return b }
        return da <= db ? a : b        // degenerate geometry — keep the nearer one
    }

    /// Assembles all twelve cusps from the exact angles plus the four intermediate cusps,
    /// placing each intermediate in its proper quadrant and mirroring houses 4…9.
    private static func assemble(mc: Double, asc: Double,
                                 h11: Double, h12: Double,
                                 h2: Double, h3: Double) -> [Double] {
        let ic = AstroMath.norm360(mc + 180)
        let mcToAsc = AstroMath.norm360(asc - mc)     // houses 11 and 12 live in here
        let ascToIc = AstroMath.norm360(ic - asc)     // houses 2 and 3 live in here

        var out = [Double](repeating: 0, count: 12)
        func set(_ house: Int, _ value: Double) {
            let v = AstroMath.norm360(value)
            out[house - 1] = v
            let opposite = house > 6 ? house - 6 : house + 6
            out[opposite - 1] = AstroMath.norm360(v + 180)
        }
        set(10, mc)
        set(1, asc)
        set(11, branch(h11, after: mc, span: mcToAsc))
        set(12, branch(h12, after: mc, span: mcToAsc))
        set(2,  branch(h2,  after: asc, span: ascToIc))
        set(3,  branch(h3,  after: asc, span: ascToIc))
        return out
    }

    // MARK: Time-based systems (Placidus / Koch)

    /// Ecliptic longitude of the point with the given right ascension.
    private static func eclipticLongitude(rightAscension ra: Double, obliquity eps: Double) -> Double {
        AstroMath.norm360(AstroMath.atan2d(AstroMath.sind(ra),
                                           AstroMath.cosd(ra) * AstroMath.cosd(eps)))
    }

    /// Ascensional difference of an ecliptic degree: asin(tan φ · tan δ).
    /// `nil` when the point never rises or never sets at this latitude (circumpolar).
    private static func ascensionalDifference(ofLongitude lon: Double,
                                              latitude phi: Double,
                                              obliquity eps: Double) -> Double? {
        let dec = AstroMath.asind(AstroMath.sind(eps) * AstroMath.sind(lon))
        let s = AstroMath.tand(phi) * AstroMath.tand(dec)
        guard abs(s) <= 1 else { return nil }        // circumpolar → no rising/setting
        return AstroMath.asind(s)
    }

    /// **Koch** ("birthplace" houses) — closed form, no iteration.
    ///
    /// The cusps are the degrees that stood on the *Ascendant* at sidereal times spaced by
    /// thirds of the **culminating degree's** semi-diurnal arc:
    ///
    ///     cusp(10+k) = Asc( RAMC + (k−3)/3 · SA_MC ),   k = 1…5   → cusps 11, 12, 1, 2, 3
    ///     tan δ_MC = tan ε · sin(RAMC),  AD_MC = asin(tan φ · tan δ_MC),  SA_MC = 90 + AD_MC
    ///
    /// The construction is self-closing: one further third, `Asc(RAMC − SA_MC)`, is the MC
    /// itself — because the culminating degree rose exactly one semi-arc ago. That identity is
    /// what pins this as Koch (and is asserted in the tests).
    ///
    /// It also gives Koch its classical failure domain: `|tan φ · tan ε · sin RAMC| ≤ 1` can only
    /// be violated when `|φ| > 90 − ε`, i.e. inside the polar circles.
    ///
    /// (An earlier cut of this file trisected the *Ascendant's* semi-arc instead. That is a
    /// different system, and it can never fail — a point on the horizon always satisfies
    /// `|tan φ · tan δ| ≤ 1` — which contradicts Koch's known behaviour at high latitude.)
    private static func kochCusps(ramc: Double,
                                  latitude phi: Double,
                                  obliquity eps: Double,
                                  mc: Double,
                                  asc: Double) -> [Double]? {
        let sinAD = AstroMath.tand(phi) * AstroMath.tand(eps) * AstroMath.sind(ramc)
        guard abs(sinAD) <= 1 else { return nil }          // culminating degree is circumpolar
        let semiArc = 90 + AstroMath.asind(sinAD)

        func cusp(_ k: Int) -> Double {
            ascendant(ramc: ramc + Double(k - 3) / 3 * semiArc, latitude: phi, obliquity: eps)
        }
        let cusps = assemble(mc: mc, asc: asc,
                             h11: cusp(1), h12: cusp(2), h2: cusp(4), h3: cusp(5))
        return isWellOrdered(cusps) ? cusps : nil
    }

    /// Guards the time-based systems: near the polar circles the trisection can degenerate and
    /// hand back houses wider than 180°, which is worse than admitting defeat.
    private static func isWellOrdered(_ cusps: [Double]) -> Bool {
        for n in 0..<12 {
            let span = AstroMath.norm360(cusps[(n + 1) % 12] - cusps[n])
            if span <= 0 || span >= 180 { return false }
        }
        return true
    }

    /// **Placidus** — each cusp trisects its *own* semi-arc, so it has to be solved numerically.
    ///
    /// Cusps 11 and 12 sit 1/3 and 2/3 of a semi-*diurnal* arc east of the MC; cusps 2 and 3 sit
    /// 2/3 and 1/3 of a semi-*nocturnal* arc back from the IC.
    private static func placidusCusps(ramc: Double,
                                      latitude phi: Double,
                                      obliquity eps: Double,
                                      mc: Double,
                                      asc: Double) -> [Double]? {
        // Beyond the polar circle (|φ| > 90 − ε) part of the ecliptic never rises or sets, so a
        // "fraction of the time spent above the horizon" stops being meaningful: the trisection
        // degenerates and can even hand back houses wider than 180°. Both time-based systems are
        // classically undefined there, so refuse before computing anything.
        guard abs(phi) < 90 - eps else { return nil }

        // Cusp k (of 11, 12, 2, 3) satisfies  α = RAMC + 30k + c·AD(λ(α))  in right ascension.
        // (k, c) — the diurnal and nocturnal branches collapse to this one uniform relation.
        let spec: [(house: Int, k: Double, c: Double)] = [
            (11, 1, 1.0 / 3.0), (12, 2, 2.0 / 3.0),
            (2,  4, 2.0 / 3.0), (3,  5, 1.0 / 3.0),
        ]

        var solved: [Int: Double] = [10: mc, 1: asc]
        for s in spec {
            let anchor = ramc + 30 * s.k
            // Residual of the defining relation. `|c·AD| ≤ 60 < 90`, so the residual is strictly
            // negative at `anchor − 90` and strictly positive at `anchor + 90`: the root is
            // always bracketed and bisection converges unconditionally — no damping factor, no
            // convergence flag, no chance of the oscillation a fixed-point iteration hits near
            // the polar circle.
            func residual(_ alpha: Double) -> Double? {
                let lon = eclipticLongitude(rightAscension: alpha, obliquity: eps)
                guard let ad = ascensionalDifference(ofLongitude: lon, latitude: phi, obliquity: eps)
                else { return nil }
                return AstroMath.norm180(alpha - anchor - s.c * ad)
            }
            var lo = anchor - 90, hi = anchor + 90
            for _ in 0..<60 {
                let mid = (lo + hi) / 2
                guard let g = residual(mid) else { return nil }
                if g < 0 { lo = mid } else { hi = mid }
            }
            solved[s.house] = eclipticLongitude(rightAscension: (lo + hi) / 2, obliquity: eps)
        }

        let cusps = assemble(mc: mc, asc: asc,
                             h11: solved[11]!, h12: solved[12]!,
                             h2: solved[2]!, h3: solved[3]!)
        return isWellOrdered(cusps) ? cusps : nil
    }
}

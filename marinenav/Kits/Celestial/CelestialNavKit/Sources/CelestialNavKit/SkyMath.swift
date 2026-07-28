// Ported from calculators/marine-navigation/intercept.swift/InterceptKit (oracle-first harvest, 2026-07-08).
import Foundation

/// Sun & Moon positions, horizontal coordinates, rise/set/twilight and Moon illumination.
///
/// Implementation follows Paul Schlyter's compact method ("How to compute planetary
/// positions"), which reaches ~1–2 arcminute accuracy for the Sun and Moon — ample for
/// imaging planning. Pure, stateless, `Foundation` only.
public enum SkyMath {

    public enum Body: Sendable { case sun, moon }

    // MARK: Time

    /// Julian Day (UT) from a Date.
    public static func julianDay(_ date: Date) -> Double {
        date.timeIntervalSince1970 / 86400.0 + 2440587.5
    }

    /// Schlyter's day number d (epoch 2000 Jan 0.0 = JD 2451543.5).
    static func dayNumber(_ date: Date) -> Double { julianDay(date) - 2451543.5 }

    /// Greenwich Mean Sidereal Time in degrees (Meeus 12.4).
    public static func gmst(_ date: Date) -> Double {
        let jd = julianDay(date)
        let t = (jd - 2451545.0) / 36525.0
        let theta = 280.46061837
            + 360.98564736629 * (jd - 2451545.0)
            + 0.000387933 * t * t
            - t * t * t / 38_710_000.0
        return Deg.norm360(theta)
    }

    /// Local Apparent Sidereal Time (deg) — using mean obliquity is fine here.
    public static func lst(_ date: Date, longitudeEast: Double) -> Double {
        Deg.norm360(gmst(date) + longitudeEast)
    }

    // MARK: Obliquity

    static func obliquity(_ d: Double) -> Double { 23.4393 - 3.563e-7 * d }

    // MARK: Sun

    /// Sun ecliptic longitude (deg) and mean anomaly/argument used by the Moon perturbations.
    static func sunElements(_ d: Double) -> (lon: Double, meanAnomaly: Double, perihelion: Double) {
        let w = 282.9404 + 4.70935e-5 * d
        let e = 0.016709 - 1.151e-9 * d
        let M = Deg.norm360(356.0470 + 0.9856002585 * d)
        // eccentric anomaly (one Newton step is plenty for the Sun)
        var E = M + e * (180 / .pi) * Deg.sin(M) * (1 + e * Deg.cos(M))
        let x = Deg.cos(E) - e
        let y = Deg.sin(E) * (1 - e * e).squareRoot()
        let v = Deg.atan2(y, x)
        let lon = Deg.norm360(v + w)
        _ = E
        return (lon, M, w)
    }

    public static func sunPosition(_ date: Date) -> SkyPosition {
        let d = dayNumber(date)
        let (lon, _, _) = sunElements(d)
        return equatorial(fromEclLon: lon, eclLat: 0, d: d)
    }

    // MARK: Moon

    public static func moonPosition(_ date: Date) -> SkyPosition {
        let d = dayNumber(date)
        let N = 125.1228 - 0.0529538083 * d
        let i = 5.1454
        let w = 318.0634 + 0.1643573223 * d
        let a = 60.2666
        let e = 0.054900
        let M = Deg.norm360(115.3654 + 13.0649929509 * d)

        // eccentric anomaly (iterate)
        var E = M + e * (180 / .pi) * Deg.sin(M) * (1 + e * Deg.cos(M))
        for _ in 0..<3 {
            E = E - (E - e * (180 / .pi) * Deg.sin(E) - M) / (1 - e * Deg.cos(E))
        }
        let x = a * (Deg.cos(E) - e)
        let y = a * (1 - e * e).squareRoot() * Deg.sin(E)
        let r = (x * x + y * y).squareRoot()
        let v = Deg.atan2(y, x)

        // geocentric ecliptic before perturbations
        let xe = r * (Deg.cos(N) * Deg.cos(v + w) - Deg.sin(N) * Deg.sin(v + w) * Deg.cos(i))
        let ye = r * (Deg.sin(N) * Deg.cos(v + w) + Deg.cos(N) * Deg.sin(v + w) * Deg.cos(i))
        let ze = r * Deg.sin(v + w) * Deg.sin(i)
        var lon = Deg.atan2(ye, xe)
        var lat = Deg.atan2(ze, (xe * xe + ye * ye).squareRoot())

        // perturbation arguments
        let (_, Ms, ws) = sunElements(d)
        let Ls = Deg.norm360(Ms + ws)        // Sun mean longitude
        let Lm = Deg.norm360(N + w + M)      // Moon mean longitude
        let D = Deg.norm360(Lm - Ls)         // mean elongation
        let F = Deg.norm360(Lm - N)          // argument of latitude
        let Mm = M

        // longitude perturbations (deg)
        lon += -1.274 * Deg.sin(Mm - 2 * D)
        lon +=  0.658 * Deg.sin(2 * D)
        lon += -0.186 * Deg.sin(Ms)
        lon += -0.059 * Deg.sin(2 * Mm - 2 * D)
        lon += -0.057 * Deg.sin(Mm - 2 * D + Ms)
        lon +=  0.053 * Deg.sin(Mm + 2 * D)
        lon +=  0.046 * Deg.sin(2 * D - Ms)
        lon +=  0.041 * Deg.sin(Mm - Ms)
        lon += -0.035 * Deg.sin(D)
        lon += -0.031 * Deg.sin(Mm + Ms)
        lon += -0.015 * Deg.sin(2 * F - 2 * D)
        lon +=  0.011 * Deg.sin(Mm - 4 * D)

        // latitude perturbations (deg)
        lat += -0.173 * Deg.sin(F - 2 * D)
        lat += -0.055 * Deg.sin(Mm - F - 2 * D)
        lat += -0.046 * Deg.sin(Mm + F - 2 * D)
        lat +=  0.033 * Deg.sin(F + 2 * D)
        lat +=  0.017 * Deg.sin(2 * Mm + F)

        return equatorial(fromEclLon: Deg.norm360(lon), eclLat: lat, d: d)
    }

    /// Convert ecliptic lon/lat to equatorial RA/Dec at day number d.
    static func equatorial(fromEclLon lon: Double, eclLat lat: Double, d: Double) -> SkyPosition {
        let ecl = obliquity(d)
        let xe = Deg.cos(lon) * Deg.cos(lat)
        let ye = Deg.sin(lon) * Deg.cos(lat)
        let ze = Deg.sin(lat)
        let xeq = xe
        let yeq = ye * Deg.cos(ecl) - ze * Deg.sin(ecl)
        let zeq = ye * Deg.sin(ecl) + ze * Deg.cos(ecl)
        let ra = Deg.norm360(Deg.atan2(yeq, xeq))
        let dec = Deg.asin(zeq)
        return SkyPosition(rightAscension: ra, declination: dec,
                           eclipticLongitude: Deg.norm360(lon), eclipticLatitude: lat)
    }

    public static func position(of body: Body, at date: Date) -> SkyPosition {
        switch body {
        case .sun:  return sunPosition(date)
        case .moon: return moonPosition(date)
        }
    }

    // MARK: Horizontal

    /// Horizontal coordinates for equatorial position at a time & place.
    public static func horizontal(_ pos: SkyPosition, at date: Date, location: GeoLocation) -> Horizontal {
        let ha = Deg.norm180(lst(date, longitudeEast: location.longitude) - pos.rightAscension)
        let lat = location.latitude
        let alt = Deg.asin(Deg.sin(lat) * Deg.sin(pos.declination)
                           + Deg.cos(lat) * Deg.cos(pos.declination) * Deg.cos(ha))
        // azimuth from North, clockwise
        let az = Deg.norm360(Deg.atan2(Deg.sin(ha),
                             Deg.cos(ha) * Deg.sin(lat) - Deg.tan(pos.declination) * Deg.cos(lat)) + 180)
        return Horizontal(altitude: alt, azimuth: az)
    }

    /// Altitude (deg) of a body at a moment.
    public static func altitude(of body: Body, at date: Date, location: GeoLocation) -> Double {
        horizontal(position(of: body, at: date), at: date, location: location).altitude
    }

    // MARK: Rise / set / twilight

    /// Standard target altitudes (deg) for event finding.
    public enum EventAltitude {
        public static let sunUpperLimb = -0.833     // rise/set
        public static let civil = -6.0
        public static let nautical = -12.0
        public static let astronomical = -18.0
        public static let moonUpperLimb = 0.125     // ~ -0.583° refraction + ~0.7° radius ⇒ +0.125 centre
    }

    /// Find rise/set of a body crossing `targetAltitude` within [dayStart, dayStart+24h)
    /// by scanning at `stepMinutes` and refining crossings by bisection.
    public static func riseSet(of body: Body, dayStartUTC: Date, location: GeoLocation,
                               targetAltitude: Double, stepMinutes: Double = 10) -> RiseSet {
        let step = stepMinutes * 60
        let n = Int(24 * 60 / stepMinutes)
        var prevT = dayStartUTC
        var prevAlt = altitude(of: body, at: prevT, location: location) - targetAltitude
        var rise: Date?, set: Date?
        var everUp = prevAlt > 0, everDown = prevAlt <= 0
        for k in 1...n {
            let t = dayStartUTC.addingTimeInterval(Double(k) * step)
            let alt = altitude(of: body, at: t, location: location) - targetAltitude
            everUp = everUp || alt > 0
            everDown = everDown || alt <= 0
            if prevAlt <= 0 && alt > 0 { rise = refine(body, prevT, t, location, targetAltitude, rising: true) }
            if prevAlt > 0 && alt <= 0 { set = refine(body, prevT, t, location, targetAltitude, rising: false) }
            prevT = t; prevAlt = alt
        }
        let alwaysUp = everUp && !everDown
        let alwaysDown = everDown && !everUp
        return RiseSet(rise: rise, set: set, alwaysUp: alwaysUp, alwaysDown: alwaysDown)
    }

    private static func refine(_ body: Body, _ a: Date, _ b: Date, _ loc: GeoLocation,
                               _ target: Double, rising: Bool) -> Date {
        var lo = a, hi = b
        for _ in 0..<40 {
            let mid = Date(timeIntervalSince1970: (lo.timeIntervalSince1970 + hi.timeIntervalSince1970) / 2)
            let v = altitude(of: body, at: mid, location: loc) - target
            if (v > 0) == rising { hi = mid } else { lo = mid }
        }
        return Date(timeIntervalSince1970: (lo.timeIntervalSince1970 + hi.timeIntervalSince1970) / 2)
    }

    // MARK: Moon illumination

    /// Illuminated fraction of the Moon's disc [0,1] at a moment.
    public static func moonIllumination(_ date: Date) -> Double {
        let s = sunPosition(date)
        let m = moonPosition(date)
        // geocentric elongation between Moon and Sun
        let cosElong = Deg.sin(s.declination) * Deg.sin(m.declination)
            + Deg.cos(s.declination) * Deg.cos(m.declination) * Deg.cos(s.rightAscension - m.rightAscension)
        let elong = Deg.acos(cosElong)
        return (1 - Foundation.cos(Deg.rad(elong))) / 2
    }
}

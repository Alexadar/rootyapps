import Foundation

/// Sidereal time and the obliquity of the ecliptic — the equatorial-frame machinery the
/// house/angle math needs. The rest of the engine stays in ecliptic longitude and never
/// needed these.
///
/// ⚠️ Epoch trap: the position engine counts days from Paul Schlyter's epoch
/// (`Date.schlyterDay`, JD 2451543.5 = 1999-12-31.0), but every formula here is expressed
/// in Julian centuries from **J2000.0 = JD 2451545.0** — a 1.5-day difference. Always go
/// through `julianCenturies(_:)`; never reuse `schlyterDay` for this.
public enum SiderealTime {

    /// JD of the standard epoch J2000.0 (2000 January 1.5 TT).
    public static let j2000: Double = 2_451_545.0

    /// Julian centuries elapsed since J2000.0.
    public static func julianCenturies(_ date: Date) -> Double {
        (date.julianDay - j2000) / 36_525.0
    }

    /// Mean obliquity of the ecliptic ε₀, in degrees (Meeus, *Astronomical Algorithms*, 22.2):
    /// ε₀ = 23°26′21.448″ − 46.8150″·T − 0.00059″·T² + 0.001813″·T³
    ///
    /// Mean (not true) obliquity: nutation is omitted, consistent with the rest of the engine,
    /// which works to Schlyter precision (~arcminute) and applies no nutation either.
    public static func meanObliquity(at date: Date) -> Double {
        let t = julianCenturies(date)
        let seconds = 21.448 - t * (46.8150 + t * (0.00059 - t * 0.001813))
        return 23.0 + 26.0 / 60.0 + seconds / 3600.0
    }

    /// Greenwich Mean Sidereal Time in degrees [0, 360) (Meeus 12.4), valid for any instant:
    /// θ₀ = 280.46061837 + 360.98564736629·(JD − 2451545) + 0.000387933·T² − T³/38710000
    public static func greenwichMeanSiderealTime(at date: Date) -> Double {
        let jd = date.julianDay
        let t = julianCenturies(date)
        let theta = 280.46061837
            + 360.98564736629 * (jd - j2000)
            + t * t * (0.000387933 - t / 38_710_000.0)
        return AstroMath.norm360(theta)
    }

    /// Local Mean Sidereal Time in degrees [0, 360) for an observer at `longitude`
    /// (**east positive**, the sign convention used throughout this Kit).
    public static func localMeanSiderealTime(at date: Date, longitude: Double) -> Double {
        AstroMath.norm360(greenwichMeanSiderealTime(at: date) + longitude)
    }

    /// Right Ascension of the Midheaven — numerically the local sidereal time, in degrees.
    /// This is the anchor every house system is built from.
    public static func ramc(at date: Date, longitude: Double) -> Double {
        localMeanSiderealTime(at: date, longitude: longitude)
    }
}

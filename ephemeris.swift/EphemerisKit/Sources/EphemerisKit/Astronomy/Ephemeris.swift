import Foundation

/// Facade over the per-body position calculators. Pure, stateless, no dependencies.
public enum Ephemeris {
    /// Geocentric apparent ecliptic longitude (degrees, equinox of date).
    public static func longitude(of body: CelestialBody, at date: Date) -> Double {
        let d = date.schlyterDay
        let sun = SunPosition.compute(day: d)
        switch body {
        case .sun:   return sun.longitude
        case .moon:  return MoonPosition.longitude(day: d, sun: sun)
        default:     return PlanetPosition.compute(body, day: d, sun: sun).longitude
        }
    }

    /// Geocentric distance: AU for planets/Sun, Earth-radii for the Moon.
    public static func geocentricDistance(of body: CelestialBody, at date: Date) -> Double {
        let d = date.schlyterDay
        let sun = SunPosition.compute(day: d)
        switch body {
        case .sun:   return sun.r
        case .moon:  return 60.2666 // mean; distance not used in cycle logic for the Moon
        default:     return PlanetPosition.compute(body, day: d, sun: sun).distance
        }
    }

    /// Apparent motion in ecliptic longitude, degrees/day. Negative = retrograde.
    /// Sampled symmetrically over ±3h (matches the demo's finite-difference idea).
    public static func dailyMotion(of body: CelestialBody, at date: Date) -> Double {
        let h = 3.0 * 3600.0
        let before = longitude(of: body, at: date.addingTimeInterval(-h))
        let after = longitude(of: body, at: date.addingTimeInterval(h))
        let diff = AstroMath.norm180(after - before)
        return diff / (2 * h / 86_400.0)
    }

    public static func isRetrograde(_ body: CelestialBody, at date: Date) -> Bool {
        dailyMotion(of: body, at: date) < 0
    }
}

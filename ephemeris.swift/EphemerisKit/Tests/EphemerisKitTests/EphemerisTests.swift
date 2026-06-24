import Testing
import Foundation
import EphemerisKit

@Suite("Ephemeris engine")
struct EphemerisTests {

    /// The demo's sanity proof: Sun at the June 2026 solstice sits at 0° Cancer (≈90°).
    @Test func sunAtJuneSolstice() {
        let lon = Ephemeris.longitude(of: .sun, at: utc(2026, 6, 21, 12, 0))
        #expect(abs(lon - 90.14) < 0.3)
    }

    /// Sun's instantaneous motion stays in the physical range (~0.953°/day near
    /// aphelion to ~1.019°/day near perihelion); the year-average is the tropical rate.
    @Test func sunDailyMotion() {
        let m = Ephemeris.dailyMotion(of: .sun, at: utc(2026, 6, 21, 12, 0))
        #expect(m > 0.95 && m < 1.02)

        var sum = 0.0, n = 0
        var t = utc(2026, 1, 1)
        let end = utc(2026, 12, 31)
        while t < end {
            sum += Ephemeris.dailyMotion(of: .sun, at: t); n += 1
            t = t.addingTimeInterval(86_400)
        }
        #expect(abs(sum / Double(n) - 0.9856) < 0.01)   // mean ≈ tropical-year rate
    }

    /// All longitudes stay in range and the Sun is never retrograde.
    @Test func longitudesInRange() {
        let t = utc(2026, 3, 15, 0, 0)
        for body in CelestialBody.allCases {
            let lon = Ephemeris.longitude(of: body, at: t)
            #expect(lon >= 0 && lon < 360)
        }
        #expect(Ephemeris.dailyMotion(of: .sun, at: t) > 0)
        #expect(Ephemeris.dailyMotion(of: .moon, at: t) > 0)
    }

    /// Cross-check against NASA/JPL Horizons geocentric ecliptic longitude of date
    /// (ObsEcLon) for 2026-06-21 00:00 UTC. Tolerances reflect Schlyter precision.
    @Test func planetCrossCheck() {
        let t = utc(2026, 6, 21, 0, 0)
        let refs: [(CelestialBody, Double, Double)] = [
            (.sun,      89.6656, 0.25),
            (.mercury, 113.3888, 0.8),
            (.venus,   128.7542, 0.8),
            (.mars,     54.3946, 0.8),
            (.jupiter, 118.0494, 1.0),
            (.saturn,   13.6804, 1.0),
        ]
        for (body, expected, tol) in refs {
            let lon = Ephemeris.longitude(of: body, at: t)
            let diff = abs(AstroMath.norm180(lon - expected))
            #expect(diff < tol, "\(body) lon \(lon) vs Horizons \(expected) (Δ\(diff))")
        }
    }

    @Test func zodiacSignMapping() {
        #expect(ZodiacSign.from(longitude: 0) == .aries)
        #expect(ZodiacSign.from(longitude: 35) == .taurus)
        #expect(ZodiacSign.from(longitude: 90) == .cancer)
        #expect(ZodiacSign.from(longitude: 359.9) == .pisces)
        #expect(ZodiacSign.from(longitude: 360) == .aries)
    }
}

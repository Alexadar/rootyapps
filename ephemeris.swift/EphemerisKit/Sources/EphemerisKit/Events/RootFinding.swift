import Foundation

/// Shared root-finding for all event finders: detect a sign change of a scalar
/// function between daily samples, then bisect to an exact instant.
enum RootFinding {
    /// True only for a genuine zero crossing (not a ±180° wrap of a norm180 value).
    static func crossesZero(_ a: Double, _ b: Double) -> Bool {
        a != 0 && b != 0 && (a < 0) != (b < 0) && abs(a) < 90 && abs(b) < 90
    }

    /// Bisect `f` between `lo` and `hi` (assumes one sign change in between).
    static func refine(_ lo: Date, _ hi: Date, _ f: (Date) -> Double) -> Date {
        var a = lo.timeIntervalSince1970, b = hi.timeIntervalSince1970
        var fa = f(lo)
        for _ in 0..<48 {
            let m = (a + b) / 2
            let fm = f(Date(timeIntervalSince1970: m))
            if (fa < 0) != (fm < 0) { b = m } else { a = m; fa = fm }
        }
        return Date(timeIntervalSince1970: (a + b) / 2)
    }

    /// Signed longitude difference body − reference, in (-180, 180]. Zero at conjunction.
    static func signedSeparation(_ a: CelestialBody, _ b: CelestialBody, at t: Date) -> Double {
        AstroMath.norm180(Ephemeris.longitude(of: a, at: t) - Ephemeris.longitude(of: b, at: t))
    }
}

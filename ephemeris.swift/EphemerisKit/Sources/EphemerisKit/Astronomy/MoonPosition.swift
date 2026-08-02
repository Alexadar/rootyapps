import Foundation

/// Geocentric ecliptic longitude of the Moon (Schlyter, with the 12 main
/// longitude perturbations — ~2 arcmin accuracy).
enum MoonPosition {
    static func longitude(day d: Double, sun: SunPosition.Result) -> Double {
        let N = 125.1228 - 0.0529538083 * d
        let i = 5.1454
        let w = 318.0634 + 0.1643573223 * d
        let e = 0.054900
        let M = AstroMath.norm360(115.3654 + 13.0649929509 * d)

        var E = M + AstroMath.deg * e * AstroMath.sind(M) * (1 + e * AstroMath.cosd(M))
        for _ in 0..<5 {
            E = E - (E - AstroMath.deg * e * AstroMath.sind(E) - M) / (1 - e * AstroMath.cosd(E))
        }

        let xv = AstroMath.cosd(E) - e
        let yv = sqrt(1 - e * e) * AstroMath.sind(E)
        let v = AstroMath.atan2d(yv, xv)
        let r = sqrt(xv * xv + yv * yv)

        // Heliocentric→geocentric here is identity (Moon elements are geocentric).
        let xh = r * (AstroMath.cosd(N) * AstroMath.cosd(v + w) - AstroMath.sind(N) * AstroMath.sind(v + w) * AstroMath.cosd(i))
        let yh = r * (AstroMath.sind(N) * AstroMath.cosd(v + w) + AstroMath.cosd(N) * AstroMath.sind(v + w) * AstroMath.cosd(i))

        var lon = AstroMath.atan2d(yh, xh)

        // Perturbation arguments.
        let Ms = sun.meanAnomaly
        let Ls = sun.meanAnomaly + sun.perihelion       // Sun mean longitude
        let Lm = M + w + N                              // Moon mean longitude
        let D = Lm - Ls                                 // mean elongation
        let F = Lm - N                                  // argument of latitude
        let Mm = M

        lon += -1.274 * AstroMath.sind(Mm - 2 * D)
        lon +=  0.658 * AstroMath.sind(2 * D)
        lon += -0.186 * AstroMath.sind(Ms)
        lon += -0.059 * AstroMath.sind(2 * Mm - 2 * D)
        lon += -0.057 * AstroMath.sind(Mm - 2 * D + Ms)
        lon +=  0.053 * AstroMath.sind(Mm + 2 * D)
        lon +=  0.046 * AstroMath.sind(2 * D - Ms)
        lon +=  0.041 * AstroMath.sind(Mm - Ms)
        lon += -0.035 * AstroMath.sind(D)
        lon += -0.031 * AstroMath.sind(Mm + Ms)
        lon += -0.015 * AstroMath.sind(2 * F - 2 * D)
        lon +=  0.011 * AstroMath.sind(Mm - 4 * D)

        return AstroMath.norm360(lon)
    }
}

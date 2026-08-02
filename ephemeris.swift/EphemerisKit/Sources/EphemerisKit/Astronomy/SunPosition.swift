import Foundation

/// Geocentric apparent position of the Sun (Schlyter, equinox of date).
enum SunPosition {
    struct Result {
        let longitude: Double   // ecliptic longitude, degrees [0,360)
        let r: Double           // distance, AU
        let meanAnomaly: Double // M, degrees — reused by planet perturbations
        let perihelion: Double  // w, degrees
        let x: Double           // geocentric rectangular (Sun) in ecliptic plane
        let y: Double
    }

    static func compute(day d: Double) -> Result {
        let M = AstroMath.norm360(356.0470 + 0.9856002585 * d)
        let w = 282.9404 + 4.70935e-5 * d
        let e = 0.016709 - 1.151e-9 * d

        // Eccentric anomaly (one Newton step is plenty for the Sun's small e).
        var E = M + AstroMath.deg * e * AstroMath.sind(M) * (1 + e * AstroMath.cosd(M))
        E = E - (E - AstroMath.deg * e * AstroMath.sind(E) - M) / (1 - e * AstroMath.cosd(E))

        let xv = AstroMath.cosd(E) - e
        let yv = sqrt(1 - e * e) * AstroMath.sind(E)
        let v = AstroMath.atan2d(yv, xv)
        let r = sqrt(xv * xv + yv * yv)

        let lon = AstroMath.norm360(v + w)
        return Result(longitude: lon, r: r, meanAnomaly: M, perihelion: w,
                      x: r * AstroMath.cosd(lon), y: r * AstroMath.sind(lon))
    }
}

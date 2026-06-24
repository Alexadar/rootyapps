import Foundation

/// Geocentric ecliptic longitude + Earth distance of a planet (Schlyter,
/// equinox of date, with the main outer-planet perturbations). Pluto via
/// Schlyter's special series (valid ~1800–2099).
enum PlanetPosition {
    struct Result {
        let longitude: Double   // geocentric ecliptic longitude, degrees [0,360)
        let distance: Double    // geocentric distance (AU)
    }

    /// Time-varying Keplerian elements (degrees / AU). `N i w` are angles, `a` AU, `e` unitless, `M` angle.
    private struct Elements { let N, i, w, a, e, M: Double }

    private static func elements(_ body: CelestialBody, _ d: Double) -> Elements {
        switch body {
        case .mercury:
            return Elements(N: 48.3313 + 3.24587e-5 * d, i: 7.0047 + 5.00e-8 * d,
                            w: 29.1241 + 1.01444e-5 * d, a: 0.387098,
                            e: 0.205635 + 5.59e-10 * d, M: 168.6562 + 4.0923344368 * d)
        case .venus:
            return Elements(N: 76.6799 + 2.46590e-5 * d, i: 3.3946 + 2.75e-8 * d,
                            w: 54.8910 + 1.38374e-5 * d, a: 0.723330,
                            e: 0.006773 - 1.302e-9 * d, M: 48.0052 + 1.6021302244 * d)
        case .mars:
            return Elements(N: 49.5574 + 2.11081e-5 * d, i: 1.8497 - 1.78e-8 * d,
                            w: 286.5016 + 2.92961e-5 * d, a: 1.523688,
                            e: 0.093405 + 2.516e-9 * d, M: 18.6021 + 0.5240207766 * d)
        case .jupiter:
            return Elements(N: 100.4542 + 2.76854e-5 * d, i: 1.3030 - 1.557e-7 * d,
                            w: 273.8777 + 1.64505e-5 * d, a: 5.20256,
                            e: 0.048498 + 4.469e-9 * d, M: 19.8950 + 0.0830853001 * d)
        case .saturn:
            return Elements(N: 113.6634 + 2.38980e-5 * d, i: 2.4886 - 1.081e-7 * d,
                            w: 339.3939 + 2.97661e-5 * d, a: 9.55475,
                            e: 0.055546 - 9.499e-9 * d, M: 316.9670 + 0.0334442282 * d)
        case .uranus:
            return Elements(N: 74.0005 + 1.3978e-5 * d, i: 0.7733 + 1.9e-8 * d,
                            w: 96.6612 + 3.0565e-5 * d, a: 19.18171 - 1.55e-8 * d,
                            e: 0.047318 + 7.45e-9 * d, M: 142.5905 + 0.011725806 * d)
        case .neptune:
            return Elements(N: 131.7806 + 3.0173e-5 * d, i: 1.7700 - 2.55e-7 * d,
                            w: 272.8461 - 6.027e-6 * d, a: 30.05826 + 3.313e-8 * d,
                            e: 0.008606 + 2.15e-9 * d, M: 260.2471 + 0.005995147 * d)
        default:
            fatalError("PlanetPosition.elements called for non-planet \(body)")
        }
    }

    static func compute(_ body: CelestialBody, day d: Double, sun: SunPosition.Result) -> Result {
        if body == .pluto { return pluto(day: d, sun: sun) }

        let el = elements(body, d)
        let e = el.e
        let M = AstroMath.norm360(el.M)

        var E = M + AstroMath.deg * e * AstroMath.sind(M) * (1 + e * AstroMath.cosd(M))
        for _ in 0..<5 {
            E = E - (E - AstroMath.deg * e * AstroMath.sind(E) - M) / (1 - e * AstroMath.cosd(E))
        }

        let xv = el.a * (AstroMath.cosd(E) - e)
        let yv = el.a * sqrt(1 - e * e) * AstroMath.sind(E)
        let v = AstroMath.atan2d(yv, xv)
        let r = sqrt(xv * xv + yv * yv)

        // Heliocentric ecliptic rectangular.
        var xh = r * (AstroMath.cosd(el.N) * AstroMath.cosd(v + el.w) - AstroMath.sind(el.N) * AstroMath.sind(v + el.w) * AstroMath.cosd(el.i))
        var yh = r * (AstroMath.sind(el.N) * AstroMath.cosd(v + el.w) + AstroMath.cosd(el.N) * AstroMath.sind(v + el.w) * AstroMath.cosd(el.i))
        var zh = r * AstroMath.sind(v + el.w) * AstroMath.sind(el.i)

        var lonecl = AstroMath.atan2d(yh, xh)
        var latecl = AstroMath.atan2d(zh, sqrt(xh * xh + yh * yh))

        // Major perturbations for the giant planets.
        let (dLon, dLat) = perturbations(body, d)
        if dLon != 0 || dLat != 0 {
            lonecl += dLon
            latecl += dLat
            xh = r * AstroMath.cosd(lonecl) * AstroMath.cosd(latecl)
            yh = r * AstroMath.sind(lonecl) * AstroMath.cosd(latecl)
            zh = r * AstroMath.sind(latecl)
        }

        // Geocentric: add Sun's geocentric rectangular position.
        let xg = xh + sun.x
        let yg = yh + sun.y
        let zg = zh
        let lon = AstroMath.norm360(AstroMath.atan2d(yg, xg))
        let dist = sqrt(xg * xg + yg * yg + zg * zg)
        return Result(longitude: lon, distance: dist)
    }

    private static func perturbations(_ body: CelestialBody, _ d: Double) -> (lon: Double, lat: Double) {
        let Mj = 19.8950 + 0.0830853001 * d
        let Ms = 316.9670 + 0.0334442282 * d
        let Mu = 142.5905 + 0.011725806 * d
        switch body {
        case .jupiter:
            var l = 0.0
            l += -0.332 * AstroMath.sind(2 * Mj - 5 * Ms - 67.6)
            l += -0.056 * AstroMath.sind(2 * Mj - 2 * Ms + 21)
            l +=  0.042 * AstroMath.sind(3 * Mj - 5 * Ms + 21)
            l += -0.036 * AstroMath.sind(Mj - 2 * Ms)
            l +=  0.022 * AstroMath.cosd(Mj - Ms)
            l +=  0.023 * AstroMath.sind(2 * Mj - 3 * Ms + 52)
            l += -0.016 * AstroMath.sind(Mj - 5 * Ms - 69)
            return (l, 0)
        case .saturn:
            var l = 0.0, b = 0.0
            l +=  0.812 * AstroMath.sind(2 * Mj - 5 * Ms - 67.6)
            l += -0.229 * AstroMath.cosd(2 * Mj - 4 * Ms - 2)
            l +=  0.119 * AstroMath.sind(Mj - 2 * Ms - 3)
            l +=  0.046 * AstroMath.sind(2 * Mj - 6 * Ms - 69)
            l +=  0.014 * AstroMath.sind(Mj - 3 * Ms + 32)
            b += -0.020 * AstroMath.cosd(2 * Mj - 4 * Ms - 2)
            b +=  0.018 * AstroMath.sind(2 * Mj - 6 * Ms - 49)
            return (l, b)
        case .uranus:
            var l = 0.0
            l +=  0.040 * AstroMath.sind(Ms - 2 * Mu + 6)
            l +=  0.035 * AstroMath.sind(Ms - 3 * Mu + 33)
            l += -0.015 * AstroMath.sind(Mj - Mu + 20)
            return (l, 0)
        default:
            return (0, 0)
        }
    }

    /// Pluto — Schlyter's heliocentric series, then geocentric.
    private static func pluto(day d: Double, sun: SunPosition.Result) -> Result {
        let S = 50.03 + 0.033459652 * d
        let P = 238.95 + 0.003968789 * d

        var lonecl = 238.9508 + 0.00400703 * d
        lonecl += -19.799 * AstroMath.sind(P)     + 19.848 * AstroMath.cosd(P)
        lonecl +=   0.897 * AstroMath.sind(2 * P)  -  4.956 * AstroMath.cosd(2 * P)
        lonecl +=   0.610 * AstroMath.sind(3 * P)  +  1.211 * AstroMath.cosd(3 * P)
        lonecl += -0.341 * AstroMath.sind(4 * P)   -  0.190 * AstroMath.cosd(4 * P)
        lonecl +=  0.128 * AstroMath.sind(5 * P)   -  0.034 * AstroMath.cosd(5 * P)
        lonecl += -0.038 * AstroMath.sind(6 * P)   +  0.031 * AstroMath.cosd(6 * P)
        lonecl +=  0.020 * AstroMath.sind(S - P)   -  0.010 * AstroMath.cosd(S - P)

        var latecl = -3.9082
        latecl += -5.453 * AstroMath.sind(P)       - 14.975 * AstroMath.cosd(P)
        latecl +=  3.527 * AstroMath.sind(2 * P)   +  1.673 * AstroMath.cosd(2 * P)
        latecl += -1.051 * AstroMath.sind(3 * P)   +  0.328 * AstroMath.cosd(3 * P)
        latecl +=  0.179 * AstroMath.sind(4 * P)   -  0.292 * AstroMath.cosd(4 * P)
        latecl +=  0.019 * AstroMath.sind(5 * P)   +  0.100 * AstroMath.cosd(5 * P)
        latecl += -0.031 * AstroMath.sind(6 * P)   -  0.026 * AstroMath.cosd(6 * P)
        latecl +=  0.011 * AstroMath.cosd(S - P)

        var r = 40.72
        r += 6.68 * AstroMath.sind(P)  + 6.90 * AstroMath.cosd(P)
        r += -1.18 * AstroMath.sind(2 * P) - 0.03 * AstroMath.cosd(2 * P)
        r +=  0.15 * AstroMath.sind(3 * P) - 0.14 * AstroMath.cosd(3 * P)

        let xh = r * AstroMath.cosd(lonecl) * AstroMath.cosd(latecl)
        let yh = r * AstroMath.sind(lonecl) * AstroMath.cosd(latecl)
        let zh = r * AstroMath.sind(latecl)

        let xg = xh + sun.x, yg = yh + sun.y, zg = zh
        let lon = AstroMath.norm360(AstroMath.atan2d(yg, xg))
        let dist = sqrt(xg * xg + yg * yg + zg * zg)
        return Result(longitude: lon, distance: dist)
    }
}

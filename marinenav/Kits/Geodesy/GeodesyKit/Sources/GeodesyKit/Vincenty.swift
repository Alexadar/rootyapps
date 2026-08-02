// Ported from calculators/marine-navigation/geodesic.swift/GeodesyKit (oracle-first harvest, 2026-07-08).
import Foundation

/// Vincenty inverse/direct geodesics on the WGS84 ellipsoid.
///
/// Accurate to ~mm for the vast majority of geodesics, but — by design and well-documented —
/// it FAILS TO CONVERGE for near-antipodal endpoints. That case is reported, not hidden
/// (see the GeodTest oracle). A Karney upgrade for sub-mm-everywhere is tracked in NOTES.md.
///
/// MODEL CAVEAT: this is the geodesic on the WGS-84 **ellipsoid** — the shortest path over a
/// mathematical figure of the Earth. It is not a rhumb-line (constant-bearing) course, does not
/// account for terrain or sea state, and takes no view on whether the path crosses land.
public enum Vincenty {
    public static let a = 6_378_137.0
    public static let f = 1 / 298.257223563
    public static var b: Double { a * (1 - f) }

    public struct Inverse: Sendable, Equatable {
        public var distanceM: Double     // s12
        public var azimuth1Deg: Double    // forward azimuth at point 1
        public var azimuth2Deg: Double    // forward azimuth at point 2
        public var converged: Bool
    }

    static func rad(_ d: Double) -> Double { d * .pi / 180 }
    static func deg(_ r: Double) -> Double { r * 180 / .pi }

    /// Inverse geodesic: distance + azimuths between two lat/long points (degrees).
    public static func inverse(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Inverse {
        let L = rad(lon2 - lon1)
        let U1 = atan((1 - f) * tan(rad(lat1)))
        let U2 = atan((1 - f) * tan(rad(lat2)))
        let sinU1 = sin(U1), cosU1 = cos(U1), sinU2 = sin(U2), cosU2 = cos(U2)

        var lambda = L
        var sinSigma = 0.0, cosSigma = 0.0, sigma = 0.0, cosSqAlpha = 0.0, cos2SigmaM = 0.0
        var converged = false
        for _ in 0..<200 {
            let sinL = sin(lambda), cosL = cos(lambda)
            sinSigma = ((cosU2 * sinL) * (cosU2 * sinL)
                        + (cosU1 * sinU2 - sinU1 * cosU2 * cosL) * (cosU1 * sinU2 - sinU1 * cosU2 * cosL)).squareRoot()
            if sinSigma == 0 { return Inverse(distanceM: 0, azimuth1Deg: 0, azimuth2Deg: 0, converged: true) } // coincident
            cosSigma = sinU1 * sinU2 + cosU1 * cosU2 * cosL
            sigma = atan2(sinSigma, cosSigma)
            let sinAlpha = cosU1 * cosU2 * sinL / sinSigma
            cosSqAlpha = 1 - sinAlpha * sinAlpha
            cos2SigmaM = cosSqAlpha == 0 ? 0 : cosSigma - 2 * sinU1 * sinU2 / cosSqAlpha   // equatorial → 0
            let C = f / 16 * cosSqAlpha * (4 + f * (4 - 3 * cosSqAlpha))
            let lambdaPrev = lambda
            lambda = L + (1 - C) * f * sinAlpha
                * (sigma + C * sinSigma * (cos2SigmaM + C * cosSigma * (-1 + 2 * cos2SigmaM * cos2SigmaM)))
            if abs(lambda - lambdaPrev) < 1e-12 { converged = true; break }
        }
        guard converged else {
            return Inverse(distanceM: .nan, azimuth1Deg: .nan, azimuth2Deg: .nan, converged: false)
        }
        let uSq = cosSqAlpha * (a * a - b * b) / (b * b)
        let A = 1 + uSq / 16384 * (4096 + uSq * (-768 + uSq * (320 - 175 * uSq)))
        let B = uSq / 1024 * (256 + uSq * (-128 + uSq * (74 - 47 * uSq)))
        let deltaSigma = B * sinSigma * (cos2SigmaM + B / 4
            * (cosSigma * (-1 + 2 * cos2SigmaM * cos2SigmaM)
               - B / 6 * cos2SigmaM * (-3 + 4 * sinSigma * sinSigma) * (-3 + 4 * cos2SigmaM * cos2SigmaM)))
        let s = b * A * (sigma - deltaSigma)

        let sinL = sin(lambda), cosL = cos(lambda)
        let a1 = atan2(cosU2 * sinL, cosU1 * sinU2 - sinU1 * cosU2 * cosL)
        let a2 = atan2(cosU1 * sinL, -sinU1 * cosU2 + cosU1 * sinU2 * cosL)
        func norm(_ d: Double) -> Double { let m = d.truncatingRemainder(dividingBy: 360); return m < 0 ? m + 360 : m }
        return Inverse(distanceM: s, azimuth1Deg: norm(deg(a1)), azimuth2Deg: norm(deg(a2)), converged: true)
    }
}

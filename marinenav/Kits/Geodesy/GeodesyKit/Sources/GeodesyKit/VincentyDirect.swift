import Foundation

extension Vincenty {

    /// Result of the direct geodesic problem.
    public struct Direct: Sendable, Equatable {
        /// Latitude of the destination, degrees.
        public var lat2Deg: Double
        /// Longitude of the destination, degrees, normalised to (−180, 180].
        public var lon2Deg: Double
        /// Forward azimuth at the destination, degrees, in [0, 360).
        public var azimuth2Deg: Double
        public var converged: Bool
    }

    /// Direct geodesic: given a start point, an initial azimuth and a distance
    /// along the geodesic, find the destination and the azimuth there.
    ///
    /// Source: Vincenty, "Direct and Inverse Solutions of Geodesics on the
    /// Ellipsoid with Application of Nested Equations", *Survey Review* XXIII/176
    /// (1975). WGS-84 ellipsoid.
    ///
    /// Pure, stateless. Unlike the inverse problem, the direct problem has no
    /// near-antipodal convergence failure — it converges everywhere — but the
    /// `converged` flag is still reported rather than assumed.
    public static func direct(lat1: Double, lon1: Double,
                              azimuth1Deg: Double, distanceM s: Double) -> Direct {
        precondition(s.isFinite, "distance must be finite")

        let alpha1 = rad(azimuth1Deg)
        let U1 = atan((1 - f) * tan(rad(lat1)))
        let sinU1 = sin(U1), cosU1 = cos(U1)
        let sinAlpha1 = sin(alpha1), cosAlpha1 = cos(alpha1)

        let sigma1 = atan2(tanU1(lat1), cosAlpha1)
        let sinAlpha = cosU1 * sinAlpha1
        let cosSqAlpha = 1 - sinAlpha * sinAlpha
        let uSq = cosSqAlpha * (a * a - b * b) / (b * b)
        let A = 1 + uSq / 16384 * (4096 + uSq * (-768 + uSq * (320 - 175 * uSq)))
        let B = uSq / 1024 * (256 + uSq * (-128 + uSq * (74 - 47 * uSq)))

        var sigma = s / (b * A)
        var cos2SigmaM = 0.0, sinSigma = 0.0, cosSigma = 0.0, deltaSigma = 0.0
        var converged = false
        for _ in 0..<200 {
            cos2SigmaM = cos(2 * sigma1 + sigma)
            sinSigma = sin(sigma)
            cosSigma = cos(sigma)
            deltaSigma = B * sinSigma * (cos2SigmaM + B / 4
                * (cosSigma * (-1 + 2 * cos2SigmaM * cos2SigmaM)
                   - B / 6 * cos2SigmaM * (-3 + 4 * sinSigma * sinSigma)
                     * (-3 + 4 * cos2SigmaM * cos2SigmaM)))
            let previous = sigma
            sigma = s / (b * A) + deltaSigma
            if abs(sigma - previous) < 1e-12 { converged = true; break }
        }
        guard converged else {
            return Direct(lat2Deg: .nan, lon2Deg: .nan, azimuth2Deg: .nan, converged: false)
        }

        let tmp = sinU1 * sinSigma - cosU1 * cosSigma * cosAlpha1
        let lat2 = atan2(sinU1 * cosSigma + cosU1 * sinSigma * cosAlpha1,
                         (1 - f) * (sinAlpha * sinAlpha + tmp * tmp).squareRoot())
        let lambda = atan2(sinSigma * sinAlpha1,
                           cosU1 * cosSigma - sinU1 * sinSigma * cosAlpha1)
        let C = f / 16 * cosSqAlpha * (4 + f * (4 - 3 * cosSqAlpha))
        let L = lambda - (1 - C) * f * sinAlpha
            * (sigma + C * sinSigma * (cos2SigmaM + C * cosSigma
               * (-1 + 2 * cos2SigmaM * cos2SigmaM)))
        let alpha2 = atan2(sinAlpha, -tmp)

        return Direct(lat2Deg: deg(lat2),
                      lon2Deg: normalizeSigned(lon1 + deg(L)),
                      azimuth2Deg: normalize(deg(alpha2)),
                      converged: true)
    }

    @inline(__always)
    private static func tanU1(_ lat1: Double) -> Double { (1 - f) * tan(rad(lat1)) }

    /// Wrap to [0, 360).
    static func normalize(_ d: Double) -> Double {
        let m = d.truncatingRemainder(dividingBy: 360)
        return m < 0 ? m + 360 : m
    }

    /// Wrap to (−180, 180].
    static func normalizeSigned(_ d: Double) -> Double {
        let m = normalize(d)
        return m > 180 ? m - 360 : m
    }
}

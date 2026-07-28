// Ported from calculators/marine-navigation/deviation.swift/GeomagKit (oracle-first harvest, 2026-07-08).
import Foundation

/// Geomagnetic field from a World Magnetic Model coefficient set (WMM.COF): degree/order-12
/// spherical-harmonic synthesis. Pure, stateless once loaded.
///
/// MODEL CAVEAT: the WMM describes only the **main (core) field** plus its linear secular
/// variation. It does not model crustal anomalies, ionospheric or magnetospheric contributions,
/// or magnetic storms — local declination can depart from it by degrees over magnetised rock,
/// and the model degrades toward the end of its 5-year epoch. A compass on a steel vessel is
/// further affected by deviation, which is a property of the vessel, not of this model.
public struct GeomagField: Sendable {
    public var x, y, z, h, f, declinationDeg, inclinationDeg: Double
}

public struct WMM {
    public let epoch: Double
    private var g = [[Double]](repeating: [Double](repeating: 0, count: 13), count: 13)
    private var h = [[Double]](repeating: [Double](repeating: 0, count: 13), count: 13)
    private var dg = [[Double]](repeating: [Double](repeating: 0, count: 13), count: 13)
    private var dh = [[Double]](repeating: [Double](repeating: 0, count: 13), count: 13)

    private static let N = 12
    private static let aRef = 6371.2          // geomagnetic reference radius (km)
    private static let aWGS = 6378.137
    private static let fWGS = 1 / 298.257223563

    /// Parse a WMM.COF file.
    public init?(cof: String) {
        let lines = cof.split(whereSeparator: \.isNewline).map(String.init)
        guard let header = lines.first,
              let ep = Double(header.split(whereSeparator: \.isWhitespace).first ?? "") else { return nil }
        epoch = ep
        for line in lines.dropFirst() {
            let t = line.split(whereSeparator: \.isWhitespace).compactMap { Double($0) }
            guard t.count >= 6 else { continue }
            let n = Int(t[0]), m = Int(t[1])
            guard n >= 1, n <= 12, m >= 0, m <= n else { continue }   // skips the 9999… terminator
            g[n][m] = t[2]; h[n][m] = t[3]; dg[n][m] = t[4]; dh[n][m] = t[5]
        }
    }

    private static func schmidt(_ n: Int, _ m: Int) -> Double {
        if m == 0 { return 1 }
        var prod = 1.0
        for k in (n - m + 1)...(n + m) { prod *= Double(k) }
        return (2.0 / prod).squareRoot()
    }

    /// Field at a time (decimal year), altitude (km), and geodetic lat/long (deg).
    public func field(decimalYear t: Double, altitudeKm alt: Double, latDeg: Double, lonDeg: Double) -> GeomagField {
        let dt = t - epoch
        let d2r = Double.pi / 180
        let phi = latDeg * d2r, lam = lonDeg * d2r
        let sp = sin(phi), cp = cos(phi)
        let e2 = Self.fWGS * (2 - Self.fWGS)
        let Rc = Self.aWGS / (1 - e2 * sp * sp).squareRoot()
        let pxy = (Rc + alt) * cp
        let zc = (Rc * (1 - e2) + alt) * sp
        let r = (pxy * pxy + zc * zc).squareRoot()
        let phic = atan2(zc, pxy)                 // geocentric latitude
        let sinTheta = cos(phic)                   // sin(colatitude)
        let cosTheta = sin(phic)                   // cos(colatitude)

        // Unnormalized associated Legendre (Ferrers, no Condon-Shortley) in colatitude, + dP/dθ.
        let N = Self.N
        var Pu = [[Double]](repeating: [Double](repeating: 0, count: 13), count: 13)
        var dPu = Pu
        Pu[0][0] = 1
        for m in 0...N {
            if m > 0 {
                Pu[m][m] = Double(2 * m - 1) * sinTheta * Pu[m - 1][m - 1]
                dPu[m][m] = Double(2 * m - 1) * (sinTheta * dPu[m - 1][m - 1] + cosTheta * Pu[m - 1][m - 1])
            }
            if m < N {
                Pu[m + 1][m] = Double(2 * m + 1) * cosTheta * Pu[m][m]
                dPu[m + 1][m] = Double(2 * m + 1) * (cosTheta * dPu[m][m] - sinTheta * Pu[m][m])
                if m + 2 <= N {
                    for n in (m + 2)...N {
                        let f1 = Double(2 * n - 1), f2 = Double(n + m - 1), f3 = Double(n - m)
                        Pu[n][m] = (f1 * cosTheta * Pu[n - 1][m] - f2 * Pu[n - 2][m]) / f3
                        dPu[n][m] = (f1 * (cosTheta * dPu[n - 1][m] - sinTheta * Pu[n - 1][m]) - f2 * dPu[n - 2][m]) / f3
                    }
                }
            }
        }

        let ar = Self.aRef / r
        var bt = 0.0, bp = 0.0, br = 0.0
        for n in 1...N {
            let arn = pow(ar, Double(n + 2))
            for m in 0...n {
                let s = Self.schmidt(n, m)
                let P = Pu[n][m] * s, dP = dPu[n][m] * s
                let gt = g[n][m] + dt * dg[n][m]
                let ht = h[n][m] + dt * dh[n][m]
                let cml = cos(Double(m) * lam), sml = sin(Double(m) * lam)
                let gcs = gt * cml + ht * sml
                let gsc = gt * sml - ht * cml
                bt += arn * gcs * dP
                bp += arn * Double(m) * gsc * P
                br += Double(n + 1) * arn * gcs * P
            }
        }
        bp /= sinTheta

        // Geocentric field components, then rotate to geodetic.
        // X' (geocentric north) = +B_θ series (dP/dθ with θ = colatitude); Z' (down) = −B_r series.
        let Xc = bt, Yc = bp, Zc = -br
        // Rotate geocentric (Xc,Zc) → geodetic by the geocentric-minus-geodetic latitude.
        let psi = phic - phi
        let X = Xc * cos(psi) - Zc * sin(psi)
        let Z = Xc * sin(psi) + Zc * cos(psi)
        let Y = Yc
        let H = (X * X + Y * Y).squareRoot()
        let F = (H * H + Z * Z).squareRoot()
        return GeomagField(x: X, y: Y, z: Z, h: H, f: F,
                           declinationDeg: atan2(Y, X) / d2r, inclinationDeg: atan2(Z, H) / d2r)
    }
}

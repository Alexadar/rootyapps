import Foundation

/// Nodal (18.6-year) corrections: the angles `I, ξ, ν, ν′, 2ν″` and the node
/// factors `f`. Pure, stateless.
///
/// Source: Schureman, USC&GS Special Publication No. 98 (1958) —
/// Table 6 (pp. 173+) tabulates `I, ν, ξ, ν′, 2ν″` for each degree of N and
/// carries the sign rule: **"Positive when N is between 0° and 180°; negative
/// when N is between 180° and 360°"**. The closed forms below reproduce that
/// table to 0.006° (the table itself is printed to 0.01°).
///
/// MODEL CAVEAT: `f` and `u` model the 18.6-year nodal modulation *by equilibrium
/// theory*. Real f/u can be altered by local hydrodynamics (Parker, NOAA Sp. Pub.
/// NOS CO-OPS 3, §2.3.4). Note also that NOAA's operational predictions hold f and
/// u **constant across each calendar year** (midyear value); this type evaluates
/// them continuously, which Parker documents as the more accurate variant.
public struct Nodal: Sendable, Equatable {

    /// Obliquity of the ecliptic, epoch 1900 (Schureman Table 1, p. 163).
    public static let obliquityDeg = 23.452
    /// Inclination of the moon's orbit to the ecliptic (Schureman Table 1).
    public static let lunarInclinationDeg = 5.145

    /// Inclination of the moon's orbit to the Earth's equator.
    public let inclinationDeg: Double
    /// Longitude in the moon's orbit of the lunar intersection.
    public let xiDeg: Double
    /// Right ascension of the lunar intersection.
    public let nuDeg: Double
    /// ν′ — term in the K₁ argument (Schureman eq. 224).
    public let nuPrimeDeg: Double
    /// 2ν″ — term in the K₂ argument (Schureman eq. 232). Holds *twice* ν″.
    public let twoNuDoublePrimeDeg: Double
    /// Q — term in the M₁ argument (Schureman eq. 202).
    public let qDeg: Double
    /// Qu = P − Q (Schureman eq. 204), where P = p − ξ.
    public let quDeg: Double
    /// Qa — factor in the M₁ amplitude (Schureman eq. 197). Used as **1/Qa**.
    public let qa: Double
    /// Ru — term in the L₂ argument (Schureman eq. 214).
    public let ruDeg: Double
    /// Ra — factor in the L₂ amplitude (Schureman eq. 213). Used as **1/Ra**.
    public let ra: Double

    /// Compute the nodal angles for the moon's node `nDeg` and lunar perigee `pDeg`.
    public init(nodeDeg nDeg: Double, perigeeDeg pDeg: Double) {
        let w = Angle.radians(Nodal.obliquityDeg)
        let i = Angle.radians(Nodal.lunarInclinationDeg)
        let n = Angle.radians(nDeg)

        let cosI = cos(i) * cos(w) - sin(i) * sin(w) * cos(n)
        let I = acos(cosI)

        // Schureman: xi = N − atan(1.01883·tan(N/2)) − atan(0.64412·tan(N/2)),
        // written here with the exact half-angle ratios rather than the rounded
        // constants. The branch shifts cancel between the two arctangents.
        let at1 = atan(cos((w - i) / 2) / cos((w + i) / 2) * tan(n / 2))
        let at2 = atan(sin((w - i) / 2) / sin((w + i) / 2) * tan(n / 2))
        let xiRaw = n - at1 - at2
        let xi = atan2(sin(xiRaw), cos(xiRaw))          // wrap to (−π, π]
        let nu = at1 - at2

        let nuP = atan2(sin(2 * I) * sin(nu), sin(2 * I) * cos(nu) + 0.3347)
        let nuPP2 = atan2(pow(sin(I), 2) * sin(2 * nu),
                          pow(sin(I), 2) * cos(2 * nu) + 0.0727)

        // P = mean longitude of lunar perigee reckoned from the lunar intersection.
        let P = Angle.radians(pDeg) - xi
        let q = atan2((5 * cos(I) - 1) * sin(P), (7 * cos(I) + 1) * cos(P))
        let qa = pow(2.310 + 1.435 * cos(2 * P), -0.5)
        let ru = atan2(sin(2 * P), pow(tan(I / 2), -2) / 6.0 - cos(2 * P))
        let ra = pow(1.0 - 12 * pow(tan(I / 2), 2) * cos(2 * P) + 36 * pow(tan(I / 2), 4), -0.5)

        self.inclinationDeg = Angle.degrees(I)
        self.xiDeg = Angle.degrees(xi)
        self.nuDeg = Angle.degrees(nu)
        self.nuPrimeDeg = Angle.degrees(nuP)
        self.twoNuDoublePrimeDeg = Angle.degrees(nuPP2)
        self.qDeg = Angle.degrees(q)
        self.quDeg = Angle.degrees(P - q)
        self.qa = qa
        self.ruDeg = Angle.degrees(ru)
        self.ra = ra
    }

    /// Convenience: nodal angles for the elements at `date`.
    public init(at date: Date) {
        let e = Astronomy.elements(at: date)
        self.init(nodeDeg: e.nDeg, perigeeDeg: e.pDeg)
    }

    // MARK: - Node factors (Schureman eq. 73–80, 144, 215, 227)

    /// f(M₂) = cos⁴(½I) / 0.9154
    public var fM2: Double { pow(cos(Angle.radians(inclinationDeg) / 2), 4) / 0.9154 }
    /// f(O₁) = sin I · cos²(½I) / 0.3800
    public var fO1: Double {
        let I = Angle.radians(inclinationDeg)
        return sin(I) * pow(cos(I / 2), 2) / 0.3800
    }
    /// f(K₁) = √(0.8965 sin²2I + 0.6001 sin 2I cos ν + 0.1006)
    public var fK1: Double {
        let I = Angle.radians(inclinationDeg), nu = Angle.radians(nuDeg)
        return (0.8965 * pow(sin(2 * I), 2) + 0.6001 * sin(2 * I) * cos(nu) + 0.1006).squareRoot()
    }
    /// f(K₂) = √(19.0444 sin⁴I + 2.7702 sin²I cos 2ν + 0.0981)
    public var fK2: Double {
        let I = Angle.radians(inclinationDeg), nu = Angle.radians(nuDeg)
        return (19.0444 * pow(sin(I), 4) + 2.7702 * pow(sin(I), 2) * cos(2 * nu) + 0.0981).squareRoot()
    }
    /// f(J₁) = sin 2I / 0.7214
    public var fJ1: Double { sin(2 * Angle.radians(inclinationDeg)) / 0.7214 }
    /// f(OO₁) = sin I · sin²(½I) / 0.0164
    public var fOO1: Double {
        let I = Angle.radians(inclinationDeg)
        return sin(I) * pow(sin(I / 2), 2) / 0.0164
    }
    /// f(Mm) = (⅔ − sin²I) / 0.5021
    public var fMm: Double {
        (2.0 / 3.0 - pow(sin(Angle.radians(inclinationDeg)), 2)) / 0.5021
    }
    /// f(Mf) = sin²I / 0.1578
    public var fMf: Double { pow(sin(Angle.radians(inclinationDeg)), 2) / 0.1578 }
    /// f(M₃) = cos⁶(½I) / 0.8758
    public var fM3: Double { pow(cos(Angle.radians(inclinationDeg) / 2), 6) / 0.8758 }
    /// f(M₁) = f(O₁) · (1/Qa) — Qa is defined as an inverse (Schureman eq. 197).
    public var fM1: Double { fO1 / qa }
    /// f(L₂) = f(M₂) · (1/Ra) — Ra is defined as an inverse (Schureman eq. 213).
    public var fL2: Double { fM2 / ra }
}

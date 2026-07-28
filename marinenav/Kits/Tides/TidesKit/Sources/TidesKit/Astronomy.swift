import Foundation

/// Mean longitudes of the lunar and solar elements. Pure, stateless.
///
/// Source: Schureman, *Manual of Harmonic Analysis and Prediction of Tides*,
/// USC&GS Special Publication No. 98 (1958), **Table 1, p. 163** —
/// "Fundamental astronomical data" (U.S. Government work, public domain).
///
/// `T` is Julian centuries of 36525 days reckoned from **Greenwich mean noon,
/// 31 December 1899** (JD 2415020.0).
///
/// MODEL CAVEAT: these are mean (not true) longitudes from a polynomial fit
/// published in 1958. They are the arguments the harmonic method is *defined*
/// against — using a modern ephemeris here would make the constituent phases
/// disagree with every published set of harmonic constants, including NOAA's.
public enum Astronomy: Sendable {

    /// Reference epoch for `T`: Greenwich mean noon, 31 Dec 1899 = JD 2415020.0.
    public static let epochJD = 2_415_020.0

    /// Julian centuries (36525 d) from the Schureman epoch.
    public static func julianCenturies(at date: Date) -> Double {
        let jd = date.timeIntervalSince1970 / 86_400.0 + 2_440_587.5
        return (jd - epochJD) / 36_525.0
    }

    /// The five mean longitudes plus the mean-solar hour angle, all in degrees.
    ///
    /// - `hourAngleDeg` (Schureman's *T*) is the hour angle of the mean sun:
    ///   `15°·h_UT + 180°`, i.e. 180° at 00:00 UT.
    /// - `s` moon, `h` sun, `p` lunar perigee, `n` moon's ascending node,
    ///   `p1` solar perigee — each normalised to [0, 360).
    public struct Elements: Sendable, Equatable {
        public var hourAngleDeg: Double
        public var sDeg: Double
        public var hDeg: Double
        public var pDeg: Double
        public var nDeg: Double
        public var p1Deg: Double
    }

    /// Degrees from a sexagesimal degree/minute/second triple.
    @inline(__always)
    static func dms(_ d: Double, _ m: Double, _ s: Double) -> Double {
        d + m / 60.0 + s / 3600.0
    }

    /// Mean longitudes at `date` (UTC).
    ///
    /// Schureman Table 1, p. 163, verbatim:
    /// - h  = 279° 41′ 48.04″ + 129,602,768.13″·T + 1.089″·T²
    /// - s  = 270° 26′ 14.72″ + (1336 rev + 1,108,411.20″)·T + 9.09″·T² + 0.0068″·T³
    /// - p  = 334° 19′ 40.87″ + (11 rev + 392,515.94″)·T − 37.24″·T² − 0.045″·T³
    /// - N  = 259° 10′ 57.12″ − (5 rev + 482,912.63″)·T + 7.58″·T² + 0.008″·T³
    /// - p₁ = 281° 13′ 15.0″ + 6,189.03″·T + 1.63″·T² + 0.012″·T³
    public static func elements(at date: Date) -> Elements {
        let t = julianCenturies(at: date)
        let t2 = t * t, t3 = t2 * t

        let h  = dms(279, 41, 48.04) + (129_602_768.13 * t + 1.089 * t2) / 3600.0
        let s  = dms(270, 26, 14.72) + 1336.0 * 360.0 * t
               + (1_108_411.20 * t + 9.09 * t2 + 0.0068 * t3) / 3600.0
        let p  = dms(334, 19, 40.87) + 11.0 * 360.0 * t
               + (392_515.94 * t - 37.24 * t2 - 0.045 * t3) / 3600.0
        let n  = dms(259, 10, 57.12) - 5.0 * 360.0 * t
               + (-482_912.63 * t + 7.58 * t2 + 0.008 * t3) / 3600.0
        let p1 = dms(281, 13, 15.0) + (6_189.03 * t + 1.63 * t2 + 0.012 * t3) / 3600.0

        // UT hour straight from the epoch seconds. Unix time is UTC-based and
        // ignores leap seconds, so this is exact — and it avoids building a
        // Calendar per call, which dominated the cost when a caller evaluates
        // thousands of samples (finding slack water does exactly that).
        let seconds = date.timeIntervalSince1970
        var secondOfDay = seconds.truncatingRemainder(dividingBy: 86_400)
        if secondOfDay < 0 { secondOfDay += 86_400 }
        let hourUT = secondOfDay / 3600.0

        return Elements(hourAngleDeg: 15.0 * hourUT + 180.0,
                        sDeg: Angle.normalize(s),
                        hDeg: Angle.normalize(h),
                        pDeg: Angle.normalize(p),
                        nDeg: Angle.normalize(n),
                        p1Deg: Angle.normalize(p1))
    }

    /// Rates of change of the elements, in **degrees per mean solar hour**.
    /// Derived from the Table 1 linear coefficients; used to compute each
    /// constituent's angular speed from its Doodson coefficients.
    public enum Rate: Sendable {
        public static let hourAngle = 15.0
        public static let s  = (1336.0 * 360.0 + 1_108_411.20 / 3600.0) / (36525.0 * 24.0)
        public static let h  = (129_602_768.13 / 3600.0) / (36525.0 * 24.0)
        public static let p  = (11.0 * 360.0 + 392_515.94 / 3600.0) / (36525.0 * 24.0)
        public static let p1 = (6_189.03 / 3600.0) / (36525.0 * 24.0)
    }
}

/// Degree-angle helpers. Pure, stateless.
public enum Angle: Sendable {
    /// Wrap to [0, 360).
    public static func normalize(_ deg: Double) -> Double {
        let r = deg.truncatingRemainder(dividingBy: 360.0)
        return r < 0 ? r + 360.0 : r
    }

    /// Wrap to (−180, 180].
    public static func normalizeSigned(_ deg: Double) -> Double {
        let r = normalize(deg)
        return r > 180.0 ? r - 360.0 : r
    }

    @inline(__always) public static func radians(_ deg: Double) -> Double { deg * .pi / 180.0 }
    @inline(__always) public static func degrees(_ rad: Double) -> Double { rad * 180.0 / .pi }
}

import Foundation

/// Climb and descent planning math. Altitudes are feet, distances nautical miles,
/// speeds knots, rates feet/minute.
public enum ClimbDescent {

    /// Feet in one nautical mile.
    public static let feetPerNm = 6076.11549

    /// Descent rate (fpm) needed to lose an altitude over a ground distance at a groundspeed.
    public static func descentRateFpm(altitudeToLoseFt: Double, distanceNm: Double, gsKt: Double) -> Double {
        distanceNm > 0 ? altitudeToLoseFt * gsKt / (distanceNm * 60) : 0
    }

    /// Climb/descent rate (fpm) required to fly a gradient (ft/nm) at a groundspeed.
    public static func rateFpm(gradientFtPerNm: Double, gsKt: Double) -> Double {
        gradientFtPerNm * gsKt / 60
    }

    /// Distance before the destination (nm) to begin descent at a chosen gradient (ft/nm).
    public static func topOfDescentNm(altitudeToLoseFt: Double, gradientFtPerNm: Double) -> Double {
        gradientFtPerNm > 0 ? altitudeToLoseFt / gradientFtPerNm : 0
    }

    /// Climb gradient as a percentage from ft/nm.
    public static func gradientPercent(ftPerNm: Double) -> Double {
        ftPerNm / feetPerNm * 100
    }

    /// Climb gradient in degrees from ft/nm.
    public static func gradientDegrees(ftPerNm: Double) -> Double {
        atan(ftPerNm / feetPerNm) * 180 / .pi
    }

    /// Still-air glide distance (nm) from a height at a glide ratio (:1).
    public static func glideDistanceNm(glideRatio: Double, heightFt: Double) -> Double {
        glideRatio * heightFt / feetPerNm
    }
}

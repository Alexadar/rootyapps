// Ported from calculators/marine-navigation/intercept.swift/InterceptKit (oracle-first harvest, 2026-07-08).
import Foundation

/// Celestial navigation: Greenwich Hour Angle, sextant-altitude corrections, and
/// Marcq Saint-Hilaire sight reduction. Pure, stateless.
///
/// Conventions: latitude north-positive, longitude **east-positive**.
///
/// MODEL CAVEAT: GHA and declination come from compact analytic series (`SkyMath`), accurate to
/// roughly 0.1°–0.25° — good enough to identify a body and to demonstrate the reduction, but
/// **coarser than a Nautical Almanac daily page**, which is what an actual position fix should be
/// worked from. The sight-reduction trigonometry itself is exact; the ephemeris is the
/// approximation. Refraction assumes a standard atmosphere.
public enum Navigation {

    public enum Body: Sendable { case sun, moon }

    /// Greenwich Hour Angle (deg, [0,360)) and declination (deg) of a body at `date`.
    /// GHA = GMST − RA (apparent), i.e. the body's hour angle at Greenwich.
    public static func ghaDec(_ body: Body, at date: Date) -> (gha: Double, dec: Double) {
        let pos: SkyPosition = (body == .sun) ? SkyMath.sunPosition(date) : SkyMath.moonPosition(date)
        let gha = Deg.norm360(SkyMath.gmst(date) - pos.rightAscension)
        return (gha, pos.declination)
    }

    // MARK: Sextant corrections

    /// Dip of the horizon (arcminutes) for height of eye in metres: 1.76·√h.
    public static func dipArcmin(heightOfEyeMetres h: Double) -> Double { 1.76 * max(h, 0).squareRoot() }

    /// Atmospheric refraction (arcminutes) for apparent altitude (deg), Bennett's formula.
    public static func refractionArcmin(apparentAltitudeDeg h: Double) -> Double {
        guard h > -1 else { return 0 }
        return 1.0 / Deg.tan(h + 7.31 / (h + 4.4))
    }

    /// Observed altitude Ho (deg) from sextant altitude Hs (deg).
    /// `semiDiameterArcmin` is added for lower-limb sights, subtracted for upper-limb.
    public static func observedAltitude(sextantHs Hs: Double, indexErrorArcmin ic: Double,
                                        heightOfEyeMetres eye: Double,
                                        semiDiameterArcmin sd: Double = 0, lowerLimb: Bool = true) -> Double {
        let apparent = Hs - ic / 60 - dipArcmin(heightOfEyeMetres: eye) / 60
        let refr = refractionArcmin(apparentAltitudeDeg: apparent) / 60
        let sdCorr = (lowerLimb ? sd : -sd) / 60
        return apparent - refr + sdCorr
    }

    // MARK: Sight reduction (Marcq Saint-Hilaire intercept)

    public struct Reduction: Sendable, Equatable {
        public var computedAltitudeHc: Double   // deg
        public var azimuthZn: Double            // deg true, [0,360)
        public var interceptNM: Double          // nautical miles; + = "toward"
    }

    /// Reduce a sight from an assumed position. `observedHo` and assumed lat/long in degrees.
    public static func reduce(observedHo Ho: Double, gha: Double, dec: Double,
                              assumedLat: Double, assumedLonEast: Double) -> Reduction {
        let lha = Deg.norm360(gha + assumedLonEast)
        let hc = Deg.asin(Deg.sin(assumedLat) * Deg.sin(dec)
                          + Deg.cos(assumedLat) * Deg.cos(dec) * Deg.cos(lha))
        // azimuth measured from north, clockwise
        let zn = Deg.norm360(Deg.atan2(Deg.sin(lha),
                             Deg.cos(lha) * Deg.sin(assumedLat) - Deg.tan(dec) * Deg.cos(assumedLat)) + 180)
        let interceptNM = (Ho - hc) * 60   // 1° = 60 nm
        return Reduction(computedAltitudeHc: hc, azimuthZn: zn, interceptNM: interceptNM)
    }
}

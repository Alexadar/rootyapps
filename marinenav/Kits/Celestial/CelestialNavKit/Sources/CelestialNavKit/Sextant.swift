import Foundation

extension Navigation {

    /// A sextant's index correction, stated the way a navigator reads it off the
    /// instrument. Pure, stateless.
    ///
    /// This exists because the sign is the classic silent error: Bowditch and the
    /// Nautical Almanac state the **correction** (IC) that is *added* to the
    /// sextant reading, whereas `observedAltitude(sextantHs:indexErrorArcmin:…)`
    /// takes the **error**, which is *subtracted*. They are opposite in sign.
    ///
    /// - `onTheArc`: the sextant reads high; the correction is negative.
    /// - `offTheArc`: the sextant reads low; the correction is positive.
    public enum IndexCorrection: Sendable, Equatable {
        case onTheArc(arcmin: Double)
        case offTheArc(arcmin: Double)
        case none

        /// The correction to ADD to the sextant reading, arcminutes (Bowditch "IC").
        public var correctionArcmin: Double {
            switch self {
            case let .onTheArc(a):  return -abs(a)
            case let .offTheArc(a): return  abs(a)
            case .none:             return 0
            }
        }

        /// The index ERROR, arcminutes — the quantity `observedAltitude` subtracts.
        public var errorArcmin: Double { -correctionArcmin }
    }

    /// Local Hour Angle of a body at an assumed position, degrees in [0, 360).
    ///
    /// `LHA = GHA + east longitude`. A western assumed position carries a negative
    /// east longitude, and the result wraps — the classic trap this exists to
    /// contain, so that no caller has to open-code it.
    public static func localHourAngle(gha: Double, assumedLonEast: Double) -> Double {
        Deg.norm360(gha + assumedLonEast)
    }

    /// Dip of the horizon (arcminutes) for a height of eye in **feet**.
    ///
    /// Bowditch and the Nautical Almanac tabulate dip in feet; this is the same
    /// relation as `dipArcmin(heightOfEyeMetres:)` with the units converted, kept
    /// separate so a call site never has to guess which unit it is passing.
    public static func dipArcmin(heightOfEyeFeet feet: Double) -> Double {
        dipArcmin(heightOfEyeMetres: max(feet, 0) * 0.3048)
    }

    /// Observed altitude Ho from a sextant altitude, stated in almanac terms.
    ///
    /// This is the same computation as
    /// `observedAltitude(sextantHs:indexErrorArcmin:heightOfEyeMetres:…)` but takes
    /// the index correction and the height of eye in the form a navigator has them,
    /// so the two sign conventions cannot be mixed up.
    ///
    /// MODEL CAVEAT: refraction uses Bennett's formula for standard atmosphere.
    /// Non-standard temperature or pressure — and abnormal refraction near the
    /// horizon — are not modelled.
    public static func observedAltitude(sextantHs Hs: Double,
                                        indexCorrection ic: IndexCorrection,
                                        heightOfEyeFeet feet: Double,
                                        semiDiameterArcmin sd: Double = 0,
                                        lowerLimb: Bool = true) -> Double {
        observedAltitude(sextantHs: Hs,
                         indexErrorArcmin: ic.errorArcmin,
                         heightOfEyeMetres: max(feet, 0) * 0.3048,
                         semiDiameterArcmin: sd,
                         lowerLimb: lowerLimb)
    }

    /// Apparent altitude `ha` — the sextant reading corrected only for index error
    /// and dip, before refraction. Almanac tables are entered with this value.
    public static func apparentAltitude(sextantHs Hs: Double,
                                        indexCorrection ic: IndexCorrection,
                                        heightOfEyeFeet feet: Double) -> Double {
        Hs + ic.correctionArcmin / 60 - dipArcmin(heightOfEyeFeet: feet) / 60
    }
}

/// Degrees from a degrees-and-decimal-minutes reading, the form sextant altitudes
/// and almanac angles are published in (e.g. `34° 54.6′` → `dm(34, 54.6)`).
public func dm(_ degrees: Double, _ minutes: Double) -> Double {
    degrees >= 0 ? degrees + minutes / 60 : degrees - minutes / 60
}

import Foundation

/// Circular midpoints — the "half-sums" of classical astrology.
///
/// Two ecliptic longitudes have **two** midpoints, 180° apart: one bisects each of the two arcs
/// joining them. The convention everywhere in this domain (Ebertin's half-sums, and every
/// composite technique built on top of them) is the midpoint of the **shorter** arc, so that is
/// what `midpoint` returns.
///
/// The arithmetic mean is *not* that point, and that single line is where this keeps going wrong:
/// (350° + 10°) / 2 = 180°, the far midpoint, when the answer wanted is 0°. `midpoint` therefore
/// never averages raw longitudes. It works on the signed difference `norm180(b − a)`, which is by
/// construction the shorter arc *with its direction attached*, and steps half of it from `a`.
/// Direction is the part that silently disagrees between two copies of this maths, so there is
/// exactly one copy here and everything else calls it.
///
/// At opposition the shorter arc does not exist — both arcs are 180° long and both candidate
/// midpoints are equally valid. Left alone, the sign of a floating-point subtraction decides,
/// and `midpoint(0, 180)` and `midpoint(180, 0)` come back 180° apart. See `oppositionTolerance`
/// for the tie-break that removes that coin flip.
public enum Midpoints {

    /// Half-width, in degrees, of the band around 180° separation where the shorter arc is
    /// treated as undefined and the tie-break takes over.
    ///
    /// It is deliberately not zero, because "exactly opposite" is not a state floating point can
    /// be trusted to report: two longitudes that are mathematically opposite compute to a
    /// separation of 179.99999999999997 or 180.00000000000003 depending on the order of
    /// operations, and those two straddle the branch — they select *opposite* midpoints. Inside
    /// the band the answer is decided by the inputs rather than by the rounding.
    ///
    /// 1e-9° ≈ 3.6 microarcseconds, some seven orders of magnitude below this engine's own worst
    /// error (~6′ for the Moon), so no chart computed from real positions is ever pushed into the
    /// band by accident — only genuinely constructed oppositions land there.
    public static let oppositionTolerance: Double = 1e-9

    /// True when the two longitudes are close enough to opposition that the shorter arc is
    /// meaningless and `midpoint` falls back on its tie-break.
    ///
    /// Exposed so callers that care (a composite chart UI, say) can mark the result as ambiguous
    /// rather than present a 50/50 choice as fact.
    public static func isAmbiguous(_ a: Double, _ b: Double,
                                   tolerance: Double = oppositionTolerance) -> Bool {
        abs(AstroMath.separation(a, b) - 180) <= tolerance
    }

    /// Midpoint of the shorter arc between two ecliptic longitudes, in [0, 360).
    ///
    /// Inputs need not be normalized; −10° and 710° behave like 350°. The result is equidistant
    /// from both inputs and, outside the opposition band, lies on the shorter arc.
    ///
    /// **At opposition** (see `isAmbiguous`) both midpoints are equidistant and neither arc is
    /// shorter, so the ambiguity is resolved by a rule instead of by arithmetic luck: take the
    /// midpoint of the arc running counterclockwise (increasing longitude) from the numerically
    /// smaller of the two *normalized* longitudes. That rule depends on the set {a, b} and not on
    /// the argument order, so it is commutative like the rest of the function, and it agrees with
    /// what a reader computes by hand — `midpoint(0, 180) = 90`, not 270.
    public static func midpoint(_ a: Double, _ b: Double,
                                oppositionTolerance tol: Double = oppositionTolerance) -> Double {
        let a0 = AstroMath.norm360(a)
        let b0 = AstroMath.norm360(b)
        let delta = AstroMath.norm180(b0 - a0)          // shorter arc, signed
        guard abs(abs(delta) - 180) > tol else {
            // Opposition: both arcs are the same length. Documented tie-break.
            return AstroMath.norm360((min(a0, b0) + max(a0, b0)) / 2)
        }
        return AstroMath.norm360(a0 + delta / 2)
    }

    /// The midpoint's opposite point — the *other* midpoint, on the longer arc.
    ///
    /// Ebertin's technique treats a half-sum and its opposition as one axis (a planet sitting on
    /// either end activates it), so both ends are needed to work with midpoint axes at all.
    public static func oppositeMidpoint(_ a: Double, _ b: Double,
                                        oppositionTolerance tol: Double = oppositionTolerance) -> Double {
        AstroMath.norm360(midpoint(a, b, oppositionTolerance: tol) + 180)
    }

    /// Circular midpoint of two bodies' longitudes.
    public static func midpoint(_ a: BodyPosition, _ b: BodyPosition) -> Double {
        midpoint(a.longitude, b.longitude)
    }
}

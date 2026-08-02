import Foundation

/// Parallel / multi-pipe offsets — keeping a bank of pipes equally spaced through an offset.
/// Pure, stateless. Angles in degrees.
///
/// **TODO(oracle): not cited.** Every other namespace in this Kit is either a trigonometric identity
/// or checked against a published trade table. This one is not: the stagger between adjacent pipes
/// depends on a layout convention (which reference line the spacing is measured on), and I have not
/// found a citable published source for it. The functions below are derived from the geometry and
/// covered by *invariant* tests only — reduction to zero, linearity, monotonicity, round-trips.
///
/// Consequence, deliberately: **this namespace must not be surfaced as a tool** until a published
/// source is found and the reference tests are added. A green invariant suite is not a cited number.
///
/// Derivation being asserted: when pipes stacked `spacing` apart in the plane of the offset all turn
/// through the same fitting angle θ, holding their spacing constant through the sloped section requires
/// each successive fitting to be displaced along the run by
///
///     stagger = spacing · tan(θ ⁄ 2)
///
/// which vanishes as θ → 0 (no offset, no stagger) and equals the spacing at θ = 90° (a square jog).
public enum ParallelOffset {
    private static let d2r = Double.pi / 180

    /// Displacement along the run between adjacent pipes' fittings — `spacing · tan(θ ⁄ 2)`.
    /// TODO(oracle): needs a published pipefitting source before this reaches a user.
    public static func staggerIn(spacingIn: Double, fittingAngleDeg angleDeg: Double) -> Double {
        guard spacingIn > 0, angleDeg > 0, angleDeg <= 90 else { return 0 }
        return spacingIn * tan(angleDeg / 2 * d2r)
    }

    /// Total spread across `count` parallel pipes at equal `spacing` — `(count − 1) · spacing`.
    /// Definitional; no oracle needed.
    public static func spreadIn(count: Int, spacingIn: Double) -> Double {
        count > 1 ? Double(count - 1) * spacingIn : 0
    }

    /// Run consumed by the whole bank — the single-pipe run plus the stagger accumulated across it.
    /// TODO(oracle): inherits the uncited stagger above.
    public static func bankRunIn(setIn: Double, spacingIn: Double, count: Int,
                                 fittingAngleDeg angleDeg: Double) -> Double {
        let single = PipeOffset.runIn(setIn: setIn, fittingAngleDeg: angleDeg)
        guard count > 1 else { return single }
        return single + Double(count - 1) * staggerIn(spacingIn: spacingIn, fittingAngleDeg: angleDeg)
    }
}

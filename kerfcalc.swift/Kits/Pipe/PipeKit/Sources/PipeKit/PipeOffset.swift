import Foundation

/// Simple pipe offset — the fitter's right triangle. Pure, stateless. All angles in degrees.
///
/// An offset moves a run of pipe sideways by the **set** using two fittings of equal angle θ. The
/// diagonal piece between them is the **travel**; the horizontal distance it consumes is the **run**:
///
///     travel = set · csc θ      run = set · cot θ      θ = atan(set ⁄ run)
///
/// The trade's famous multipliers *are* those cosecants and cotangents — 45° → 1.414, 22½° → 2.613,
/// 11¼° → 5.126 — so the published table and the closed form are the same number, which makes this an
/// identity oracle cross-checked against a published one (see PipeOffsetOracleTests).
///
/// This is the same right triangle as `FramingKit.Pitch`, restated in the pipe trades' vocabulary
/// (set/travel/run rather than rise/diagonal/run). It is **deliberately duplicated rather than
/// imported**: no Kit in this app depends on another. `kerfcalcTests` asserts the two stay numerically
/// identical so the two spellings cannot drift apart.
///
/// Fitting angles are valid on `0° < θ ≤ 90°`. Outside that domain every function returns 0 rather
/// than trapping or producing a negative length — degenerate input must not crash a jobsite calculator.
public enum PipeOffset {
    private static let r2d = 180 / Double.pi
    private static let d2r = Double.pi / 180

    /// True for a physically meaningful fitting angle: greater than 0°, no more than 90°.
    private static func valid(_ angleDeg: Double) -> Bool { angleDeg > 0 && angleDeg <= 90 }

    /// Travel multiplier — `csc θ = 1 ⁄ sin θ`. Multiply the set by this to get the travel.
    /// 45° → 1.41421356, 30° → 2 exactly, 22½° → 2.61312593.
    public static func travelMultiplier(fittingAngleDeg angleDeg: Double) -> Double {
        guard valid(angleDeg) else { return 0 }
        let s = sin(angleDeg * d2r)
        return s > 0 ? 1 / s : 0
    }

    /// Run multiplier — `cot θ = cos θ ⁄ sin θ`. Multiply the set by this to get the run consumed.
    /// 45° → 1, 22½° → 2.41421356, 11¼° → 5.02733949.
    ///
    /// A square (90°) offset consumes no run at all, and that is answered exactly: `cos(π/2)` is
    /// 6.1e-17 rather than 0 in binary floating point, so cot 90° is snapped to a true zero instead of
    /// handing the caller a phantom sliver of run.
    public static func runMultiplier(fittingAngleDeg angleDeg: Double) -> Double {
        guard valid(angleDeg) else { return 0 }
        guard angleDeg != 90 else { return 0 }
        let s = sin(angleDeg * d2r)
        return s > 0 ? cos(angleDeg * d2r) / s : 0
    }

    /// Travel (the diagonal piece between the two fittings) — `set · csc θ`.
    public static func travelIn(setIn: Double, fittingAngleDeg angleDeg: Double) -> Double {
        setIn * travelMultiplier(fittingAngleDeg: angleDeg)
    }

    /// Run consumed by the offset along the pipe's original line — `set · cot θ`.
    public static func runIn(setIn: Double, fittingAngleDeg angleDeg: Double) -> Double {
        setIn * runMultiplier(fittingAngleDeg: angleDeg)
    }

    /// The fitting angle a given set and run imply — `atan(set ⁄ run)`, degrees.
    /// A zero run is a square (90°) offset.
    public static func fittingAngleDeg(setIn: Double, runIn: Double) -> Double {
        (setIn == 0 && runIn == 0) ? 0 : atan2(setIn, runIn) * r2d
    }

    /// The set a given travel and fitting angle produce — `travel · sin θ`. Inverse of `travelIn`.
    public static func setIn(travelIn: Double, fittingAngleDeg angleDeg: Double) -> Double {
        guard valid(angleDeg) else { return 0 }
        return travelIn * sin(angleDeg * d2r)
    }
}

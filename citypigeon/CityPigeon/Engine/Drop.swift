import Foundation
import MLX

/// A batched result: the values, plus a mask saying where a solution exists at all.
///
/// This replaces `Optional` in the vector world. An optional forces a branch per element and cannot
/// be batched; a value-plus-mask pair keeps the arithmetic branchless — invalid lanes still compute
/// *something*, and the mask decides whether anyone is allowed to believe it.
public struct Solution: Sendable {
    public var value: MLXArray
    /// Bool, same shape as `value`.
    public var valid: MLXArray

    public init(value: MLXArray, valid: MLXArray) {
        self.value = value
        self.valid = valid
    }

    /// Invalid lanes replaced by a sentinel, so the result can be fed straight into further maths.
    public func filled(_ sentinel: Float) -> MLXArray {
        which(valid, value, MLXArray(sentinel))
    }
}

/// A closed interval per lane, with a validity mask. Empty intervals are carried, never removed —
/// removing them would need a compaction, and a compaction is a gather.
public struct Window: Sendable {
    public var lo: MLXArray
    public var hi: MLXArray
    public var valid: MLXArray

    public init(lo: MLXArray, hi: MLXArray, valid: MLXArray) {
        self.lo = lo
        self.hi = hi
        self.valid = valid
    }

    /// How forgiving the shot is. Drives difficulty grading and the charge-meter HUD alike — the
    /// oracle and the interface read the same number, which is the only way they cannot disagree.
    public var width: MLXArray { hi - lo }
}

/// The closed-form drop, written as batch mathematics from the ground up.
///
/// Every function here takes and returns `MLXArray`. There is no loop over worlds, over payloads or
/// over targets anywhere in this file. That is what makes simulating one world and simulating ten
/// thousand literally the same code path, distinguished only by a leading dimension — the property
/// that makes batched sweeps free later instead of a rewrite.
///
/// Geometry: `+x` is the pigeon's flight direction, `+y` is up, the street is `y = 0`. A payload
/// released at height `H` above a target's impact plane with **signed upward** velocity `u` crosses
/// that plane at
///
///     T = (u + √(u² + 2gH)) / g
///
/// and the inverse is exactly elementary:
///
///     u = gT/2 − H/T
///
/// which is also the *proof* that `T` is strictly increasing in `u`: `du/dT = g/2 + H/T² > 0`, so
/// `u(T)` is a strictly increasing bijection with non-vanishing derivative and the inverse function
/// theorem does the rest — **with no case analysis for `u < 0`**, which is where differentiating `T`
/// directly gets uncomfortable.
public enum Drop {

    /// Time from release to crossing a plane `H` **below** the release point, on the descending branch.
    ///
    /// Two things here are not cosmetic.
    ///
    /// **The stable root.** `(u + √D)/g` is the *cancelling* form for exactly the case this game
    /// ships: a charged shot has `u < 0`, and `√(u² + 2gH) → |u|` as `2gH/u² → 0`, so the numerator
    /// is a difference of near-equal numbers. In Float32 (`ε ≈ 6e-8`) that is a relative error of
    /// about `ε·u²/(gH)` — tolerable at altitude, but this is a game about flying low over traffic.
    /// The `u < 0` branch multiplies through by the conjugate instead, giving `2H/(√D − u)`, whose
    /// denominator is a **sum** of positives whenever `H > 0` and therefore never cancels. Both
    /// branches are always evaluated and selected by `which`; branching per lane is not available
    /// and would not be wanted.
    ///
    /// **`H > 0` is a hard precondition, not tidiness.** With `H < 0` — a plane *above* the release
    /// point, which is a real case the moment a tall vehicle exists — the `+` root is the **wrong
    /// crossing**. It reports an impact the payload only reaches after passing through the body.
    /// At `H = 0` the model degenerates differently: `T ≡ 0` for every `u ≤ 0`, so the strict
    /// monotonicity everything downstream relies on is simply false there.
    public static func flightTime(releaseVelocity u: MLXArray, drop H: MLXArray,
                                  in w: WorldConfig) -> Solution {
        let g = MLXArray(Float(w.gravity))
        let positiveDrop = greater(H, 0)
        // Invalid lanes still compute something harmless rather than producing a NaN that would
        // propagate through every downstream op and poison valid lanes in a reduction.
        let safeH = which(positiveDrop, H, MLXArray(Float(1)))

        let D = u * u + 2 * g * safeH
        let root = sqrt(maximum(D, MLXArray(Float(0))))

        let ascending = (u + root) / g
        let descending = 2 * safeH / maximum(root - u, MLXArray(Float(1e-9)))
        let T = which(greaterEqual(u, 0), ascending, descending)

        return Solution(value: T, valid: logicalAnd(positiveDrop, greaterEqual(D, 0)))
    }

    /// The exact inverse, `u = gT/2 − H/T`. Rational algebra — no radical, so nothing to cancel.
    public static func releaseVelocity(flightTime T: MLXArray, drop H: MLXArray,
                                       in w: WorldConfig) -> Solution {
        let g = MLXArray(Float(w.gravity))
        let ok = logicalAnd(greater(T, 0), greater(H, 0))
        let safeT = which(greater(T, 0), T, MLXArray(Float(1)))
        return Solution(value: g * safeT / 2 - H / safeT, valid: ok)
    }

    /// Flight time at zero charge — the payload simply inherits the pigeon's climb rate.
    public static func unchargedTime(drop H: MLXArray, climb vy: MLXArray,
                                     in w: WorldConfig) -> Solution {
        flightTime(releaseVelocity: vy, drop: H, in: w)
    }

    /// Flight time at full charge.
    public static func fullChargeTime(drop H: MLXArray, climb vy: MLXArray,
                                      in w: WorldConfig) -> Solution {
        flightTime(releaseVelocity: vy - MLXArray(Float(w.maxChargeSpeed)), drop: H, in: w)
    }

    /// **Charge is linear in flight time, not in imparted speed.**
    ///
    /// `dT/du` collapses as charge rises, so a linear speed ramp would put nearly all of the meter's
    /// effect in the first third of its travel and leave the top dead. Interpolating the *time*
    /// instead is perfectly even and makes the meter altitude-relative. It costs no proof:
    /// composing with a strictly increasing reparametrisation preserves every monotonicity result
    /// in this file.
    public static func flightTime(drop H: MLXArray, climb vy: MLXArray, charge c: MLXArray,
                                  in w: WorldConfig) -> Solution {
        let t0 = unchargedTime(drop: H, climb: vy, in: w)
        let t1 = fullChargeTime(drop: H, climb: vy, in: w)
        return Solution(value: (1 - c) * t0.value + c * t1.value,
                        valid: logicalAnd(t0.valid, t1.valid))
    }

    /// The charge producing a given flight time. Strictly decreasing in `T`.
    ///
    /// Values outside `[0, 1]` are **retained, not clamped**, so callers can see how far out of
    /// reach a shot is — the spawner's admissibility band is driven by that deficit.
    public static func charge(flightTime T: MLXArray, drop H: MLXArray, climb vy: MLXArray,
                              in w: WorldConfig) -> Solution {
        let t0 = unchargedTime(drop: H, climb: vy, in: w)
        let t1 = fullChargeTime(drop: H, climb: vy, in: w)
        let span = t0.value - t1.value
        let usable = greater(abs(span), MLXArray(Float(1e-6)))
        let safeSpan = which(usable, span, MLXArray(Float(1)))
        return Solution(value: (t0.value - T) / safeSpan,
                        valid: logicalAnd(logicalAnd(t0.valid, t1.valid), usable))
    }

    /// Horizontal distance from release to impact — the quantity the ground reticle draws.
    ///
    /// Note what this is *not*. With the pigeon holding its velocity, the payload lands exactly
    /// beneath it: `x_p + v_x·T` is where the pigeon will be at impact too. The on-screen lead
    /// relative to the bird is identically zero at every charge. What charge actually buys is lead
    /// against the **traffic**, which moves `v_t·T` while the payload falls.
    public static func lead(forwardSpeed vx: MLXArray, flightTime T: MLXArray) -> MLXArray {
        vx * T
    }

    /// Analytic position of a payload at elapsed time `t` since release.
    ///
    /// Payloads are **never integrated**. Their whole state is `(release state, release time)` and
    /// position is evaluated fresh every frame. That makes replay exact, rewind free, sub-frame
    /// rendering possible, and drift impossible — and it is what lets the impact be resolved at
    /// release rather than discovered by a per-frame overlap test.
    public static func position(x0: MLXArray, y0: MLXArray, vx0: MLXArray, u0: MLXArray,
                                elapsed t: MLXArray, in w: WorldConfig) -> (x: MLXArray, y: MLXArray) {
        let g = MLXArray(Float(w.gravity))
        return (x0 + vx0 * t, y0 + u0 * t - 0.5 * g * t * t)
    }
}

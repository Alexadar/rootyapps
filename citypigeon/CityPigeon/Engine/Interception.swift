import Foundation
import MLX

/// Which charges hit a moving target — solved, not searched.
///
/// The key structural fact, and the reason there is no root-finder anywhere in this engine:
///
/// > **The miss is affine in flight time.** `f(T) = −Δx₀ + Δv·T`, where `Δx₀ = x_t − x_p` and
/// > `Δv = v_x − v_t`. All the nonlinearity of the problem lives in the monotone bijection
/// > `T ↔ u ↔ c`, and none of it is in the geometry.
///
/// So `{T : |f(T)| ≤ r}` is an interval by inspection — invert at `f = ±r` — and mapping it through
/// the strictly decreasing `T ↦ c` gives an interval of charges. Two divisions and a couple of
/// comparisons, branchless, fully batched. A bisection would have been a fixed-iteration loop with a
/// validity mask; instead there is no loop at all.
///
/// **The window, not the point, is the primitive.** The exact-hit charge `T* = Δx₀/Δv` is
/// catastrophically ill-conditioned as `Δv → 0`, and at `Δv = 0` it does not exist. The window
/// degrades gracefully through the same limit: it widens to everything (if the target is already
/// within `r`) or empties. The point solve is recovered as the window's midpoint, which is also the
/// *most forgiving* charge rather than merely a solution — a better thing to aim at anyway.
public enum Interception {

    /// Charges that land within `r` of the target, already clipped to the usable charge domain.
    ///
    /// Shapes broadcast: a `[B, 1]` pigeon against `[B, M]` targets yields `[B, M]` windows, which
    /// is exactly how the game asks "what can I hit right now" for every target at once.
    ///
    /// `radius` must be **constant with respect to charge**. If it grew with charge, `f + r` would
    /// be a difference of monotone functions, `{c : |f(c)| ≤ r(c)}` could stop being an interval,
    /// and this two-endpoint inversion would silently return a wrong set rather than fail.
    public static func window(pigeonX: MLXArray, pigeonY: MLXArray,
                              forwardSpeed vx: MLXArray, climb vy: MLXArray,
                              targetX: MLXArray, targetSpeed vt: MLXArray,
                              targetTopY: MLXArray, radius r: MLXArray,
                              in w: WorldConfig) -> Window {
        let cf = MLXArray(Float(w.chargeFloor)), cc = MLXArray(Float(w.chargeCeiling))

        let H = pigeonY - targetTopY
        let dx = targetX - pigeonX
        let dv = vx - vt

        // The achievable flight-time range, at the *usable* charge limits rather than at 0 and 1 —
        // a player cannot reliably produce either extreme, so a shot needing one is not available.
        let tUn = Drop.unchargedTime(drop: H, climb: vy, in: w)
        let tFull = Drop.fullChargeTime(drop: H, climb: vy, in: w)
        let span = tUn.value - tFull.value
        let tMax = (1 - cf) * tUn.value + cf * tFull.value      // slowest usable shot
        let tMin = (1 - cc) * tUn.value + cc * tFull.value      // fastest usable shot

        // Invert the miss at ±r. Ordering flips with the sign of Δv, so take min/max rather than
        // branching on it.
        let degenerate = less(abs(dv), MLXArray(Float(1e-4)))
        let safeDv = which(degenerate, MLXArray(Float(1)), dv)
        let ta = (dx - r) / safeDv
        let tb = (dx + r) / safeDv

        // Δv ≈ 0 is a THIRD OUTCOME, not an edge case to guard. The target and the pigeon are
        // co-moving, `f` is constant, and the answer is either "every charge hits" or "none does".
        // That cannot be expressed as a value, which is why it is folded into the interval here.
        let coMovingHits = lessEqual(abs(dx), r)
        let tLo = which(degenerate, tMin, minimum(ta, tb))
        let tHi = which(degenerate, tMax, maximum(ta, tb))

        // Clip to what the charge meter can actually produce. Clipping in T and clipping in c are
        // the same operation because tMin/tMax were computed at the charge limits.
        let loC = maximum(tLo, tMin)
        let hiC = minimum(tHi, tMax)

        // T ↦ c is strictly DECREASING, so the interval ends swap.
        let usableSpan = greater(abs(span), MLXArray(Float(1e-6)))
        let safeSpan = which(usableSpan, span, MLXArray(Float(1)))
        let cLo = clip((tUn.value - hiC) / safeSpan, min: cf, max: cc)
        let cHi = clip((tUn.value - loC) / safeSpan, min: cf, max: cc)

        var valid = logicalAnd(tUn.valid, tFull.valid)
        valid = logicalAnd(valid, usableSpan)
        valid = logicalAnd(valid, greaterEqual(hiC, loC))
        valid = logicalAnd(valid, greaterEqual(cHi, cLo))
        // In the co-moving case the geometry alone decides.
        valid = logicalAnd(valid, which(degenerate, coMovingHits, MLXArray(true)))

        return Window(lo: cLo, hi: cHi, valid: valid)
    }

    /// The most forgiving charge for a shot: the midpoint of the window.
    ///
    /// Deliberately derived from the window rather than solved separately. `Δx₀/Δv` is the textbook
    /// expression and it is a trap — as `Δv → 0` it blows up, while the shot it describes is getting
    /// *easier*, not harder.
    public static func bestCharge(_ window: Window) -> Solution {
        Solution(value: (window.lo + window.hi) / 2, valid: window.valid)
    }

    /// Signed horizontal miss at impact for a given charge. Positive means the payload lands ahead
    /// of the target's centre. This is the function the oracle's independent bisector searches on,
    /// and it must not share code with `window` beyond `Drop` itself.
    public static func miss(pigeonX: MLXArray, pigeonY: MLXArray,
                            forwardSpeed vx: MLXArray, climb vy: MLXArray,
                            targetX: MLXArray, targetSpeed vt: MLXArray,
                            targetTopY: MLXArray, charge c: MLXArray,
                            in w: WorldConfig) -> Solution {
        let H = pigeonY - targetTopY
        let T = Drop.flightTime(drop: H, climb: vy, charge: c, in: w)
        let impactX = pigeonX + vx * T.value
        let targetAtImpact = targetX + vt * T.value
        return Solution(value: impactX - targetAtImpact, valid: T.valid)
    }

    /// Time of flight for a given charge — needed by the renderer for the ghost marker showing where
    /// the target will be when the payload arrives.
    public static func flightTime(pigeonY: MLXArray, climb vy: MLXArray,
                                  targetTopY: MLXArray, charge c: MLXArray,
                                  in w: WorldConfig) -> Solution {
        Drop.flightTime(drop: pigeonY - targetTopY, climb: vy, charge: c, in: w)
    }
}

// MARK: - Release timing
//
// Everything above answers "if I let go **now**, which charge hits?". That is the right question for
// the reticle, and the wrong one for anything that plans a shot: charging takes 0.9 s, and the world
// does not pause while it happens. A pilot that solves for a charge and then holds until it arrives
// is aiming at a world that moved on while it waited.

extension Interception {

    /// When to let go, given that you start charging now.
    ///
    /// **The problem is affine, so it is solved rather than searched** — the same structural luck
    /// that keeps the rest of this file loop-free, one level up.
    ///
    /// Charge is linear in flight time by construction (`Drop.flightTime(drop:climb:charge:)`), and
    /// charge is linear in hold time (`Step` phase 2). Compose them and the *impact time* is affine
    /// in the *release time*:
    ///
    ///     G(τ) = τ + T(c(τ)) = G₀ + a·τ        a = 1 − (t₀ − t₁)/chargeTime
    ///
    /// with `a` a **constant** — about −0.27 at shipping tuning. Negative, which is worth sitting
    /// with: holding longer makes the payload land *earlier* in absolute time, because charging
    /// shortens the fall faster than waiting delays the throw.
    ///
    /// The miss is then the same affine form the instantaneous solver uses, in τ instead of T:
    ///
    ///     miss(τ) = −Δx₀ + Δv·G(τ)
    ///
    /// so the solution set is recovered by inverting at ±r. Two branches, because the charge
    /// saturates: while it is still ramping the slope is `a`; once it pins at `chargeCeiling` the
    /// extra time buys travel but no charge, and the slope becomes exactly 1.
    ///
    /// ⚠️ **`G` is affine on each branch but not monotone overall.** With `a < 0` it *descends* while
    /// charging and *ascends* after saturation, so it is V-shaped with its minimum at `τ_full`, and
    /// `{τ : |miss| ≤ r}` is in general **two disjoint intervals** — one on each limb. An earlier
    /// version of this function returned their hull, which declared the gap between them hittable;
    /// the set-equality test found τ values inside the reported window that missed by up to 0.2 m.
    ///
    /// A `Window` is one interval, so this returns the **earlier limb** when both exist: the ramping
    /// branch lies entirely within `[0, τ_full]` and the saturated branch entirely after it, so
    /// "earlier" is unambiguous, and a pilot wants the soonest shot it can take rather than the one
    /// that requires holding through the ceiling.
    ///
    /// **Precondition, stated rather than hidden:** `t₀` and `t₁` depend on the pigeon's altitude and
    /// climb rate, which drift during the hold under the step's exponential velocity approach. The
    /// affine result assumes the pigeon holds its state across the hold — exactly true for a level
    /// pilot, approximately true for a manoeuvring player, and re-solved every frame either way.
    ///
    /// Returns a window in **seconds from now**, not in charge.
    public static func releaseWindow(pigeonX: MLXArray, pigeonY: MLXArray,
                                     forwardSpeed vx: MLXArray, climb vy: MLXArray,
                                     charge cNow: MLXArray,
                                     targetX: MLXArray, targetSpeed vt: MLXArray,
                                     targetTopY: MLXArray, radius r: MLXArray,
                                     in w: WorldConfig) -> Window {
        let ct = Float(w.chargeTime)
        let cc = MLXArray(Float(w.chargeCeiling))

        let H = pigeonY - targetTopY
        let dx = targetX - pigeonX
        let dv = vx - vt

        let t0 = Drop.unchargedTime(drop: H, climb: vy, in: w)
        let t1 = Drop.fullChargeTime(drop: H, climb: vy, in: w)
        let span = t0.value - t1.value                       // t₀ − t₁ > 0

        // Impact time as seen from now, on each branch.
        let a = 1 - span / ct                                 // ramping slope, constant
        let gAtZero = t0.value + cNow * (t1.value - t0.value) // G(0), charge already held
        let tauFull = maximum((cc - cNow) * ct, MLXArray(Float(0)))
        let gAtFull = tauFull + t0.value + cc * (t1.value - t0.value)

        // Required impact time for a hit, as an interval: Δv·G ∈ [Δx − r, Δx + r].
        let degenerate = less(abs(dv), MLXArray(Float(1e-4)))
        let safeDv = which(degenerate, MLXArray(Float(1)), dv)
        let ga = (dx - r) / safeDv
        let gb = (dx + r) / safeDv
        let gLo = minimum(ga, gb), gHi = maximum(ga, gb)

        // Branch 1 — still ramping, τ ∈ [0, τ_full], slope `a`. Invert and order by sign(a).
        let flat = less(abs(a), MLXArray(Float(1e-6)))
        let safeA = which(flat, MLXArray(Float(1)), a)
        let r1 = (gLo - gAtZero) / safeA
        let r2 = (gHi - gAtZero) / safeA
        var loRamp = minimum(r1, r2), hiRamp = maximum(r1, r2)
        loRamp = maximum(loRamp, MLXArray(Float(0)))
        hiRamp = minimum(hiRamp, tauFull)
        let rampOK = logicalAnd(logicalNot(flat), greaterEqual(hiRamp, loRamp))

        // Branch 2 — saturated, τ ≥ τ_full, slope exactly 1.
        var loSat = maximum(gLo - gAtFull + tauFull, tauFull)
        var hiSat = gHi - gAtFull + tauFull
        loSat = maximum(loSat, MLXArray(Float(0)))
        hiSat = maximum(hiSat, loSat - 1)                     // keep ordered; validity decides
        let satOK = greaterEqual(hiSat, loSat)

        // Prefer the earlier limb. NOT a hull — see the V-shape note above.
        let lo = which(rampOK, loRamp, loSat)
        let hi = which(rampOK, hiRamp, hiSat)

        var valid = logicalAnd(t0.valid, t1.valid)
        valid = logicalAnd(valid, logicalOr(rampOK, satOK))
        valid = logicalAnd(valid, greaterEqual(hi, lo))
        // Co-moving: `miss` no longer depends on τ at all, so geometry alone decides — the same
        // third outcome the instantaneous solver has, arriving here for the same reason.
        valid = logicalAnd(valid, which(degenerate, lessEqual(abs(dx), r), MLXArray(true)))

        return Window(lo: lo, hi: hi, valid: valid)
    }

    /// The charge the meter will be showing at release time `τ`, clamped to the usable domain.
    ///
    /// This is what lets a stateless pilot use a *time* solution: it never has to remember when it
    /// started holding, because `w.charge` already is that clock.
    public static func chargeAtRelease(_ tau: MLXArray, chargeNow cNow: MLXArray,
                                       in w: WorldConfig) -> MLXArray {
        clip(cNow + tau / Float(w.chargeTime),
             min: MLXArray(Float(w.chargeFloor)), max: MLXArray(Float(w.chargeCeiling)))
    }
}

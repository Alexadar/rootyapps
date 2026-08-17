import Foundation
import MLX

/// Targets are placed **hittable by construction**, never generated-and-rejected.
///
/// The whole firing window is closed form. Working in the gap `Δx(t) = x_t(t) − x_p(t)`, which is
/// affine with slope `−Δv`, a hit needs `Δv·[T_min, T_max]` to meet `[Δx − r, Δx + r]`. Two intervals
/// meet on an interval, so:
///
///     duration = (T_max − T_min) + 2r / |v_x − v_t|
///     opens at   Δx = Δv·T_max + r
///
/// Two consequences the design turns on.
///
/// **The offset is `Δv·T_max`, not `v_x·T_max`.** For oncoming traffic `Δv > v_x`, so using the
/// pigeon's own lead spawns the target *already inside* its window — the window opens off-screen and
/// the reaction-time guarantee is void. This was a real bug in the first draft of the design.
///
/// **The admissible target-speed band is derived, not sampled.** Requiring `duration ≥ Δt_min`
/// rearranges to `|Δv| ≤ 2r / (Δt_min − (T_max − T_min))`, a closed-form bound. The spawner draws
/// inside it, so there is nothing to reject — which matters doubly here, because rejection sampling
/// is a `while` loop and this engine does not have those.
public enum Spawn {

    /// A window, in the scalar form the config tests and the difficulty tuner reason about.
    public struct FiringWindow: Hashable, Sendable {
        /// Gap at which the window opens (target still ahead) and closes.
        public var opensAtGap: Double
        public var closesAtGap: Double
        public var duration: Double
        /// The widest charge interval available anywhere in the window. Zero at both edges by
        /// tangency, so duration alone overstates how fair a window is.
        public var widestChargeWindow: Double
    }

    public enum Verdict: Hashable, Sendable {
        case fair(FiringWindow)
        case neverCloses           // Δv ≤ 0: the target is not being caught up with
        case windowTooShort(Double)
        case chargeWindowTooTight(Double)
        case opensOffScreen(by: Double)
        case unreachable
    }

    // MARK: - The guarantee band

    /// The smallest charge-driven time spread anywhere in the guarantee box.
    ///
    /// `T_max − T_min` is a free additive term in every window's duration, so its **worst case** is
    /// what the fairness bound must be built on. It shrinks with altitude, so the worst corner is the
    /// bottom of the band.
    public static func worstChargeSpan(_ p: TargetProfile, in w: WorldConfig) -> Double {
        var worst = Double.infinity
        for alt in [w.guaranteeAltitudeRange.lowerBound, w.guaranteeAltitudeRange.upperBound] {
            for vy in [w.guaranteeClimbRange.lowerBound, 0, w.guaranteeClimbRange.upperBound] {
                let H = alt - p.topY
                guard let t0 = w.flightTime(drop: H, climb: vy, charge: w.chargeFloor),
                      let t1 = w.flightTime(drop: H, climb: vy, charge: w.chargeCeiling)
                else { continue }
                worst = min(worst, t0 - t1)
            }
        }
        return worst
    }

    /// The largest flight time the pigeon can produce anywhere in the guarantee box — the quantity
    /// the spawn offset is measured in.
    public static func maxFlightTime(_ p: TargetProfile, in w: WorldConfig) -> Double {
        let H = w.guaranteeAltitudeRange.upperBound - p.topY
        return w.flightTime(drop: H, climb: w.guaranteeClimbRange.upperBound,
                            charge: w.chargeFloor) ?? .nan
    }

    /// **Derived** from the fairness floor: the fastest a target may close and still give the player
    /// react + charge + cooldown inside its window.
    public static func maxClosingSpeed(_ p: TargetProfile, in w: WorldConfig) -> Double {
        let slack = w.minFairWindow - worstChargeSpan(p, in: w)
        guard slack > 0 else { return .infinity }   // the charge range alone already clears the floor
        return 2 * w.hitRadius(p) / slack
    }

    /// Target speeds that produce a fair window, intersected with the kind's authored envelope.
    ///
    /// `nil` means the tuning is broken, not that this target is unlucky — which is why
    /// `ConfigDerivationTests` asserts it is never nil rather than the spawner handling it.
    public static func admissibleSpeeds(_ p: TargetProfile, in w: WorldConfig) -> ClosedRange<Double>? {
        // The gap must actually close, or the target is never caught. A floor rather than `> 0`
        // because near-co-moving targets have unboundedly long windows and are trivial.
        let minClosing = 2.0
        // Two independent ceilings on how fast a target may close: the window must be long enough
        // (fairness), and the whole approach must fit on screen (visibility). Both are closed form,
        // so the band is an intersection of intervals rather than something to search for.
        let byFairness = w.cruiseSpeed - maxClosingSpeed(p, in: w)
        let byCamera = w.cruiseSpeed - maxVisibleClosingSpeed(p, in: w)
        let lo = max(p.speedRange.lowerBound, max(byFairness, byCamera))
        let hi = min(p.speedRange.upperBound, w.cruiseSpeed - minClosing)
        return lo <= hi ? lo...hi : nil
    }

    /// The gap at which a target's firing window opens.
    public static func windowOpensAt(targetSpeed vt: Double, _ p: TargetProfile,
                                     in w: WorldConfig) -> Double {
        (w.cruiseSpeed - vt) * maxFlightTime(p, in: w) + w.hitRadius(p)
    }

    /// The fastest a target may close and still be **seen approaching** for `minPreVisibility`
    /// before its window opens.
    ///
    /// A target that materialises at the instant it becomes hittable is indistinguishable from an
    /// unfair one, however long its window is. Solving
    /// `Δv·T_max + r + Δv·preVisibility ≤ visibleAhead` for `Δv` gives the bound directly.
    public static func maxVisibleClosingSpeed(_ p: TargetProfile, in w: WorldConfig) -> Double {
        let denom = maxFlightTime(p, in: w) + w.minPreVisibility
        guard denom > 0 else { return .infinity }
        return (w.visibleAheadOfPigeon - w.hitRadius(p)) / denom
    }

    /// Where a target must appear: far enough ahead that the player watches it close for
    /// `minPreVisibility` before the window opens, and still on screen.
    public static func spawnGap(targetSpeed vt: Double, _ p: TargetProfile,
                                in w: WorldConfig) -> Double? {
        let dv = w.cruiseSpeed - vt
        guard dv > 0 else { return nil }
        let gap = windowOpensAt(targetSpeed: vt, p, in: w) + dv * w.minPreVisibility
        return gap <= w.visibleAheadOfPigeon ? gap : nil
    }

    // MARK: - Verification

    /// What the oracle asks of every spawn the generator produces.
    public static func verify(targetSpeed vt: Double, gap: Double, _ p: TargetProfile,
                              in w: WorldConfig) -> Verdict {
        let dv = w.cruiseSpeed - vt
        guard dv > 0 else { return .neverCloses }

        let r = w.hitRadius(p)
        let span = worstChargeSpan(p, in: w)
        guard span.isFinite, span > 0 else { return .unreachable }

        let opens = windowOpensAt(targetSpeed: vt, p, in: w)
        guard opens <= w.visibleAheadOfPigeon else {
            return .opensOffScreen(by: opens - w.visibleAheadOfPigeon)
        }
        // The target must have been visible and closing for minPreVisibility before this point,
        // otherwise it appeared already hittable and the player never saw it coming.
        let needed = opens + dv * w.minPreVisibility
        guard gap >= needed - 1e-9 else { return .opensOffScreen(by: needed - gap) }
        guard gap <= w.visibleAheadOfPigeon + 1e-9 else {
            return .opensOffScreen(by: gap - w.visibleAheadOfPigeon)
        }

        let duration = span + 2 * r / dv
        guard duration >= w.minFairWindow else { return .windowTooShort(duration) }

        // The charge interval is widest when the target sits at the window's centre, where the
        // required flight time is mid-range.
        let widest = min(1.0, 2 * r / (dv * max(span, 1e-9)))
        guard widest >= w.minChargeWindow else { return .chargeWindowTooTight(widest) }

        let closes = opens - dv * duration
        return .fair(FiringWindow(opensAtGap: opens, closesAtGap: closes,
                                  duration: duration, widestChargeWindow: widest))
    }

    // MARK: - Device-side emission

    /// Map an already-drawn uniform into the admissible speed band.
    ///
    /// Takes the uniform rather than drawing one, because the step draws every lane it needs in a
    /// single hash — the engine is bound by operation count and a hash is a dozen operations.
    ///
    /// The band is a closed-form interval, so this is a scale-and-shift. There is no rejection step,
    /// and therefore no data-dependent control flow.
    public static func speeds(fromUniform u: MLXArray, _ p: TargetProfile,
                              in w: WorldConfig) -> MLXArray {
        guard let band = admissibleSpeeds(p, in: w) else {
            // Unreachable in a tested build; the config suite proves the band is non-empty.
            return MLXArray.zeros(u.shape) + Float(w.cruiseSpeed - 2.0)
        }
        return Rng.scaled(u, into: band)
    }

    /// The gap at which each target should appear, given its speed and a jitter uniform.
    public static func emissionGap(targetSpeed vt: MLXArray, jitter u: MLXArray,
                                   _ p: TargetProfile, in w: WorldConfig) -> MLXArray {
        let dv = MLXArray(Float(w.cruiseSpeed)) - vt
        let base = dv * Float(maxFlightTime(p, in: w) + w.minPreVisibility) + Float(w.hitRadius(p))
        // Jitter upward only — downward would eat into the pre-visibility guarantee — and clamped
        // so a target never appears beyond the camera.
        return minimum(base + u * 3.0, MLXArray(Float(w.visibleAheadOfPigeon)))
    }

    /// Convenience for tests: draw and map in one call.
    public static func sampleSpeeds(shape: [Int], _ p: TargetProfile, in w: WorldConfig,
                                    seed: UInt64, frame: Int) -> MLXArray {
        speeds(fromUniform: Rng.uniform(shape, seed: seed, frame: frame, stream: .targetSpeed),
               p, in: w)
    }
}

import Foundation

/// A batched result: the values, plus a mask saying where a solution exists at all.
///
/// This replaces `Optional` in the vector world. An optional forces a branch per element and cannot
/// be batched; a value-plus-mask pair keeps the arithmetic branchless — invalid lanes still compute
/// *something*, and the mask decides whether anyone is allowed to believe it.
public struct Solution: Sendable {
    public var value: Tensor
    /// 1 where `value` is meaningful, 0 where no solution exists.
    public var valid: Tensor

    public init(value: Tensor, valid: Tensor) {
        self.value = value
        self.valid = valid
    }

    /// Invalid lanes replaced by a sentinel, so the result can be fed straight into further maths.
    public func filled(_ sentinel: Double) -> Tensor {
        Tensor.which(valid, value, sentinel)
    }
}

/// The closed-form ballistic model — **written as batch mathematics from the ground up**.
///
/// Every function here takes tensors and returns tensors. There is no loop over worlds, over
/// rooftops, or over candidate jumps anywhere in this file; the only loops in the Kit live inside
/// `Tensor`'s elementwise kernels. That is what makes solving one district and solving ten thousand
/// districts literally the same code path, distinguished only by a leading dimension — the property
/// that makes batching worlds free later instead of a rewrite.
///
/// The scalar entry points at the bottom are thin wrappers over batch-of-one. They exist for
/// readability at call sites that genuinely handle a single jump (the aim preview), and because
/// routing them through the batch implementation means every scalar test is also a test of the
/// vector code.
///
/// Launch is at a fixed elevation `θ` with the player choosing yaw and power. In the vertical plane
/// containing the yaw ray, with `d` horizontal distance and `h` the rise to the target:
///
///     h(d) = d·tanθ − g·d² / (2·v²·cos²θ)
///
public enum Ballistics {

    // MARK: - Speed and power

    /// Launch speed for powers in 0…1.
    public static func speed(power: Tensor, boosted: Bool, in w: WorldConfig) -> Tensor {
        power * (boosted ? w.maxLaunchSpeed * w.flyMultiplier : w.maxLaunchSpeed)
    }

    /// The shortest distance at which a jump can *land* on a surface `h` above the launch.
    ///
    /// An upward arc crosses any height below its apex **twice** — once climbing, once falling —
    /// and only the second one is a landing. Closer than this, the frog is still rising as it passes
    /// the roof's height, so it sails over the roof rather than onto it.
    ///
    /// The two crossings coincide exactly at `d·tanθ = 2h`. (Derivation: the crossings are the roots
    /// of `a·d² − d·tanθ + h = 0`; the descending root is the larger, so `d ≥ tanθ/2a`, and
    /// substituting `a = (d·tanθ − h)/d²` reduces to `d·tanθ ≥ 2h`.) Zero for level or downhill
    /// targets, which can be landed on at any distance.
    public static func minimumLandingDistance(rise h: Tensor, in w: WorldConfig) -> Tensor {
        let t = tan(w.launchElevation)
        return (h * (2 / t)).maximum(0)
    }

    /// The speed required to **land** at `d` horizontally while rising `h`.
    ///
    ///     v² = g·d² / (2·cos²θ·(d·tanθ − h))
    ///
    /// Invalid in two distinct cases, and the difference matters:
    ///
    ///  * `d·tanθ ≤ h` — the target sits above the straight launch ray. Nothing reaches it at any
    ///    speed, because the arc only ever falls away from that ray. This is the height ceiling that
    ///    makes the envelope asymmetric.
    ///  * `d·tanθ < 2h` — a speed exists that *passes through* the point, but on the way up. The
    ///    frog would clear the roof and land beyond it, so certifying this as a landing would be a
    ///    lie: the solver would promise a route the player cannot fly. (The oracle caught exactly
    ///    this on its first run, when the guard was missing.)
    public static func requiredSpeed(range d: Tensor, rise h: Tensor, in w: WorldConfig) -> Solution {
        let θ = w.launchElevation
        let t = tan(θ), c = cos(θ)

        let dTan = d * t
        let onDescendingBranch = dTan .>= (h * 2)
        let denom = (dTan - h) * (2 * c * c)
        let positiveDenom = denom .> 0

        let valid = (d .> 0) .&& onDescendingBranch .&& positiveDenom
        // Invalid lanes compute a harmless value rather than branching around it.
        let safeDenom = Tensor.which(positiveDenom, denom, 1.0)
        let v2 = (d * d) * w.gravity / safeDenom
        return Solution(value: v2.squareRoot, valid: valid)
    }

    /// The power in 0…1 required for a jump. Values above 1 are kept so callers can see *how far*
    /// out of reach a jump is — the generator's repair step is driven by that deficit.
    public static func requiredPower(range d: Tensor, rise h: Tensor,
                                     boosted: Bool, in w: WorldConfig) -> Solution {
        let s = requiredSpeed(range: d, rise: h, in: w)
        let vMax = boosted ? w.maxLaunchSpeed * w.flyMultiplier : w.maxLaunchSpeed
        return Solution(value: s.value / vMax, valid: s.valid)
    }

    // MARK: - Range

    /// Horizontal distance at which a jump of speed `v` crosses the plane `h` above the launch.
    ///
    /// The descending root of `a·d² − d·tanθ + h = 0` with `a = g / (2v²cos²θ)`.
    public static func range(speed v: Tensor, rise h: Tensor, in w: WorldConfig) -> Solution {
        let θ = w.launchElevation
        let t = tan(θ), c = cos(θ)

        let positiveSpeed = v .> 0
        let safeV = Tensor.which(positiveSpeed, v, 1.0)
        let a = (safeV * safeV * (2 * c * c)).map { w.gravity / $0 }

        let disc = (t * t) - (a * h * 4)
        // At exactly `criticalSpeed(rise:)` the two crossings merge and this discriminant is
        // mathematically zero — but in floating point it lands either side of zero, and a bare
        // `disc >= 0` then refuses a jump that is genuinely on the boundary. The oracle caught this
        // as a reachable roof reported unreachable, which in the game would show up as the
        // generator quietly discarding perfectly good districts.
        let hasRoot = disc .>= -1e-12
        let root = disc.maximum(0).squareRoot
        let d = (root + t) / (a * 2)

        return Solution(value: d, valid: positiveSpeed .&& hasRoot)
    }

    /// The slowest speed that can reach a rise of `h` at all.
    ///
    /// Below it the apex is under the target and no distance works; at exactly it the two crossings
    /// coincide. Zero for level or downhill targets.
    public static func criticalSpeed(rise h: Tensor, in w: WorldConfig) -> Tensor {
        let s = sin(w.launchElevation)
        let positive = h .> 0
        let v = (h * (2 * w.gravity)).maximum(0).squareRoot / s
        return Tensor.which(positive, v, 0.0)
    }

    /// Apex height above the launch point.
    public static func apex(speed v: Tensor, in w: WorldConfig) -> Tensor {
        let s = v * sin(w.launchElevation)
        return s * s / (2 * w.gravity)
    }

    /// Time of flight to the plane `h` above the launch.
    public static func flightTime(speed v: Tensor, rise h: Tensor, in w: WorldConfig) -> Solution {
        let r = range(speed: v, rise: h, in: w)
        let horizontal = v * cos(w.launchElevation)
        let nonZero = horizontal .> 0
        let safe = Tensor.which(nonZero, horizontal, 1.0)
        return Solution(value: r.value / safe, valid: r.valid .&& nonZero)
    }

    /// Speed components at the moment the target plane is crossed. `vertical` is the downward
    /// magnitude, and it is what decides whether a landing settles or bounces.
    public static func impactSpeed(speed v: Tensor, rise h: Tensor,
                                   in w: WorldConfig) -> (horizontal: Tensor, vertical: Solution) {
        let up = v * sin(w.launchElevation)
        let vv = (up * up) - (h * (2 * w.gravity))
        let reaches = vv .>= 0
        return (v * cos(w.launchElevation),
                Solution(value: vv.maximum(0).squareRoot, valid: reaches))
    }

    // MARK: - Landing tolerance

    /// How far inside a rooftop's edge the frog must land for the landing to stick.
    ///
    /// Froggo 1 got its settle from SpriteKit (restitution 0.2, friction 0.8 on both bodies). We
    /// author the same behaviour, which means we can also *predict* it — so the usable part of a
    /// roof is its footprint shrunk by the frog's own half-width plus however far it will skid.
    ///
    /// Each bounce leaves with `e·vy` upward and keeps `tr` of its horizontal speed, so bounce `i`
    /// covers `vx·tr^i · 2·e^i·vy/g`. The series is short and capped. Below the bounce threshold the
    /// landing settles on contact and the skid is zero.
    public static func landingInset(horizontal vx: Tensor, vertical vy: Tensor,
                                    in w: WorldConfig) -> Tensor {
        guard w.maxBounces > 0 else { return Tensor(repeating: w.frogHalfWidth, shape: vx.shape) }

        var skid = Tensor.zeros(vx.shape)
        for i in 1...w.maxBounces {
            let tangential = vx * pow(w.tangentialRetention, Double(i))
            let airTime = vy * (2 * pow(w.restitution, Double(i)) / w.gravity)
            skid = skid + tangential * airTime
        }
        let bounces = vy .> w.bounceThreshold
        return Tensor.which(bounces, skid, 0.0) + w.frogHalfWidth
    }

    // MARK: - The arc

    /// Position at time `t`, relative to the launch point, for a batch of jumps.
    public static func position(speed v: Tensor, yaw: Tensor, t: Tensor, in w: WorldConfig) -> (x: Tensor, y: Tensor, z: Tensor) {
        let horizontal = v * cos(w.launchElevation) * t
        let y = (v * sin(w.launchElevation) * t) - (t * t * (0.5 * w.gravity))
        let dirX = yaw.map { sin($0) }
        let dirZ = yaw.map { -cos($0) }
        return (dirX * horizontal, y, dirZ * horizontal)
    }
}

// MARK: - Scalar convenience
//
// Single-jump wrappers, implemented as batch-of-one. Deliberately *not* a second implementation:
// they delegate, so every scalar test is also a test of the vector code beneath it.

extension Ballistics {
    private static func one(_ x: Double) -> Tensor { Tensor(shape: [1], data: [x]) }
    private static func scalar(_ s: Solution) -> Double? {
        s.valid[0] > 0.5 ? s.value[0] : nil
    }

    public static func speed(power: Double, boosted: Bool, in w: WorldConfig) -> Double {
        speed(power: one(power), boosted: boosted, in: w)[0]
    }

    public static func minimumLandingDistance(rise h: Double, in w: WorldConfig) -> Double {
        minimumLandingDistance(rise: one(h), in: w)[0]
    }

    public static func requiredSpeed(range d: Double, rise h: Double, in w: WorldConfig) -> Double? {
        scalar(requiredSpeed(range: one(d), rise: one(h), in: w))
    }

    public static func requiredPower(range d: Double, rise h: Double,
                                     boosted: Bool, in w: WorldConfig) -> Double? {
        scalar(requiredPower(range: one(d), rise: one(h), boosted: boosted, in: w))
    }

    public static func range(speed v: Double, rise h: Double, in w: WorldConfig) -> Double? {
        scalar(range(speed: one(v), rise: one(h), in: w))
    }

    public static func criticalSpeed(rise h: Double, in w: WorldConfig) -> Double {
        criticalSpeed(rise: one(h), in: w)[0]
    }

    public static func apex(speed v: Double, in w: WorldConfig) -> Double {
        apex(speed: one(v), in: w)[0]
    }

    public static func flightTime(speed v: Double, rise h: Double, in w: WorldConfig) -> Double? {
        scalar(flightTime(speed: one(v), rise: one(h), in: w))
    }

    public static func impactSpeed(speed v: Double, rise h: Double,
                                   in w: WorldConfig) -> (horizontal: Double, vertical: Double)? {
        let (hz, vt) = impactSpeed(speed: one(v), rise: one(h), in: w)
        guard vt.valid[0] > 0.5 else { return nil }
        return (hz[0], vt.value[0])
    }

    public static func landingInset(impact: (horizontal: Double, vertical: Double),
                                    in w: WorldConfig) -> Double {
        landingInset(horizontal: one(impact.horizontal), vertical: one(impact.vertical), in: w)[0]
    }

    public static func position(speed v: Double, yaw: Double, t: Double, in w: WorldConfig) -> Vec3 {
        let p = position(speed: one(v), yaw: one(yaw), t: one(t), in: w)
        return Vec3(p.x[0], p.y[0], p.z[0])
    }

    /// The arc from `origin`, sampled for rendering. Every sample is computed in one batched call.
    public static func arc(from origin: Vec3, speed v: Double, yaw: Double, rise h: Double,
                           samples: Int, in w: WorldConfig) -> [Vec3] {
        let total = flightTime(speed: v, rise: h, in: w)
            ?? (2 * v * sin(w.launchElevation) / w.gravity)
        guard samples > 1, total > 0 else { return [origin] }

        let times = Tensor(shape: [samples],
                           data: (0..<samples).map { total * Double($0) / Double(samples - 1) })
        let speeds = Tensor(repeating: v, shape: [samples])
        let yaws = Tensor(repeating: yaw, shape: [samples])
        let p = position(speed: speeds, yaw: yaws, t: times, in: w)

        return (0..<samples).map { i in
            Vec3(origin.x + p.x[i], origin.y + p.y[i], origin.z + p.z[i])
        }
    }
}

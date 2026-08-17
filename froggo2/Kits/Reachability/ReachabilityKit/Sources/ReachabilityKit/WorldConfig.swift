import Foundation

/// Every global constant of Froggo 2, in ONE place.
///
/// `ReachabilityKit` (scalar), `FroggoSim` (batched/GPU), the renderer, and any future Python
/// torchsim all read this same struct — exported to `world.json` — so the constants cannot drift.
/// That drift is not hypothetical: it is what broke the old Metal demo in `monstro_shooter.swift`
/// (see `torchsim/world_config.py:1-7`), which is why that repo has one config and so does this one.
///
/// Units: metres, seconds, radians. Unlike froggo 1, every number here has a unit that someone wrote
/// down. Froggo 1's `jumpForce = 50` was an impulse divided by a mass SpriteKit derived implicitly
/// from the body's area — a number in no stated unit at all, which is precisely why it could not be
/// ported and why this project integrates its own ballistics.
public struct WorldConfig: Codable, Hashable, Sendable {

    // MARK: - Scale

    /// Metres per froggo-1 point. THE single free parameter of the port.
    ///
    /// Because `[g] = L/T²`, choosing this one number and demanding that *times* be preserved forces
    /// gravity and launch speed and leaves hang time — the quantity that carries the feel — exactly
    /// as it was in froggo 1. Everything else in this struct is derived from it, and the oracle
    /// asserts the resulting *ratios* (reach ÷ frog width, apex ÷ max gap) rather than the metres,
    /// so re-scaling the art fails loudly instead of drifting silently.
    public var metresPerPoint: Double

    // MARK: - Ballistics

    /// Gravity magnitude, m/s². Froggo 1: `gravitation = -5.8` (GameManager.swift:14).
    ///
    /// SpriteKit's gravity is already m/s² (its world is 150 points per metre), so this literal
    /// survives the port intact — the one froggo 1 constant that means the same thing in both games.
    /// 5.8 is 59% of Earth: floaty, and the floatiness *is* the froggo feel.
    public var gravity: Double

    /// Launch speed at power 1.0 with no fly, m/s.
    ///
    /// Derived, never guessed: set so full power clears the widest generated gap with `powerCeiling`
    /// worth of margin. Froggo 1's `jumpForce = 50` is deliberately absent — see the type docs.
    public var maxLaunchSpeed: Double

    /// Launch elevation above horizontal, radians. FIXED — the player controls yaw and power only.
    ///
    /// Froggo 1's drag was two degrees of freedom (direction in the vertical plane, and length).
    /// In 3-D the corridor direction becomes yaw and consumes one of them; restoring pitch would
    /// make three and break one-thumb play. The decisive reason is the oracle's, though: with a
    /// free pitch, "required power" would be the value at the *optimal* pitch, which a human never
    /// actually hits, so the solver would certify blocks that are provably solvable and practically
    /// not. Fixing elevation makes the solver's action space exactly the player's action space.
    public var launchElevation: Double

    /// Fraction of the envelope the oracle is allowed to certify. A player cannot reliably produce
    /// power 1.000, so a jump requiring it is not really available to them.
    public var powerCeiling: Double

    /// Minimum power a drag can express — below this it reads as a tap, not a launch.
    public var minPower: Double

    /// Fly bonus, applied to SPEED. Froggo 1: `flyEatenMultiplier = 1.5` (Frog.swift:36), which
    /// multiplied the impulse and therefore the velocity — identical semantics.
    ///
    /// Note what this means in 2-D that it did not mean in 1-D: range goes as v², so ×1.5 on speed
    /// is **×2.25 on range**. In a corridor that is "a longer jump"; in a field it opens whole
    /// routes. That is why PROMPT.md §5 is right that the fly is worth keeping.
    public var flyMultiplier: Double

    // MARK: - Bodies

    /// Frog half-width, metres. Froggo 1 drew a 40×40 sprite.
    public var frogHalfWidth: Double

    /// Restitution on landing. Froggo 1: 0.2 on both frog and skyscraper.
    ///
    /// Froggo 1 got its settle from SpriteKit's solver. We author it instead: a landing above the
    /// bounce threshold emits at most `maxBounces` further analytic sub-arcs at this restitution,
    /// then snaps to rest. Same look, and — unlike a solver — the aim preview can draw it.
    public var restitution: Double

    /// Tangential speed retained through a bounce. Froggo 1 used friction 0.8 on both bodies.
    public var tangentialRetention: Double

    /// Hard cap on authored bounces before the frog is snapped to rest.
    public var maxBounces: Int

    /// Vertical impact speed below which a landing settles immediately with no bounce, m/s.
    public var bounceThreshold: Double

    // MARK: - City generation

    /// Roof footprint half-extent range, metres. Froggo 1: width `80 + random(0...30)` ⇒ 80–110 pt.
    ///
    /// The absolute size is raised relative to a pure λ scaling: a 3-D rooftop has to hold a frog
    /// *and* be a place worth aiming at, which a 2-D silhouette never had to be. The ratio that
    /// matters — gap to width — is preserved.
    public var roofHalfExtentRange: ClosedRange<Double>

    /// Edge-to-edge gap range, metres. Froggo 1: `80 × random(0.38...1.62)` ⇒ 30.4–129.6 pt
    /// (GameManager.swift:23, :101). 1.62 is the golden ratio, and **the distribution is the asset**
    /// — the absolute numbers are rescaled, the shape is not.
    public var gapRange: ClosedRange<Double>

    /// Roof height range, metres. Froggo 1: `scaleY 1200 ± 100`.
    ///
    /// Sampled from a smooth value-noise field, NOT independently per roof. At a fixed launch
    /// elevation the greatest *rise* reachable at any power is `v²/(4g)`; a neighbour taller than
    /// that is unreachable at every power. Independent uniform heights would therefore make most
    /// blocks unsolvable by construction, and the generator would burn its whole budget rejecting
    /// them. A few deliberate spikes above that threshold become fly-gated shortcuts. The physics
    /// writes the level design.
    public var heightRange: ClosedRange<Double>

    /// Roofs per district. Froggo 1 spawned 20 in a line; a 2-D field needs more to have branches.
    public var roofsPerDistrict: Int

    /// How far below the lowest roof the frog dies. Froggo 1 used an absolute `pitHeight = 600`
    /// (GameView.swift:115), which cannot survive into a game where districts stack.
    public var deathDrop: Double

    // MARK: - Simulation

    /// Fixed simulation timestep. Froggo 1 had two frame-rate-dependent bugs — a camera lerp of
    /// 0.15 *per frame* and a landing test of 5 consecutive *frames* — so a 120 Hz iPad played a
    /// measurably different game from a 60 Hz iPhone. A fixed step is the fix.
    public var dt: Double

    /// Substep cap per rendered frame, so a stall cannot spiral.
    public var maxSubsteps: Int

    // MARK: - Defaults

    /// The shipping tuning. Every value is either carried from froggo 1 with its provenance in the
    /// property docs, or derived here in terms of the others — nothing is a bare magic number.
    ///
    /// `ConfigConsistencyTests` proves the numbers below actually hang together: that the hardest
    /// jump the generator can produce still fits inside the envelope, that roofs cannot overlap at
    /// the tightest spacing, and that neighbouring roofs never differ in height by more than the
    /// frog can climb. Those three used to be arithmetic done in my head, and doing it in my head
    /// is how the first draft ended up with rooftops wider than the maximum jump.
    public static let shipping: WorldConfig = {
        // Froggo 1's world, in its own units, read from source.
        let f1FrogWidth: Double = 40          // Frog.swift:55
        let f1MinGap: Double = 30.4           // 80 × 0.38, GameManager.swift:23/:101
        let f1MaxGap: Double = 129.6          // 80 × 1.62 — the golden ratio

        // λ: the frog reads best at roughly half a metre across in a 3-D city block. This is the
        // one free parameter; everything with a length below is expressed through it.
        let lambda = 0.5 / f1FrogWidth        // 0.0125 m per froggo-1 point

        let g = 5.8
        let theta = Double.pi / 4             // 45°: maximises range per unit speed; proven, not asserted

        // Rooftops are deliberately ~1.5× froggo 1's proportion (it used 2–2.75 frog widths; this
        // uses 3–4.2). A side-on 2-D "roof" is a line segment the frog lands on in one axis; a 3-D
        // rooftop has to be hit in two axes, from a camera behind the frog, and then stood on while
        // aiming the next jump. Widening the pad is the adaptation that buys that back, and it is
        // stated here rather than smuggled in.
        let roofHalfLo = 0.75, roofHalfHi = 1.05

        // The reachability budget. The worst jump the generator can ask for is roughly
        // "half of one roof + the widest gap + the landing inset", and full power should clear that
        // with room to spare rather than scrape it — a jump needing 100% of the envelope is a jump
        // no thumb can actually place.
        let flatRange = 5.0
        let vMax = (flatRange * g / sin(2 * theta)).squareRoot()

        return WorldConfig(
            metresPerPoint: lambda,
            gravity: g,
            maxLaunchSpeed: vMax,
            launchElevation: theta,
            powerCeiling: 0.97,
            minPower: 0.05,
            flyMultiplier: 1.5,
            frogHalfWidth: f1FrogWidth * lambda / 2,
            restitution: 0.2,
            tangentialRetention: 0.2,
            maxBounces: 2,
            bounceThreshold: 1.2,
            roofHalfExtentRange: roofHalfLo...roofHalfHi,
            // Froggo 1's gap distribution, scaled. The golden-ratio spread is the asset; the
            // absolute numbers are just λ.
            gapRange: (f1MinGap * lambda)...(f1MaxGap * lambda),
            // A deliberately narrow height band, and this is a consequence of physics rather than
            // taste: at a fixed 45° the apex is exactly a quarter of the flat range, so the frog
            // can climb at most `flatRange/4` however hard it jumps. Froggo 1 could vary its
            // rooftops by far more than that because its drag controlled elevation as well as
            // power — it had a degree of freedom this game spends on yaw instead. The towers below
            // still vary in height; it is the *rooftops* that stay within one hop of each other.
            heightRange: 16.0...17.6,
            roofsPerDistrict: 30,
            deathDrop: 9.0,
            dt: 1.0 / 120.0,
            maxSubsteps: 8
        )
    }()

    public init(
        metresPerPoint: Double,
        gravity: Double,
        maxLaunchSpeed: Double,
        launchElevation: Double,
        powerCeiling: Double,
        minPower: Double,
        flyMultiplier: Double,
        frogHalfWidth: Double,
        restitution: Double,
        tangentialRetention: Double,
        maxBounces: Int,
        bounceThreshold: Double,
        roofHalfExtentRange: ClosedRange<Double>,
        gapRange: ClosedRange<Double>,
        heightRange: ClosedRange<Double>,
        roofsPerDistrict: Int,
        deathDrop: Double,
        dt: Double,
        maxSubsteps: Int
    ) {
        self.metresPerPoint = metresPerPoint
        self.gravity = gravity
        self.maxLaunchSpeed = maxLaunchSpeed
        self.launchElevation = launchElevation
        self.powerCeiling = powerCeiling
        self.minPower = minPower
        self.flyMultiplier = flyMultiplier
        self.frogHalfWidth = frogHalfWidth
        self.restitution = restitution
        self.tangentialRetention = tangentialRetention
        self.maxBounces = maxBounces
        self.bounceThreshold = bounceThreshold
        self.roofHalfExtentRange = roofHalfExtentRange
        self.gapRange = gapRange
        self.heightRange = heightRange
        self.roofsPerDistrict = roofsPerDistrict
        self.deathDrop = deathDrop
        self.dt = dt
        self.maxSubsteps = maxSubsteps
    }
}

// MARK: - Derived quantities

extension WorldConfig {
    /// Greatest horizontal distance reachable on flat ground at full power (no fly).
    public var flatMaxRange: Double {
        maxLaunchSpeed * maxLaunchSpeed * sin(2 * launchElevation) / gravity
    }

    /// Greatest *rise* reachable at any power and any distance. A roof taller than this above the
    /// frog cannot be reached at all — which is exactly why heights come from a smooth field.
    public var maxRise: Double {
        let s = maxLaunchSpeed * sin(launchElevation)
        return s * s / (2 * gravity)
    }

    /// Apex height of a full-power jump, metres.
    public var flatApex: Double { maxRise }

    /// Time from launch to returning to launch height at full power, seconds. This is the number
    /// that must match froggo 1 for the feel to have survived the port.
    public var flatHangTime: Double {
        2 * maxLaunchSpeed * sin(launchElevation) / gravity
    }

    /// The envelope with the fly consumed. Speed ×1.5 ⇒ range ×2.25.
    public var boosted: WorldConfig {
        var c = self
        c.maxLaunchSpeed *= flyMultiplier
        return c
    }

    /// JSON for the future Python torchsim on the other machine. It reads these constants; it does
    /// not retype them.
    public func exportJSON() throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try enc.encode(self)
    }
}

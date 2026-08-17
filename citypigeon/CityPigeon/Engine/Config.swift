import Foundation

/// Every constant of City Pigeon, in one place, `Codable` so the engine, the renderer, the headless
/// batch harness and any offline tooling read the same numbers instead of retyping them.
///
/// **Double at rest, Float32 at the kernel boundary.** MLX has no Float64, but the tuning derivations
/// below involve differences of similar magnitudes and deserve the headroom; the conversion happens
/// once, where the arrays are built.
///
/// The discipline, inherited from `froggo2/…/WorldConfig.swift`: a value is either a **free
/// parameter chosen for feel**, or it is **derived from those in terms stated here**. There are no
/// bare magic numbers, because a number nobody can re-derive is a number nobody can safely change.
public struct WorldConfig: Codable, Hashable, Sendable {

    // MARK: - Free parameters, chosen for feel

    /// Real gravity. The game is a bombsight and reads as one; a stylised `g` would make the arc
    /// look wrong to anyone who has ever dropped something.
    public var gravity: Double = 9.8

    /// The pigeon's nominal cruise height above the street.
    ///
    /// 18 m, not 30. At 30 the uncharged hang time is 2.4 s, which makes every lead long (30 m),
    /// every spawn gap large, and the whole game feel slow — and it pushed oncoming traffic outside
    /// what the camera can show, which `SpawnOracleTests` caught as "no on-screen spawn gap exists".
    /// Altitude is the parameter that scales all of those at once.
    public var cruiseAltitude: Double = 18.0

    /// Nominal forward speed. **Must be > 0**: every envelope corner below carries `sign(v_x)`, and
    /// the whole lead model degenerates at zero.
    public var cruiseSpeed: Double = 12.0

    /// How much of the uncharged flight time a full charge removes.
    ///
    /// This is *the* feel parameter — it alone decides how much authority the charge meter has, and
    /// `maxChargeSpeed` is derived from it rather than the other way round.
    ///
    /// The charge range contributes `(T_max − T_min)` directly to every firing window, so widening
    /// it widens every window at once — which is how the pedestrian fairness failure was fixed.
    public var fullChargeTimeRatio: Double = 0.38

    /// Seconds of holding to reach full charge.
    public var chargeTime: Double = 0.9

    /// A player cannot reliably produce 0.000 or 1.000, so a shot that needs either is not really
    /// available to them. Same argument as froggo2's `powerCeiling`.
    public var chargeFloor: Double = 0.03
    public var chargeCeiling: Double = 0.97

    /// Fixed simulation step. **Never a frame delta.** 60 Hz, not 120: the measured MLX step is
    /// ~2.9 ms and launch-bound, which is 17% of a 60 Hz frame and 35% of a 120 Hz one.
    public var dt: Double = 1.0 / 60.0

    // MARK: - The pigeon's state box

    /// Where the player may actually fly. Wide, because movement should feel free — but bounded by
    /// the camera: the predicted impact point must stay on screen at every corner of this box, or
    /// the reticle leaves the frame. The first draft used 20…40 m × 8…16 m/s and put the reticle
    /// 57.7 m ahead against a 45 m camera. That is what `testTheImpactPointIsAlwaysOnScreen` is for.
    public var altitudeRange: ClosedRange<Double> = 12.0...24.0
    public var forwardSpeedRange: ClosedRange<Double> = 9.0...15.0
    public var climbRateRange: ClosedRange<Double> = -5.0...5.0

    /// The sub-box the **spawn guarantee** is computed over, and the reason it exists.
    ///
    /// The guaranteed-reachable set is an *intersection* over pigeon states — leads reachable from
    /// **every** admissible state — and it shrinks as the box widens. Over the full box above it is
    /// empty: at altitude 24…36 with `v_x` 10…14 the intersection endpoints come out `A = 19.9 m`
    /// against `B = 18.3 m`, i.e. inverted. A guarantee over the whole box would therefore be a
    /// guarantee about nothing.
    ///
    /// So the spawner guarantees hittability from this **nominal band**, and the player may leave it.
    /// Outside it a shot is harder, not impossible — the *hull* (the union) still covers most of the
    /// wider box. This is the honest split: a real guarantee over a stated region beats a vacuous
    /// one over everything.
    public var guaranteeAltitudeRange: ClosedRange<Double> = 16.0...20.0
    public var guaranteeSpeedRange: ClosedRange<Double> = 11.5...12.5
    public var guaranteeClimbRange: ClosedRange<Double> = -1.5...1.5

    /// Recoil applied to the pigeon's forward velocity on release.
    ///
    /// Not flavour. With no drag and the payload inheriting `v_x`, the payload lands exactly beneath
    /// the pigeon at impact for every charge — the bombsight identity. The camera tracks the pigeon,
    /// so without this the payload falls straight down the screen and the charge meter looks inert.
    /// The payload's `v_x` is frozen at release, so this changes no ballistic formula anywhere.
    public var releaseRecoil: Double = -1.6

    // MARK: - Payload and targets

    /// Raised from 0.6 because the hit radius `halfLength + splatRadius` is what buys window
    /// duration against fast-closing targets — `2r/|Δv|` — and a pedestrian is only 0.35 m wide, so
    /// the splat is most of their hit radius. A bigger splat also reads better at this camera
    /// distance. **Constant per kind pair, never a function of charge:** if `r` grew with charge,
    /// the hit set `{c : |f(c)| ≤ r(c)}` could stop being an interval and the two-endpoint inversion
    /// would silently return the wrong answer.
    public var splatRadius: Double = 0.8
    public var payloadSlots: Int = 8
    public var targetSlots: Int = 24

    // Oncoming speed is capped by the camera, not by taste: a car closing at Δv needs to appear
    // `Δv·(T_max + preVisibility) + r` metres ahead, and that must fit on screen.
    public var car = TargetProfile(topY: 1.45, halfLength: 2.2, points: 100,
                                   speedRange: -10.0...6.0)
    public var pedestrian = TargetProfile(topY: 1.75, halfLength: 0.35, points: 250,
                                          speedRange: -1.6...1.6)

    /// Two targets closer than this make a hit ambiguous and scoring arbitrary.
    public var minTargetSeparation: Double = 6.0

    // MARK: - Fairness

    /// Fairness is **two separate requirements**, and conflating them was a modelling error.
    ///
    /// Charging does not happen inside the window — the player watches a target approach and charges
    /// while it does. So the window itself only has to contain *react + cooldown*, while *charge
    /// time* is a requirement on how long the target is *visible before* its window opens. Demanding
    /// all three inside the window made pedestrians unhittable on paper while being obviously
    /// hittable in practice.
    public var reactionLatency: Double = 0.25
    public var shotCooldown: Double = 0.30
    // `minFiringWindow` is deliberately NOT authored here — see `minFairWindow` below.

    /// The window has zero charge-width at both edges (tangency), so raw duration overstates
    /// fairness. This is the second, independent axis.
    public var minChargeWindow: Double = 0.08

    /// How far ahead of the pigeon the camera shows. A window that opens off-screen is not a window.
    /// 58 ahead + 22 behind = 80 m of street. At 16:9 that is a 45 m tall frame, comfortably above
    /// the 24 m altitude ceiling — so the camera framing is a consequence of the state box and the
    /// hull, not an independent guess.
    public var visibleAheadOfPigeon: Double = 58.0
    public var cullBehindPigeon: Double = -22.0

    // MARK: - Other pigeons

    /// The airspace is shared. Other pigeons cross it in both directions and hitting one ends the
    /// run — the only fail state in the game, and the thing that gives an endless score-chaser
    /// something to lose.
    public var flockSlots: Int = 8
    /// How many are airborne at once. The owner asked for this to be configurable at both ends.
    public var minFlock: Int = 1
    public var maxFlock: Int = 4

    /// Speed **relative to the pigeon**, not an absolute airspeed. This is the fix for two problems
    /// the first version had:
    ///
    /// * An absolute 3–9 m/s against the pigeon's 12 meant same-direction birds drifted backwards at
    ///   only 3 m/s and read as very nearly **stationary** on screen.
    /// * Nothing ever came from behind, because a bird slower than the pigeon can never catch it —
    ///   it would sit off the back edge forever.
    ///
    /// Expressed relatively, every bird has visible motion against the camera by construction, and
    /// "from behind" simply means `cruiseSpeed + magnitude`.
    public var flockSpeedRange: ClosedRange<Double> = 3.0...9.0

    /// Head-on: `v = −magnitude`. Closes fastest, so it is the population that makes altitude matter.
    public var flockOncomingShare: Double = 0.45
    /// Overtaking from behind: `v = cruiseSpeed + magnitude`. Spawns just inside the rear edge of the
    /// camera, so it is visible for the whole approach — a hazard arriving from off-screen behind the
    /// player would be unfair, and the cull boundary is what keeps it honest.
    public var flockFromBehindShare: Double = 0.25
    // The remainder are slower birds ahead, at `cruiseSpeed − magnitude`, which the pigeon runs down.

    /// How far above or below the pigeon a bird may enter, rather than anywhere in the altitude band.
    ///
    /// Spread across the full 12 m band, most birds passed nowhere near the player: a pilot that
    /// never dodged still survived 8 of 10 runs, so the flock was decoration that cost frame budget.
    /// Entering near the player's current altitude makes most of them *relevant* — near misses and
    /// real threats — without making them homing: the altitude is fixed at spawn, so climbing away
    /// still works and the dodge remains a dodge.
    public var flockAltitudeSpread: Double = 4.5

    public var flockRadiusX: Double = 1.1
    public var flockRadiusY: Double = 0.9
    /// The player's own hitbox. Generous relative to the drawn bird: a near miss that reads as a
    /// near miss should be one, and a collision the player could not see coming is worse than a
    /// collision they could have avoided.
    public var pigeonHalfWidth: Double = 1.0
    public var pigeonHalfHeight: Double = 0.7

    // MARK: - Anti-spam

    public var ammoCapacity: Double = 4
    public var ammoRegenPerSecond: Double = 0.5
    public var maxMultiplier: Double = 8

    public init() {}
}

/// A target kind. `topY` is the impact plane — **a car roof is not the street**, and using the street
/// for both inflates the computed lead by roughly a third of a car's half-length.
public struct TargetProfile: Codable, Hashable, Sendable {
    public var topY: Double
    public var halfLength: Double
    public var points: Double
    /// Signed along +x. Derived bounds are applied by the spawner; this is the authored envelope.
    public var speedRange: ClosedRange<Double>
}

// MARK: - Derived quantities
//
// Nothing below is authored. Each is a consequence of the free parameters above, and each has a
// ConfigDerivationTests assertion proving it lands where the feel argument says it should.

extension WorldConfig {

    /// Uncharged flight time from a drop of `H` with signed upward release velocity `u`.
    ///
    /// The **numerically stable** two-branch root. `T = (u + √D)/g` is the *cancelling* form exactly
    /// where the game lives: a charged shot has `u < 0`, and `√(u² + 2gH) → |u|` as `2gH/u² → 0`, so
    /// the numerator is a difference of near-equal numbers. The `u < 0` branch multiplies through by
    /// the conjugate instead — `2H/(√D − u)`, whose denominator is a *sum* of positives whenever
    /// `H > 0` and therefore never cancels.
    ///
    /// Returns nil where `H ≤ 0`. That is not tidiness: with `H < 0` (a plane *above* the release
    /// point — a truck roof the pigeon is flying below) the `+` root is the **wrong crossing**. It
    /// reports an impact the payload only reaches after passing through the body.
    public func flightTime(drop H: Double, releaseVelocity u: Double) -> Double? {
        guard H > 0 else { return nil }
        let D = u * u + 2 * gravity * H
        guard D >= 0 else { return nil }
        let root = D.squareRoot()
        return u >= 0 ? (u + root) / gravity : 2 * H / (root - u)
    }

    /// The exact inverse, `u = gT/2 − H/T`.
    ///
    /// This is also the *proof* that `flightTime` is strictly increasing in `u`, and a better one
    /// than differentiating `T`: `du/dT = g/2 + H/T² > 0` for `H > 0`, so `u(T)` is a smooth strictly
    /// increasing bijection `(0,∞) → ℝ` with non-vanishing derivative, and the inverse function
    /// theorem does the rest — with **no case analysis for `u < 0`**, which is where a derivative
    /// argument on `T` gets uncomfortable.
    public func releaseVelocity(flightTime T: Double, drop H: Double) -> Double? {
        guard T > 0, H > 0 else { return nil }
        return gravity * T / 2 - H / T
    }

    /// Flight time at zero charge from a drop of `H`, given the pigeon's climb rate.
    public func unchargedTime(drop H: Double, climb vy: Double) -> Double? {
        flightTime(drop: H, releaseVelocity: vy)
    }

    /// Flight time at full charge.
    public func fullChargeTime(drop H: Double, climb vy: Double) -> Double? {
        flightTime(drop: H, releaseVelocity: vy - maxChargeSpeed)
    }

    /// **Charge is linear in flight time, not in imparted speed.**
    ///
    /// A linear speed ramp would put nearly all the change in the first third of the meter: as charge
    /// rises `dT/du` collapses, so the top of the travel does almost nothing. Interpolating the
    /// *time* instead gives a perfectly even response and makes the meter altitude-relative, at no
    /// cost to any proof — composition with a strictly increasing reparametrisation preserves every
    /// monotonicity result.
    public func flightTime(drop H: Double, climb vy: Double, charge c: Double) -> Double? {
        guard let t0 = unchargedTime(drop: H, climb: vy),
              let t1 = fullChargeTime(drop: H, climb: vy) else { return nil }
        return (1 - c) * t0 + c * t1
    }

    /// The charge that produces a given flight time. Strictly decreasing in `T`.
    public func charge(flightTime T: Double, drop H: Double, climb vy: Double) -> Double? {
        guard let t0 = unchargedTime(drop: H, climb: vy),
              let t1 = fullChargeTime(drop: H, climb: vy),
              abs(t0 - t1) > 1e-12 else { return nil }
        return (t0 - T) / (t0 - t1)
    }

    /// The uncharged drop time at cruise — the number that carries the feel.
    public var cruiseDropTime: Double {
        unchargedTime(drop: cruiseAltitude - car.topY, climb: 0) ?? .nan
    }

    /// **Derived, not authored.** `maxChargeSpeed` is whatever makes a full charge hit
    /// `fullChargeTimeRatio` of the uncharged time at cruise, recovered through the exact inverse.
    public var maxChargeSpeed: Double {
        let H = cruiseAltitude - car.topY
        let t0 = (2 * H / gravity).squareRoot()          // uncharged, level flight
        let target = fullChargeTimeRatio * t0
        // u = gT/2 − H/T at the target time; V is how far below the pigeon's own vy that sits.
        let u = gravity * target / 2 - H / target
        return -u
    }

    /// How far the impact point swings across the charge range at cruise. The charge meter's
    /// authority, in metres, and the number that decides whether it reads as doing anything.
    public var chargeAuthority: Double {
        let H = cruiseAltitude - car.topY
        guard let t0 = unchargedTime(drop: H, climb: 0),
              let t1 = fullChargeTime(drop: H, climb: 0) else { return .nan }
        return cruiseSpeed * (t0 - t1)
    }

    /// Whether holding longer makes the payload land later (`> 0`) or **sooner** (`< 0`), per second
    /// of hold. This is `dG/dτ` where `G(τ) = τ + T(c(τ))` is impact time as a function of release
    /// time — the quantity `Interception.releaseWindow` inverts.
    ///
    /// **It is a constant**, and that is the whole reason release timing is closed form: charge is
    /// linear in flight time and linear in hold time, so their composition is affine in τ.
    ///
    /// The previous version of this property computed `1 − (V/t_charge)/(dU/dT)`, which is `G′` for a
    /// **linear-in-speed** charge ramp — the model this engine abandoned when charge became linear in
    /// flight time. It reported a sign flip across the charge range (−1.30 → +0.42) that the shipped
    /// model does not have, and a test pinned that flip as though it were behaviour. Both were
    /// describing a game that no longer existed.
    public var impactTimeSlope: Double {
        let H = cruiseAltitude - car.topY
        guard let t0 = unchargedTime(drop: H, climb: 0),
              let t1 = fullChargeTime(drop: H, climb: 0) else { return .nan }
        return 1 - (t0 - t1) / chargeTime
    }

    /// How far the landing point moves per second of holding, in metres — the **effective** authority
    /// of the charge meter, as opposed to the nominal `chargeAuthority`.
    ///
    /// These differ by much more than they look: nominal assumes you could change charge without
    /// spending time, but holding also flies you forward. Measured end-to-end, 13.0 m of nominal
    /// authority nets out to 1.85 m of effective movement across a full hold.
    public var effectiveAuthorityPerSecond: Double { cruiseSpeed * impactTimeSlope }

    /// Collision half-extents: both bodies' radii summed, which is what an overlap test needs.
    public var crashRadiusX: Double { pigeonHalfWidth + flockRadiusX }
    public var crashRadiusY: Double { pigeonHalfHeight + flockRadiusY }

    /// How long it takes to climb or dive clear of a bird on a collision line, at full climb rate.
    public var flockDodgeTime: Double { crashRadiusY / climbRateRange.upperBound }

    /// The fastest a bird may close and still be **dodgeable**: seen, reacted to, and climbed clear
    /// of before it arrives. Derived from the camera depth the same way the target spawner's band is.
    public var maxFlockClosingSpeed: Double {
        visibleAheadOfPigeon / (reactionLatency + flockDodgeTime)
    }

    /// The worst case the authored speeds can actually produce — a head-on bird at full tilt met by
    /// the pigeon at its top speed. The other two populations close at `magnitude` alone, which is
    /// strictly smaller.
    public var worstFlockClosingSpeed: Double {
        forwardSpeedRange.upperBound + flockSpeedRange.upperBound
    }

    public var minFairWindow: Double { reactionLatency + shotCooldown }

    /// What must elapse **before** the window opens, with the target already on screen and closing:
    /// long enough to see it and to have charged for it.
    public var minPreVisibility: Double { reactionLatency + chargeTime }

    public func hitRadius(_ p: TargetProfile) -> Double { p.halfLength + splatRadius }

    public static let shipping = WorldConfig()

    public func exportJSON() throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try e.encode(self)
    }
}

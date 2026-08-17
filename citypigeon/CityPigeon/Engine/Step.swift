import Foundation
import MLX

/// The one kernel. Everything the game does in a tick happens here, elementwise, once.
///
/// There is **no loop** in this file — not over worlds, not over payload slots, not over targets.
/// The only iteration is inside MLX's own primitives. `VectorDisciplineTests` enforces that by
/// scanning the source, so the property survives future edits rather than depending on care.
///
/// Two idioms carry the whole thing:
///
///  * **Fixed capacity plus an alive mask** replaces every variable-length list. To spawn, find the
///    first free slot with `argMax` over the mask, one-hot it, and write with `which`. A one-hot
///    `which` *is* a scatter, at fixed cost and with no resizing.
///  * **Resolve at release, not at impact.** When a payload spawns, its impact time and its victim
///    are computed in closed form immediately and stored. Nothing is swept per frame looking for
///    overlaps, so a fast payload cannot tunnel through a thin car between two frames, and the
///    result cannot depend on the frame rate. The precondition this buys is worth stating: a
///    target's velocity must be constant for its lifetime, which the spawner guarantees.
public enum Step {

    public static func advance(_ w: inout World, intent: Intent) {
        let c = w.config
        let B = w.batch, P = w.payloadSlots, M = w.targetSlots, K = w.flockSlots
        let dt = Float(c.dt)
        let t = Float(w.frame) * dt

        // ── 1. Pigeon ────────────────────────────────────────────────────────────────────────
        // Velocity approaches the intent rather than snapping to it. That exponential approach is
        // the whole difference between flight and a cursor.
        let approach = Float(1 - exp(-8.0 * c.dt))
        let spanX = Float((c.forwardSpeedRange.upperBound - c.forwardSpeedRange.lowerBound) / 2)
        let wantVX = MLXArray(Float(c.cruiseSpeed)) + intent.moveX * spanX
        let wantVY = intent.moveY * Float(c.climbRateRange.upperBound)

        // A dead world freezes. Gating movement rather than skipping the step keeps every world in
        // a batch on the same code path — there is no "some worlds are finished" branch anywhere.
        let live = which(w.alive, MLXArray(Float(1)), MLXArray(Float(0)))

        w.pigeonVX = w.pigeonVX + (wantVX - w.pigeonVX) * approach * live
        w.pigeonVY = w.pigeonVY + (wantVY - w.pigeonVY) * approach * live
        w.pigeonX = w.pigeonX + w.pigeonVX * dt * live

        let rawY = w.pigeonY + w.pigeonVY * dt * live
        let clampedY = clip(rawY, min: MLXArray(Float(c.altitudeRange.lowerBound)),
                            max: MLXArray(Float(c.altitudeRange.upperBound)))
        // Bleed vertical speed when the ceiling or floor is hit, or the pigeon "sticks" there with
        // stored velocity and lurches when the player reverses.
        w.pigeonVY = which(notEqual(rawY, clampedY), MLXArray(Float(0)), w.pigeonVY)
        w.pigeonY = clampedY

        // ── 2. Charge, ammo, and the release edge ────────────────────────────────────────────
        w.ammo = minimum(w.ammo + Float(c.ammoRegenPerSecond * c.dt), MLXArray(Float(c.ammoCapacity)))

        let wasHolding = w.holding
        let charging = logicalAnd(intent.hold, greaterEqual(w.ammo, 1))

        // **Capture the held charge BEFORE the update zeroes it.**
        //
        // This line is the fix for a bug that shipped in v1 and made the charge meter decorative.
        // The previous version read `which(charging, w.charge, w.charge)` — an identity, both
        // branches the same array — *after* the update below had already written 0 into `w.charge`
        // on the release frame. Since a release edge is by definition a frame where `charging` is
        // false, every shot in the game left at `clip(0, floor, ceiling) == chargeFloor`.
        //
        // It scored anyway, which is why nothing caught it: the guarantee band makes windows wide
        // enough that a minimum-charge drop still lands often. `testTheAutopilotReliablyScores` only
        // asserted `score > 0`, so a game where the charge meter did nothing looked exactly like a
        // game where it worked.
        let heldCharge = w.charge

        w.charge = which(charging,
                         minimum(heldCharge + dt / Float(c.chargeTime), MLXArray(Float(1))),
                         MLXArray(Float(0)))
        let releasedCharge = heldCharge
        let releaseEdge = logicalAnd(logicalAnd(logicalAnd(wasHolding, logicalNot(intent.hold)),
                                                greaterEqual(w.ammo, 1)), w.alive)
        w.holding = charging

        // The charge the payload actually leaves with. Clamped into the usable domain because the
        // extremes are not reliably producible and every guarantee is computed inside them.
        let usedCharge = clip(releasedCharge, min: MLXArray(Float(c.chargeFloor)),
                              max: MLXArray(Float(c.chargeCeiling)))

        // ── 3. Spawn a payload into the first free slot ──────────────────────────────────────
        let freeF = which(w.payAlive, MLXArray(Float(0)), MLXArray(Float(1)))
        let anyFree = greater(freeF.max(axis: 1), 0.5)
        let firstFree = freeF.argMax(axis: 1)
        let slotLane = MLXArray.arange(P, dtype: .int32).expandedDimensions(axis: 0)
        let slotMask = logicalAnd(equal(firstFree.expandedDimensions(axis: 1), slotLane),
                                  logicalAnd(releaseEdge, anyFree).expandedDimensions(axis: 1))

        // Charge is defined as a flight time to the STREET, and the release velocity follows from
        // it. Using the street as the reference plane keeps the mapping independent of whatever the
        // payload eventually lands on.
        let tToStreet = Drop.flightTime(drop: w.pigeonY, climb: w.pigeonVY, charge: usedCharge, in: c)
        let u0 = Drop.releaseVelocity(flightTime: tToStreet.value, drop: w.pigeonY, in: c)

        // `which` broadcasts its operands, so a column vector suffices — an explicit `broadcast` to
        // [B, P] would be one more operation per field for the same result, and operation count is
        // what this step costs.
        let col = { (a: MLXArray) in a.expandedDimensions(axis: 1) }
        w.payX0 = which(slotMask, col(w.pigeonX), w.payX0)
        w.payY0 = which(slotMask, col(w.pigeonY), w.payY0)
        w.payVX0 = which(slotMask, col(w.pigeonVX), w.payVX0)
        w.payU0 = which(slotMask, col(u0.value), w.payU0)
        w.payT0 = which(slotMask, MLXArray(t), w.payT0)
        w.payMass = which(slotMask, col(usedCharge), w.payMass)

        let spawned = which(slotMask, MLXArray(Float(1)), MLXArray(Float(0)))
        w.payAlive = logicalOr(w.payAlive, slotMask)
        w.ammo = w.ammo - which(logicalAnd(releaseEdge, anyFree), MLXArray(Float(1)), MLXArray(Float(0)))
        w.droppedReleases = w.droppedReleases
            + which(logicalAnd(releaseEdge, logicalNot(anyFree)), MLXArray(Float(1)), MLXArray(Float(0)))

        // The pigeon is shoved forward by the release. Purely so the payload visibly separates from
        // the bird — the payload's own velocity was frozen a line above, so no formula is affected.
        w.pigeonVX = w.pigeonVX
            + which(logicalAnd(releaseEdge, anyFree), MLXArray(Float(c.releaseRecoil)), MLXArray(Float(0)))

        // ── 4. Resolve the impact at release, over the [B, P, M] cube ────────────────────────
        let payU = w.payU0.expandedDimensions(axis: 2)          // [B,P,1]
        let payY = w.payY0.expandedDimensions(axis: 2)
        let payXs = w.payX0.expandedDimensions(axis: 2)
        let payVX = w.payVX0.expandedDimensions(axis: 2)
        let payT = w.payT0.expandedDimensions(axis: 2)

        // Per-kind constants are DERIVED from the one stored flag rather than stored per field.
        // Four fewer [B, M] arrays to write at spawn, to carry, and to evaluate every frame.
        let ped = w.tgtIsPedestrian.expandedDimensions(axis: 1)     // [B,1,M]
        let lerpKind = { (car: Double, pd: Double) in
            MLXArray(Float(car)) + ped * Float(pd - car)
        }
        let tgtTop = lerpKind(c.car.topY, c.pedestrian.topY)
        let tgtRad = lerpKind(c.hitRadius(c.car), c.hitRadius(c.pedestrian))

        let drop = payY - tgtTop
        let flight = Drop.flightTime(releaseVelocity: payU, drop: drop, in: c)

        let impactAt = payT + flight.value
        let payloadX = payXs + payVX * flight.value
        let targetX = w.tgtX0.expandedDimensions(axis: 1)
            + w.tgtV.expandedDimensions(axis: 1) * (impactAt - w.tgtT0.expandedDimensions(axis: 1))
        let within = lessEqual(abs(payloadX - targetX), tgtRad)

        let hit = logicalAnd(logicalAnd(flight.valid, within),
                             logicalAnd(w.payAlive.expandedDimensions(axis: 2),
                                        w.tgtAlive.expandedDimensions(axis: 1)))

        // Earliest impact wins: a payload strikes the first thing in its path, not all of them.
        let far = MLXArray(Float(1e9))
        let candidate = which(hit, flight.value, far)
        let soonest = candidate.min(axis: 2)                    // [B,P]
        let victim = candidate.argMin(axis: 2).asType(.float32)
        let hitsSomething = less(soonest, 1e8)

        // Payloads that hit nothing land on the road; give them a real impact time so the slot is
        // always recycled deterministically and can never leak.
        let toRoad = Drop.flightTime(releaseVelocity: w.payU0, drop: w.payY0, in: c)
        let flightUsed = which(hitsSomething, soonest, toRoad.value)

        let newSpawn = greater(spawned, 0.5)
        w.payImpactTime = which(newSpawn, w.payT0 + flightUsed, w.payImpactTime)
        w.payImpactX = which(newSpawn, w.payX0 + w.payVX0 * flightUsed, w.payImpactX)
        w.payVictim = which(newSpawn, which(hitsSomething, victim, MLXArray(Float(-1))), w.payVictim)

        // ── 5. Arrivals and scoring ──────────────────────────────────────────────────────────
        let arrived = logicalAnd(w.payAlive, greaterEqual(MLXArray(t), w.payImpactTime))
        let targetLane = MLXArray.arange(M, dtype: .float32).expandedDimensions(axis: 0)
            .expandedDimensions(axis: 0)                                        // [1,1,M]
        let struckBy = logicalAnd(equal(w.payVictim.expandedDimensions(axis: 2), targetLane),
                                  arrived.expandedDimensions(axis: 2))          // [B,P,M]
        // ANY over payloads, not SUM. Two payloads landing on one car in the same frame must score
        // once, or a shotgun of cheap drops pays out twice for one target.
        let struck = greater(which(struckBy, MLXArray(Float(1)), MLXArray(Float(0))).max(axis: 1), 0.5)

        let hitAnything = greater(which(struck, MLXArray(Float(1)), MLXArray(Float(0))).max(axis: 1), 0.5)
        let whiffed = logicalAnd(arrived, less(w.payVictim, 0)).max(axis: 1)

        w.multiplier = which(hitAnything, minimum(w.multiplier + 1, MLXArray(Float(c.maxMultiplier))),
                             which(whiffed, MLXArray(Float(1)), w.multiplier))
        let points = MLXArray(Float(c.car.points))
            + w.tgtIsPedestrian * Float(c.pedestrian.points - c.car.points)
        let gained = (which(struck, points, MLXArray(Float(0))).sum(axis: 1)) * w.multiplier * live
        w.score = w.score + gained
        w.lastGained = gained

        w.tgtHitAt = which(logicalAnd(struck, logicalNot(w.tgtHit)), MLXArray(t), w.tgtHitAt)
        w.tgtHit = logicalOr(w.tgtHit, struck)
        w.payAlive = logicalAnd(w.payAlive, logicalNot(arrived))

        // Every random number this frame needs, in ONE hash — drawn here because both the flock
        // phase and the traffic phase below consume lanes from it.
        let rolls = Rng.uniforms(batch: B, lanes: 8, seed: w.seed, frame: w.frame)

        // ── 6. Recycle every slot whose entity has left the window ───────────────────────────
        //
        // One rule for every entity kind: alive means on screen. Slots are fixed-capacity, so
        // nothing can leak memory — what leaks is *availability*, and a slot that never frees is one
        // the spawner can never reuse. The symptom is not a crash but a world that quietly stops
        // producing traffic, which is exactly the kind of failure that survives a play-test.
        let behind = MLXArray(Float(c.cullBehindPigeon))
        let ahead = MLXArray(Float(c.visibleAheadOfPigeon + Step.cullMargin))
        let px = w.pigeonX.expandedDimensions(axis: 1)

        let tgtNow = w.tgtX0 + w.tgtV * (MLXArray(t) - w.tgtT0)
        let tgtGap = tgtNow - px
        w.tgtAlive = logicalAnd(w.tgtAlive,
                                logicalAnd(greater(tgtGap, behind), less(tgtGap, ahead)))

        // For payloads this is a BACKSTOP, not a mechanism: every payload already has a scheduled
        // impact (a road fallback when it strikes nothing), and `FlockAndSlotTests` asserts this cull
        // never actually fires in normal play. If it starts firing, a payload is outliving its
        // impact and the arrival logic is what needs fixing — not this line.
        let payNow = w.payX0 + w.payVX0 * (MLXArray(t) - w.payT0)
        let payGap = payNow - px
        w.payAlive = logicalAnd(w.payAlive,
                                logicalAnd(greater(payGap, behind), less(payGap, ahead)))

        // ── 6b. Other pigeons: move, cull, and decide whether the run just ended ─────────────
        w.flockX = w.flockX + w.flockV * dt
        let flockGap = w.flockX - px
        w.flockAlive = logicalAnd(w.flockAlive,
                                  logicalAnd(greater(flockGap, behind), less(flockGap, ahead)))

        // Box overlap against the player, reduced over the flock axis. One `[B,K]` comparison and a
        // max — the same shape as every other interaction in this engine.
        let hitX = less(abs(w.flockX - px), MLXArray(Float(c.crashRadiusX)))
        let hitY = less(abs(w.flockY - w.pigeonY.expandedDimensions(axis: 1)),
                        MLXArray(Float(c.crashRadiusY)))
        let touching = logicalAnd(w.flockAlive, logicalAnd(hitX, hitY))
        let crashed = greater(which(touching, MLXArray(Float(1)), MLXArray(Float(0))).max(axis: 1), 0.5)
        w.alive = logicalAnd(w.alive, logicalNot(crashed))

        // Keep the flock topped up between minFlock and maxFlock. Two thresholds so the airspace is
        // never empty and never a wall: below the floor a bird spawns every eligible frame, between
        // floor and ceiling it spawns on a dice roll.
        let flockLive = which(w.flockAlive, MLXArray(Float(1)), MLXArray(Float(0))).sum(axis: 1)
        let fFreeF = which(w.flockAlive, MLXArray(Float(0)), MLXArray(Float(1)))
        let fAnyFree = greater(fFreeF.max(axis: 1), 0.5)
        let fFirst = fFreeF.argMax(axis: 1)
        let fLane = MLXArray.arange(K, dtype: .int32).expandedDimensions(axis: 0)

        let wantMore = logicalOr(less(flockLive, Float(c.minFlock)),
                                 logicalAnd(less(flockLive, Float(c.maxFlock)),
                                            less(rolls[0..., 4], MLXArray(Float(0.02)))))
        let fSlot = logicalAnd(equal(fFirst.expandedDimensions(axis: 1), fLane),
                               logicalAnd(logicalAnd(wantMore, fAnyFree), w.alive)
                                   .expandedDimensions(axis: 1))

        // Three populations from one direction roll, all with speeds RELATIVE to the pigeon so that
        // every bird visibly moves against the camera.
        let dirRoll = rolls[0..., 5]
        let oncoming = less(dirRoll, MLXArray(Float(c.flockOncomingShare)))
        let fromBehind = logicalAnd(greaterEqual(dirRoll, MLXArray(Float(c.flockOncomingShare))),
                                    less(dirRoll, MLXArray(Float(c.flockOncomingShare
                                                                 + c.flockFromBehindShare))))
        let speedMag = Rng.scaled(rolls[0..., 6], into: c.flockSpeedRange)
        // Relative to the pigeon's ACTUAL speed at spawn, not the nominal cruise constant. The two
        // differ constantly: every release knocks `releaseRecoil` off the pigeon's velocity, and the
        // player can shift it by ±3 m/s. Spawning against the constant meant the intended relative
        // speed was only ever right when the pigeon happened to be at exactly cruise.
        let base = w.pigeonVX
        let fSpeed = which(oncoming, -speedMag,
                           which(fromBehind, base + speedMag, base - speedMag))

        // Overtakers enter just inside the rear edge so the player watches them come; everyone else
        // enters at the front edge.
        let enterAt = which(fromBehind,
                            MLXArray(Float(c.cullBehindPigeon + 2)),
                            MLXArray(Float(c.visibleAheadOfPigeon)))
        let spread = Float(c.flockAltitudeSpread)
        let fAlt = clip(w.pigeonY + (rolls[0..., 7] * 2 - 1) * spread,
                        min: MLXArray(Float(c.altitudeRange.lowerBound)),
                        max: MLXArray(Float(c.altitudeRange.upperBound)))
        let colK = { (a: MLXArray) in a.expandedDimensions(axis: 1) }
        w.flockX = which(fSlot, colK(w.pigeonX + enterAt), w.flockX)
        w.flockY = which(fSlot, colK(fAlt), w.flockY)
        w.flockV = which(fSlot, colK(fSpeed), w.flockV)
        w.flockAlive = logicalOr(w.flockAlive, fSlot)

        // ── 7. Spawn traffic, hittable by construction ───────────────────────────────────────
        let due = logicalAnd(greaterEqual(MLXArray(t), w.nextSpawnTime), w.alive)
        let tFreeF = which(w.tgtAlive, MLXArray(Float(0)), MLXArray(Float(1)))
        let tAnyFree = greater(tFreeF.max(axis: 1), 0.5)
        let tFirstFree = tFreeF.argMax(axis: 1)
        let tLane = MLXArray.arange(M, dtype: .int32).expandedDimensions(axis: 0)
        let tSlot = logicalAnd(equal(tFirstFree.expandedDimensions(axis: 1), tLane),
                               logicalAnd(due, tAnyFree).expandedDimensions(axis: 1))

        let kindRoll = rolls[0..., 0]
        let speedRoll = rolls[0..., 1]
        let jitterRoll = rolls[0..., 2]
        let intervalRoll = rolls[0..., 3]

        let isPed = less(kindRoll, MLXArray(Float(0.3)))
        let carSpeeds = Spawn.speeds(fromUniform: speedRoll, c.car, in: c)
        let pedSpeeds = Spawn.speeds(fromUniform: speedRoll, c.pedestrian, in: c)
        let speed = which(isPed, pedSpeeds, carSpeeds)
        let carGap = Spawn.emissionGap(targetSpeed: carSpeeds, jitter: jitterRoll, c.car, in: c)
        let pedGap = Spawn.emissionGap(targetSpeed: pedSpeeds, jitter: jitterRoll, c.pedestrian, in: c)
        let gapOut = which(isPed, pedGap, carGap)

        // Only the kind flag is stored; topY, radius and points are derived from it at the two
        // places that read them.
        let colM = { (a: MLXArray) in a.expandedDimensions(axis: 1) }
        let pedF = which(isPed, MLXArray(Float(1)), MLXArray(Float(0)))
        w.tgtX0 = which(tSlot, colM(w.pigeonX + gapOut), w.tgtX0)
        w.tgtV = which(tSlot, colM(speed), w.tgtV)
        w.tgtT0 = which(tSlot, MLXArray(t), w.tgtT0)
        w.tgtIsPedestrian = which(tSlot, colM(pedF), w.tgtIsPedestrian)
        w.tgtHit = logicalAnd(w.tgtHit, logicalNot(tSlot))
        w.tgtAlive = logicalOr(w.tgtAlive, tSlot)

        let interval = Rng.scaled(intervalRoll, into: 0.45...1.1)
        w.nextSpawnTime = which(due, MLXArray(t) + interval, w.nextSpawnTime)

        w.frame += 1

        // ── 8. Materialise, exactly once, here ───────────────────────────────────────────────
        //
        // MLX is lazy: without this the graph grows without bound across steps, and a 3600-step run
        // builds one enormous unevaluated expression before anybody looks at a number. That is not a
        // slow path, it is a hang — which is precisely how this line came to be written.
        //
        // Once per step, at the end, is also the *only* correct place. An `.item()` or `.asArray()`
        // anywhere in the middle would sync the GPU mid-kernel and serialise the whole thing.
        w.evaluate()
    }

    /// How often the origin is pulled back to the pigeon.
    ///
    /// A **fixed** schedule, never a threshold on `x`. A threshold would fire at a state-dependent
    /// moment, and two runs of the same seed that rebase on different frames diverge — silently, and
    /// only after long enough that nobody connects it to the cause.
    public static let rebaseInterval = 1024

    /// How far past the camera's forward edge an entity may drift before its slot is reclaimed.
    /// Generous, so the cull is a safety net rather than something gameplay leans on.
    public static let cullMargin: Double = 12

    /// Pull the world back to the origin so Float32 keeps its resolution.
    ///
    /// `x` grows without bound at 12 m/s; after a few minutes `x_t − x_p` is a cancelling difference
    /// of large numbers and hit tests start to jitter. The odometer keeps the real distance in
    /// `Double`, host-side, where it is only ever displayed.
    public static func rebaseIfDue(_ w: inout World) {
        guard w.frame % rebaseInterval == 0, w.frame > 0 else { return }
        let shift = w.pigeonX
        let shiftHost = shift.asArray(Float.self)
        for i in 0..<w.batch { w.odometer[i] += Double(shiftHost[i]) }

        w.pigeonX = w.pigeonX - shift
        w.payX0 = w.payX0 - shift.expandedDimensions(axis: 1)
        w.payImpactX = w.payImpactX - shift.expandedDimensions(axis: 1)
        w.tgtX0 = w.tgtX0 - shift.expandedDimensions(axis: 1)
        w.flockX = w.flockX - shift.expandedDimensions(axis: 1)
    }
}

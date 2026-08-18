import Foundation

/// The one kernel. Everything the game does in a tick happens here, elementwise, once.
///
/// There is **no loop** in this file — not over worlds, not over slots.
/// `VectorDisciplineTests` enforces that by scanning the source, so the property survives future
/// edits rather than depending on care.
///
/// Three idioms carry the whole thing:
///
///  * **Fixed capacity plus an alive mask** replaces every variable-length list. To spawn, find the
///    first free slot with `argMinSlots` over the mask, one-hot it, and write with `which`. A one-hot
///    `which` *is* a scatter, at fixed cost and with no resizing. Three carrots per drop means three
///    of those in a row — written out, because "three" is a rule of the game and not a loop bound.
///  * **Masks are numbers, never branches.** A pig that cannot afford to drop does not skip the drop
///    code; its drop is multiplied by zero. Every world in a batch therefore runs the same
///    instructions, which is what makes `N = 1` and `N = 512` the same program.
///  * **Everything the player feels is derived from `fat`.** Speed, turn rate, cadence, reach and the
///    wobble's amplitude are all functions of it, so there is exactly one number to reason about and
///    exactly one place — `Shape.swift` — where its consequences are written down.
enum Step {

    /// Sentinel for "no candidate", far outside any real squared distance in a 20 m paddock.
    private static let far = 1e12

    static func advance(_ w: inout World, intent: Intent) {
        let c = w.config
        let n = w.batch, k = w.dropSlots
        let dt = c.dt
        let twoPi = 2 * Double.pi

        // The body, derived from `fat` rather than stored. Reach and girth both come from here, so
        // the pig's physical size and its drawn size are the same number.
        let body = PigShape.derive(fat: w.fat)

        // ── 1. Steering ──────────────────────────────────────────────────────────────────────
        //
        // The stick gives a world-space direction; the pig turns toward it at a bounded rate. Fat
        // eats into that rate, which is the whole handling cost of being enormous.
        let mag = (intent.moveX * intent.moveX + intent.moveZ * intent.moveZ).squareRoot
            .clamped(min: 0, max: 1)
        let steering = mag .> 0.02
        let wanted = Tensor.atan2(intent.moveX, intent.moveZ)
        let delta = (wanted - w.heading).wrappedToPi
        let turnCap = (w.fat * (-c.turnFatPenalty) + 1) * (c.turnRate * dt)
        let turn = Tensor.maximum(Tensor.minimum(delta, turnCap), -turnCap) * steering
        w.heading = (w.heading + turn).wrappedToPi

        // ── 2. Speed ─────────────────────────────────────────────────────────────────────────
        //
        // Velocity approaches the intent rather than snapping to it, and the time constant grows with
        // fat. That exponential approach is the entire difference between an animal and a cursor.
        let slowedByEating = Tensor.which(w.eating, c.eatSpeedFactor, 1.0)
        let want = mag * (w.fat * (-c.speedFatPenalty) + 1) * c.walkSpeed * slowedByEating
        let tau = (w.fat * c.accelFatPenalty + 1) * c.accelTau
        let approach = (Tensor(repeating: dt, shape: [n]) / tau).clamped(min: 0, max: 1)
        let wasSpeed = w.speed
        w.speed = w.speed + (want - w.speed) * approach

        let sinH = w.heading.sine, cosH = w.heading.cosine
        let stepX = w.x + sinH * w.speed * dt
        let stepZ = w.z + cosH * w.speed * dt

        // The paddock is a disc, and leaving it is prevented by projection rather than by a wall:
        // sliding along the fence reads better than stopping dead at it, and it needs no geometry.
        let dist = (stepX * stepX + stepZ * stepZ).squareRoot
        let outside = dist .> c.paddockRadius
        let pull = Tensor.which(outside,
                                Tensor(repeating: c.paddockRadius, shape: [n]) / dist.maximum(1e-6),
                                1.0)
        w.x = stepX * pull
        w.z = stepZ * pull

        // ── 3. Gait ──────────────────────────────────────────────────────────────────────────
        //
        // Advanced by DISTANCE, not by time, so the feet stay planted at every speed. Wrapped every
        // cycle so the phase cannot grow until Float32 loses its resolution in the shader.
        // The batched form of `WorldConfig.cadence(atFat:)`: 2π over the stride, and the stride is the
        // leg. `StepTests.testTheBatchedCadenceMatchesTheScalarOne` holds the two together — a pig
        // whose feet are planted against a different number than the one it walks on is a pig that
        // skates, and neither half looks wrong on its own.
        let cadence = (2 * Double.pi / c.strideOverLeg) / body.legLength
        let rawGait = w.gait + w.speed * dt * cadence
        w.gait = rawGait - (rawGait / twoPi).floored * twoPi

        // ── 4. The dog ───────────────────────────────────────────────────────────────────────
        //
        // It runs straight at the pig at a speed BETWEEN a lean pig's and a fat one's. That single
        // number is the entire reason the fat/speed trade-off matters: a pig that has been dropping
        // simply outruns it, and a pig that has been greedy simply cannot.
        w.dogTimer = w.dogTimer - dt
        let resting = w.dogActive .< 0.5
        let arrives = resting .&& (w.dogTimer .<= 0)

        let dogAngle = Rng.uniform([n], seed: w.seed, frame: w.frame, stream: .dogAngle) * twoPi
        w.dogX = Tensor.which(arrives, w.x + dogAngle.sine * c.dogSpawnDistance, w.dogX)
        w.dogZ = Tensor.which(arrives, w.z + dogAngle.cosine * c.dogSpawnDistance, w.dogZ)
        let huntFor = Rng.scaled(Rng.uniform([n], seed: w.seed, frame: w.frame, stream: .dogTimer),
                                 into: c.dogHunt)
        w.dogTimer = Tensor.which(arrives, huntFor, w.dogTimer)
        w.dogActive = Tensor.maximum(w.dogActive, Tensor.which(arrives, 1.0, 0.0))

        let toPigX = w.x - w.dogX, toPigZ = w.z - w.dogZ
        let gap = (toPigX * toPigX + toPigZ * toPigZ).squareRoot
        let safeGap = gap.maximum(1e-6)
        let lunge = w.dogActive * (c.dogSpeed * dt)
        w.dogX = w.dogX + toPigX / safeGap * lunge
        w.dogZ = w.dogZ + toPigZ / safeGap * lunge
        let rawDogGait = w.dogGait + lunge * c.dogCadence
        w.dogGait = rawDogGait - (rawDogGait / twoPi).floored * twoPi

        let hunting = w.dogActive .> 0.5
        let caught = hunting .&& (gap .< c.dogCatchRadius)
        let givesUp = hunting .&& (w.dogTimer .<= 0)
        let leaves = caught .|| givesUp
        w.dogActive = Tensor.which(leaves, 0.0, w.dogActive)
        let restFor = Rng.scaled(Rng.uniform([n], seed: w.seed, frame: w.frame &+ 7,
                                             stream: .dogTimer), into: c.dogRest)
        w.dogTimer = Tensor.which(leaves, restFor, w.dogTimer)
        w.dogCaught = caught

        // ── 5. Dropping ──────────────────────────────────────────────────────────────────────
        //
        // Fires on the PRESS, not on the hold, and costs `dropFatCost` — which is more than one
        // carrot returns, so a drop is something several meals paid for. Being caught by the dog
        // drops too, involuntarily and for a different amount, and both go down the same path: there
        // is one place in this engine that puts something on the ground.
        w.dropTimer = (w.dropTimer - dt).maximum(0)
        let pressed = intent.drop .&& (w.dropHeld .< 0.5)
        w.dropHeld = intent.drop

        let frightened = caught .&& (w.fat .>= c.dogFright)
        let deliberate = pressed .&& (w.dropTimer .<= 0) .&& (w.fat .>= c.dropMinFat)

        // Three free slots, found by three argmins in a row. Each one masks off the lane the previous
        // took, which is what stops them all landing on the same slot.
        let taken1 = w.dropAlive
        let hot1 = Tensor.oneHot(taken1.argMinSlots(), slots: k)
        let taken2 = Tensor.maximum(taken1, hot1)
        let hot2 = Tensor.oneHot(taken2.argMinSlots(), slots: k)
        let taken3 = Tensor.maximum(taken2, hot2)
        let hot3 = Tensor.oneHot(taken3.argMinSlots(), slots: k)
        let roomFor = (Double(k) - w.dropAlive.sumSlots()) .>= Double(c.carrotsPerDrop)

        let dropping = (deliberate .|| frightened) .&& roomFor
        let cost = Tensor.which(frightened, c.dogFright, c.dropFatCost)

        // Where it lands: behind the pig, then spread into a small patch so the carrots come up as
        // three separate walks rather than as one long chew.
        let baseX = w.x - sinH * c.dropBehind
        let baseZ = w.z - cosH * c.dropBehind
        let spin = Rng.uniform([n], seed: w.seed, frame: w.frame, stream: .dropSpread) * twoPi
        let third = twoPi / 3
        let angle = hot1 * spin.spread(k) + hot2 * (spin + third).spread(k)
            + hot3 * (spin + 2 * third).spread(k)

        let hot = ((hot1 + hot2 + hot3) .> 0.5) .&& dropping.spread(k)
        w.dropX = Tensor.which(hot, baseX.spread(k) + angle.sine * c.carrotSpread, w.dropX)
        w.dropZ = Tensor.which(hot, baseZ.spread(k) + angle.cosine * c.carrotSpread, w.dropZ)
        w.dropAge = Tensor.which(hot, 0.0, w.dropAge)
        w.dropAmount = Tensor.which(hot, c.carrotUnit, w.dropAmount)
        w.dropLook = Tensor.which(hot,
                                  Rng.uniform([n, k], seed: w.seed, frame: w.frame, stream: .dropLook),
                                  w.dropLook)
        w.dropAlive = Tensor.maximum(w.dropAlive, Tensor.which(hot, 1.0, 0.0))

        w.dropped = dropping
        w.dropTimer = Tensor.which(dropping, c.dropCooldown, w.dropTimer)
        let spent = cost * dropping

        // ── 6. Growing ───────────────────────────────────────────────────────────────────────
        //
        // The only thing that turns a dropping into food is time. Age is per slot and counts up; the
        // ripeness derived from it is what both the bite test and the renderer read.
        w.dropAge = w.dropAge + dt * w.dropAlive
        let ripeness = World.ripeness(age: w.dropAge, in: c)
        let edible = (ripeness .>= 1) .&& w.dropAlive

        // ── 7. Eating ────────────────────────────────────────────────────────────────────────
        //
        // The bite test is against the SNOUT, placed from the derived body length — so a pig that has
        // just grown reaches further, without anyone maintaining a second number for it.
        let reach = body.length * 0.5 + c.mouthReach
        let snoutX = w.x + sinH * reach
        let snoutZ = w.z + cosH * reach

        let dx = w.dropX - snoutX.spread(k)
        let dz = w.dropZ - snoutZ.spread(k)
        let d2 = dx * dx + dz * dz
        let bite = World.dropRadius(amount: w.dropAmount, ripeness: ripeness, in: c) + c.mouthReach
        let reachable = (d2 .< (bite * bite)) .&& edible

        // Nearest reachable carrot only. Eating every carrot the snout happens to overlap would let a
        // pig standing in a patch gain fat three times faster for the same input — the sort of thing
        // that never looks like a bug, only like inconsistent tuning.
        let candidate = Tensor.which(reachable, d2, far)
        let chosen = Tensor.oneHot(candidate.argMinSlots(), slots: k)
            * (candidate.minSlots() .< far * 0.5).spread(k)

        let take = Tensor.minimum(w.dropAmount, Tensor(repeating: c.eatRate * dt, shape: [n, k]))
            * chosen
        w.dropAmount = w.dropAmount - take
        let swallowed = take.sumSlots()
        w.eating = swallowed .> 1e-9

        let finished = edible .&& (w.dropAmount .<= 1e-6)
        w.dropAlive = w.dropAlive .&& finished.not
        w.eaten = w.eaten + finished.sumSlots()

        // ── 8. Fat ───────────────────────────────────────────────────────────────────────────
        //
        // The three ways it moves, all as rates or as one-off costs, so none of them depends on the
        // frame rate. The clamp is what every geometry proof in `ShapeOracleTests` is stated over.
        w.fat = (w.fat + swallowed * c.fatPerCarrotUnit - spent - c.walkBurn * dt)
            .clamped(min: 0, max: 1)

        // ── 9. The wobble spring ─────────────────────────────────────────────────────────────
        //
        // Driven by three things: each footfall, any change in the pig's own speed, and the shove of
        // a drop leaving. A lean pig's spring is barely visible because `wobbleGain` scales the
        // *amplitude* with fat — the spring itself is the same spring, so a fat pig does not get a
        // second, special code path.
        let footfall = (w.gait * 2).sine.maximum(0).raisedTo(10)
            * (c.wobbleFootfall * (w.speed / c.walkSpeed).absolute)
        let jerk = ((w.speed - wasSpeed) / dt).absolute * c.wobbleAccel
        let omega = c.wobbleFrequency
        let force = footfall + jerk + dropping * c.wobbleDrop
        w.wobV = w.wobV + (w.wob * (-omega * omega) - w.wobV * (2 * c.wobbleDamping * omega) + force) * dt
        w.wob = (w.wob + w.wobV * dt).clamped(min: -1, max: 1)

        w.frame += 1
    }
}

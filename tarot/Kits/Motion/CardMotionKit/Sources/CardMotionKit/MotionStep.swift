import Foundation

/// The one kernel. `advance` moves every card in every world one step, with no loop over
/// worlds or cards — only tensor algebra. The two `for` loops below iterate the *three spread
/// slots*, a physical constant of the spread (the same category as froggo2's `maxBounces`);
/// both are named in `VectorDisciplineTests`' allowlist.
///
/// Pure with respect to its inputs: state in, intent in, dt in — state out, events out.
/// No clock, no system RNG, no platform import. That is what lets four thousand emulated
/// draws prove the same code path a thumb drives at N = 1.
public enum MotionStep {

    /// Per-lane slot target coordinates for the committed `slot` lane (−1 falls back to the
    /// deck centre — the return flight's destination). Yaw and lift ride the same masked
    /// pass (zero for every slot of the three-card layout; the ten-card cross gives its
    /// crossing slot a quarter turn and a couple of thicknesses of rest height).
    static func slotTargets(slot: Tensor, config: MotionConfig)
        -> (x: Tensor, z: Tensor, yaw: Tensor, lift: Tensor) {
        var tx = Tensor(repeating: config.deckX, shape: slot.shape)
        var tz = Tensor(repeating: config.deckZ, shape: slot.shape)
        var tyaw = Tensor(repeating: 0, shape: slot.shape)
        var tlift = Tensor(repeating: 0, shape: slot.shape)
        for s in 0..<config.slotCount {
            let m = slot .== Double(s)
            tx = Tensor.which(m, config.slotX[s], tx)
            tz = Tensor.which(m, config.slotZ[s], tz)
            tyaw = Tensor.which(m, config.slotYaw[s], tyaw)
            tlift = Tensor.which(m, config.slotLift[s], tlift)
        }
        return (tx, tz, tyaw, tlift)
    }

    @discardableResult
    public static func advance(_ w: inout MotionWorld, intent: MotionIntent, dt: Double,
                               config: MotionConfig) -> MotionEvents {
        let n = w.batch
        let c = w.capacity
        w.advanceTick()
        w.time += dt

        // ── Input conditioning ────────────────────────────────────────────────────────────
        let px = intent.pointerX.clamped(min: -config.tableExtentX, max: config.tableExtentX)
        let pz = intent.pointerZ.clamped(min: -config.tableExtentZ, max: config.tableExtentZ)
        let press = intent.press .> 0.5

        let pressEdge = Tensor.newlySet(now: press, previous: w.prevPress)      // [N]
        let releaseEdge = Tensor.newlySet(now: w.prevPress, previous: press)    // [N]

        let lightAlpha = 1 - exp(-config.lightRate * dt)
        w.lightX = w.lightX + (intent.lightX - w.lightX) * lightAlpha
        w.lightZ = w.lightZ + (intent.lightZ - w.lightZ) * lightAlpha

        // ── Grab: press near the deck lifts the topmost in-deck card ─────────────────────
        let inDeck = w.phase .== MotionWorld.Phase.inDeck
        let heldBefore = w.phase .== MotionWorld.Phase.held
        let dxDeck = px - config.deckX
        let dzDeck = pz - config.deckZ
        let nearDeck = (dxDeck * dxDeck + dzDeck * dzDeck)
            .< (config.deckGrabRadius * config.deckGrabRadius)                  // [N]
        let handFree = heldBefore.sumLast() .< 0.5                              // [N]
        let wantGrab = (pressEdge .&& nearDeck .&& handFree).expandedPerLane(c) // [N,C]

        let grabbed = Tensor.oneHotOfMaskedMin(values: w.deckDepth, mask: inDeck .&& wantGrab)

        w.phase = Tensor.which(grabbed, MotionWorld.Phase.held, w.phase)
        w.vx = Tensor.which(grabbed, 0, w.vx)
        w.vz = Tensor.which(grabbed, 0, w.vz)
        w.juiceAmp = Tensor.which(grabbed, config.grabJuice, w.juiceAmp)
        w.juiceT = Tensor.which(grabbed, 0, w.juiceT)
        let grabSignNoise = LaneNoise.uniforms(seed: w.seed, tick: w.tick, stream: 2,
                                               worlds: n, lanes: c)
        w.juiceSign = Tensor.which(grabbed, 1 - 2 * (grabSignNoise .< 0.5), w.juiceSign)

        // ── Held: exponential pointer follow, smoothed velocity for the roll ─────────────
        let held = w.phase .== MotionWorld.Phase.held
        let followAlpha = 1 - exp(-config.followRate * dt)
        let velAlpha = 1 - exp(-config.velocityRate * dt)
        let liftAlpha = 1 - exp(-config.liftRate * dt)

        let targetX = px.expandedPerLane(c)
        let targetZ = pz.expandedPerLane(c)
        let newX = w.x + (targetX - w.x) * followAlpha
        let newZ = w.z + (targetZ - w.z) * followAlpha
        let instVX = (newX - w.x) / dt
        let instVZ = (newZ - w.z) / dt
        w.vx = Tensor.which(held, w.vx + (instVX - w.vx) * velAlpha, w.vx)
        w.vz = Tensor.which(held, w.vz + (instVZ - w.vz) * velAlpha, w.vz)
        w.x = Tensor.which(held, newX, w.x)
        w.z = Tensor.which(held, newZ, w.z)
        w.y = Tensor.which(held, w.y + (config.heldLift - w.y) * liftAlpha, w.y)

        // ── Release: nearest free slot within snap radius wins, else return to deck ──────
        let releasing = held .&& releaseEdge.expandedPerLane(c)                 // [N,C]
        var bestDist = Tensor(repeating: .infinity, shape: [n, c])
        var chosenSlot = Tensor(repeating: -1, shape: [n, c])
        for s in 0..<config.slotCount {
            // A slot is free if no card in any world lane is committed to it (flying or landed).
            let taken = (w.slot .== Double(s)).sumLast() .> 0.5                 // [N]
            let dxs = w.x - config.slotX[s]
            let dzs = w.z - config.slotZ[s]
            let dist2 = dxs * dxs + dzs * dzs
            let candidate = releasing
                .&& (dist2 .< config.snapRadius * config.snapRadius)
                .&& taken.not.expandedPerLane(c)
                .&& (dist2 .< bestDist)
            bestDist = Tensor.which(candidate, dist2, bestDist)
            chosenSlot = Tensor.which(candidate, Double(s), chosenSlot)
        }
        let releasedToSlot = releasing .&& (chosenSlot .>= 0)
        let releasedToReturn = releasing .&& (chosenSlot .< 0)

        let committing = releasedToSlot .|| releasedToReturn
        w.phase = Tensor.which(committing, MotionWorld.Phase.flying, w.phase)
        w.slot = Tensor.which(releasedToSlot, chosenSlot, w.slot)
        w.slot = Tensor.which(releasedToReturn, -1, w.slot)
        w.flightT = Tensor.which(committing, 0, w.flightT)
        w.startX = Tensor.which(committing, w.x, w.startX)
        w.startZ = Tensor.which(committing, w.z, w.startZ)
        w.startVX = Tensor.which(committing, w.vx, w.startVX)
        w.startVZ = Tensor.which(committing, w.vz, w.startVZ)

        // ── Flight: cubic Hermite from (release point, release velocity) to (target, 0) ──
        // The incoming drag velocity IS the initial tangent, so a fling arrives with carry
        // and settles — "carries velocity into an inertial settle", by construction.
        let flying = w.phase .== MotionWorld.Phase.flying
        w.flightT = Tensor.which(flying, w.flightT + dt, w.flightT)
        let s = (w.flightT / config.flightDuration).clamped(min: 0, max: 1)

        let (tx, tz, _, _) = slotTargets(slot: w.slot, config: config)
        let s2 = s * s
        let s3 = s2 * s
        // reduceMotion: linear path, no Hermite tangent, no arc — but the same landings.
        let h00 = config.reduceMotion ? (1 - s) : (2 * s3 - 3 * s2 + 1)
        let h10 = config.reduceMotion ? Tensor.zeros([n, c]) : (s3 - 2 * s2 + s)
        let h01 = config.reduceMotion ? s : (-2 * s3 + 3 * s2)
        let T = config.flightDuration
        let flightX = h00 * w.startX + h10 * (w.startVX * T) + h01 * tx
        let flightZ = h00 * w.startZ + h10 * (w.startVZ * T) + h01 * tz
        w.x = Tensor.which(flying, flightX, w.x)
        w.z = Tensor.which(flying, flightZ, w.z)

        // Flip runs inside slot-bound flights only; smoothstepped so the apex has dwell.
        let slotBound = flying .&& (w.slot .>= 0)
        let fRaw = ((s - config.flipStart) / config.flipSpan).clamped(min: 0, max: 1)
        let fSmooth = fRaw * fRaw * (3 - 2 * fRaw)
        w.flip = Tensor.which(slotBound, fSmooth, w.flip)

        // Flip clearance: while the card is edge-on its swinging corners need headroom, or
        // they pierce the table (seen on device as intersection triangles). Geometry, not
        // decoration — never Reduce-Motion-gated. ∝ sin(flip·π): zero at start and landing.
        let arc = config.reduceMotion ? 0.0 : config.flightArc
        let flipLift = (w.flip * Double.pi).sine * (config.cardWidth * config.flipClearance)
        let flightY = (1 - s) * config.heldLift + (s * Double.pi).sine * arc + flipLift
        w.y = Tensor.which(flying, flightY, w.y)

        // ── Arrivals ─────────────────────────────────────────────────────────────────────
        let arrived = flying .&& (s .>= 1)
        let landed = arrived .&& (w.slot .>= 0)
        let returned = arrived .&& (w.slot .< 0)

        w.phase = Tensor.which(landed, MotionWorld.Phase.landed, w.phase)
        w.phase = Tensor.which(returned, MotionWorld.Phase.inDeck, w.phase)
        w.x = Tensor.which(landed, tx, w.x)
        w.z = Tensor.which(landed, tz, w.z)
        w.y = Tensor.which(arrived, 0, w.y)
        w.vx = Tensor.which(arrived, 0, w.vx)
        w.vz = Tensor.which(arrived, 0, w.vz)
        w.flip = Tensor.which(landed, 1, w.flip)
        w.flip = Tensor.which(returned, 0, w.flip)

        // A returned card goes on top of the deck: one less than the current minimum depth.
        let inDeckNow = w.phase .== MotionWorld.Phase.inDeck
        let depthOrBig = Tensor.which(inDeckNow .&& returned.not, w.deckDepth, 1e9)
        let minDepth = depthOrBig.minLast().minimum(1e8)                        // [N]
        w.deckDepth = Tensor.which(returned, (minDepth - 1).expandedPerLane(c), w.deckDepth)

        // Landing juice — the hero beat is the card that fills the final slot.
        let filledCount = (w.phase .== MotionWorld.Phase.landed).sumLast()      // [N]
        let allFilled = filledCount .>= Double(config.slotCount) - 0.5          // [N]
        let heroLanded = landed .&& allFilled.expandedPerLane(c)
        let landAmp = Tensor.which(heroLanded, config.heroLandJuice, config.landJuice * Tensor.ones([n, c]))
        w.juiceAmp = Tensor.which(landed .|| returned, landAmp, w.juiceAmp)
        w.juiceT = Tensor.which(landed .|| returned, 0, w.juiceT)
        let landSignNoise = LaneNoise.uniforms(seed: w.seed, tick: w.tick, stream: 3,
                                               worlds: n, lanes: c)
        w.juiceSign = Tensor.which(landed .|| returned, 1 - 2 * (landSignNoise .< 0.5), w.juiceSign)

        // ── Bookkeeping & events ─────────────────────────────────────────────────────────
        w.juiceT = w.juiceT + dt

        let flipHalf = w.flip .>= 0.5
        let flipApex = Tensor.newlySet(now: flipHalf, previous: w.prevFlipHalf)
        w.prevFlipHalf = flipHalf

        let done = allFilled
        let drawComplete = Tensor.newlySet(now: done, previous: w.prevDone)
        w.prevDone = done
        w.prevPress = press

        return MotionEvents(grabbed: grabbed,
                            releasedToSlot: releasedToSlot,
                            releasedToReturn: releasedToReturn,
                            flipApex: flipApex,
                            landed: landed,
                            heroLanded: heroLanded,
                            returnedToDeck: returned,
                            drawComplete: drawComplete)
    }
}

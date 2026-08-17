import XCTest
import MLX
@testable import CityPigeon

/// The flock hazard, and the slot hygiene the owner asked for as "garbage collection".
final class FlockAndSlotTests: XCTestCase {

    let w = WorldConfig.shipping

    // MARK: - The crash

    /// Place a bird exactly on the pigeon and require the run to end; place it a millimetre outside
    /// the combined box and require the run to continue.
    ///
    /// Bracketing from both sides is the sharpest statement available about a boolean, and it is the
    /// same sandwich the interception boundary gets.
    ///
    /// **The placement compensates for one step of motion**, and that is not a fudge — the collision
    /// is evaluated in phase 6b, *after* phase 1 has already flown the pigeon forward by `v_x·dt`.
    /// The first version of this test placed birds relative to the pre-step position and reported two
    /// false crashes at exactly `+0.2 m`, which is `cruiseSpeed · dt`. The offset below is that
    /// distance, and the assertion at the end re-measures the real gap so the test fails loudly if
    /// the phase ordering ever changes rather than silently drifting off the boundary.
    func testTheCrashBoxIsBracketedToAMillimetre() {
        let stepAdvance = Float(w.cruiseSpeed * w.dt)
        for (dx, dy, shouldCrash) in [
            (0.0, 0.0, true),
            (w.crashRadiusX - 0.001, 0.0, true),
            (w.crashRadiusX + 0.001, 0.0, false),
            (0.0, w.crashRadiusY - 0.001, true),
            (0.0, w.crashRadiusY + 0.001, false),
            // Overlap needs BOTH axes; clear on either one is a near miss.
            (w.crashRadiusX + 0.001, w.crashRadiusY - 0.001, false),
        ] {
            var world = World(batch: 1, config: w, seed: 1)
            let px = world.pigeonX.item(Float.self), py = world.pigeonY.item(Float.self)
            world.flockAlive = MLXArray.zeros([1, w.flockSlots]) .> 0.5
            world.flockAlive[0, 0] = MLXArray(true)
            world.flockX = MLXArray.zeros([1, w.flockSlots]) + (px + Float(dx) + stepAdvance)
            world.flockY = MLXArray.zeros([1, w.flockSlots]) + (py + Float(dy))
            world.flockV = MLXArray.zeros([1, w.flockSlots])

            Step.advance(&world, intent: .idle(batch: 1))
            world.evaluate()

            // Re-measure rather than trust the placement: this is the geometry the engine actually
            // saw, and it is what the assertion is really about.
            let gapX = abs(world.flockX.asArray(Float.self)[0] - world.pigeonX.item(Float.self))
            let gapY = abs(world.flockY.asArray(Float.self)[0] - world.pigeonY.item(Float.self))
            XCTAssertEqual(Double(gapX), abs(dx), accuracy: 1e-3,
                           "the step moved the pigeon by something other than cruiseSpeed·dt")

            let overlapping = Double(gapX) < w.crashRadiusX && Double(gapY) < w.crashRadiusY
            XCTAssertEqual(overlapping, shouldCrash, "test scenario is mis-specified")
            XCTAssertEqual(!world.alive.item(Bool.self), shouldCrash,
                           "bird \(gapX) m across and \(gapY) m up from the pigeon: "
                           + "expected crash=\(shouldCrash)")
        }
    }

    /// A dead world stops. Not "stops scoring" — stops.
    func testADeadWorldFreezes() {
        var world = World(batch: 1, config: w, seed: 2)
        let py = world.pigeonY.item(Float.self)
        world.flockAlive = MLXArray.zeros([1, w.flockSlots]) .> 0.5
        world.flockAlive[0, 0] = MLXArray(true)
        world.flockX = MLXArray.zeros([1, w.flockSlots]) + world.pigeonX.item(Float.self)
        world.flockY = MLXArray.zeros([1, w.flockSlots]) + py
        world.flockV = MLXArray.zeros([1, w.flockSlots])
        Step.advance(&world, intent: .idle(batch: 1))
        XCTAssertFalse(world.alive.item(Bool.self))

        let frozenX = world.pigeonX.item(Float.self)
        let frozenScore = world.score.item(Float.self)
        for _ in 0..<120 { Step.advance(&world, intent: Policy.autopilot(world)) }
        world.evaluate()
        XCTAssertEqual(world.pigeonX.item(Float.self), frozenX, accuracy: 1e-4,
                       "a dead pigeon kept flying")
        XCTAssertEqual(world.score.item(Float.self), frozenScore, accuracy: 1e-4,
                       "a dead world kept scoring")
    }

    /// A pilot that holds its line and never looks must die. Otherwise the hazard is decoration.
    ///
    /// This deliberately does **not** use `Policy.autopilot`, which dodges. An earlier version did,
    /// and once avoidance was added it reported zero deaths in twelve runs and failed — correctly
    /// describing a pilot that evades, while claiming to describe one that does not. Lethality is a
    /// property of the flock; survival is a property of the pilot; measuring them through the same
    /// agent conflates the two.
    private func levelFlight(_ world: World) -> Intent {
        let err = (MLXArray(Float(w.cruiseAltitude)) - world.pigeonY) * 0.35
        return Intent(moveX: MLXArray.zeros([1]),
                      moveY: clip(err, min: MLXArray(Float(-1)), max: MLXArray(Float(1))),
                      hold: MLXArray([false]))
    }

    /// **The hazard must be lethal to inattention and survivable with attention** — but stated as the
    /// *difference between the two pilots*, which is the strongest claim this instrument supports.
    ///
    /// An earlier pair of tests asserted the two halves separately, and the second one asserted an
    /// absolute rate: "a pilot that dodges dies fewer than 4 runs in 10". That is a claim about the
    /// game being *fair*, evidenced by a deliberately crude bot — the wrong instrument. This bot flies
    /// level, bombs while it flies, tracks one threat at a time and has no hysteresis, so its death
    /// rate moves for reasons that have nothing to do with fairness: it drifted 3 → 4 when the spawner
    /// was corrected to use the pigeon's *actual* speed, which made the flock more honest, not less
    /// fair. Attempting to make the bot good enough to carry the claim made it *worse* — a version
    /// weighing every threat and steering toward the emptier side dithered and died 6 times in 10.
    ///
    /// So: assert the effect of dodging, which the bot genuinely measures, and leave fairness to be
    /// proven where it can be proven exactly — from the geometry, in `testEveryFlockSpeedIsDodgeable`
    /// and `testOvertakersAreVisibleBeforeTheyArrive`.
    func testDodgingIsWhatSeparatesSurvivalFromDeath() {
        func deaths(_ pilot: (World) -> Intent) -> Int {
            var n = 0
            for seed in UInt64(1)...10 {
                var world = World(batch: 1, config: w, seed: seed)
                for _ in 0..<2400 where world.alive.item(Bool.self) {
                    Step.advance(&world, intent: pilot(world))
                }
                if !world.alive.item(Bool.self) { n += 1 }
            }
            return n
        }

        let blind = deaths { self.levelFlight($0) }
        let dodging = deaths { Policy.autopilot($0) }
        print("FLOCK: deaths in 10 forty-second runs — holding the line \(blind), dodging \(dodging)")

        XCTAssertGreaterThan(blind, 5,
                             "a pilot that never dodges survived \(10 - blind) of 10 runs — the flock "
                             + "is not dense or lethal enough to be a hazard")
        XCTAssertLessThanOrEqual(dodging, blind - 3,
                                 "dodging saved only \(blind - dodging) of \(blind) fatal runs — "
                                 + "either the hazard is unavoidable or avoidance does not work")
        XCTAssertGreaterThan(dodging, 0,
                             "even this crude dodger never dies, so the hazard is too weak to be one")
    }

    // MARK: - Population

    func testTheFlockStaysWithinItsConfiguredBounds() {
        var world = World(batch: 4, config: w, seed: 21)
        var sawMin = false, peak = 0
        // Sampled, not read every frame: an `asArray` per step is a device synchronisation per step.
        for i in 0..<1800 {
            Step.advance(&world, intent: Policy.autopilot(world))
            guard i > 300, i % 7 == 0 else { continue }   // let the airspace fill, then sample
            let live = which(world.flockAlive, MLXArray(Float(1)), MLXArray(Float(0))).sum(axis: 1)
            for n in live.asArray(Float.self) {
                peak = max(peak, Int(n))
                if Int(n) >= w.minFlock { sawMin = true }
                XCTAssertLessThanOrEqual(Int(n), w.flockSlots, "more birds alive than slots")
            }
        }
        print("FLOCK: peak airborne \(peak), configured max \(w.maxFlock), slots \(w.flockSlots)")
        XCTAssertTrue(sawMin, "the airspace never reached minFlock")
        XCTAssertLessThanOrEqual(peak, w.maxFlock + 1, "population overshot its ceiling")
    }

    /// **Every bird must enter with visible motion, and all three populations must occur.**
    ///
    /// The first version drew absolute airspeeds, so a same-direction bird at 9 m/s against the
    /// pigeon's 12 drifted back at 3 m/s and read as parked; and nothing exceeded the pigeon's speed,
    /// so no bird could ever overtake from behind — that population simply did not exist.
    ///
    /// The guarantee is **at entry**, and that boundary is deliberate. Afterwards the player may
    /// match a bird's speed by slowing down, and a bird that appears to hang alongside because you
    /// chose to pace it is gameplay, not a defect. An earlier version of this test asserted the
    /// floor on every frame and caught the pigeon mid-recoil — a bird at 1.16 m/s relative that was
    /// only slow because the *pigeon* had just fired and lost 1.6 m/s of its own speed.
    func testEveryBirdEntersMovingAndAllThreePopulationsOccur() {
        var world = World(batch: 4, config: w, seed: 61)
        var sawOncoming = false, sawOvertaking = false, sawSlowerAhead = false
        var slowestAtEntry = Double.greatestFiniteMagnitude
        var prevAlive = [Bool](repeating: false, count: 4 * w.flockSlots)
        var entries = 0

        for _ in 0..<1500 {
            Step.advance(&world, intent: Policy.autopilot(world))
            let alive = world.flockAlive.asArray(Bool.self)
            let v = world.flockV.asArray(Float.self)
            let pvx = world.pigeonVX.asArray(Float.self)

            for i in 0..<alive.count where alive[i] && !prevAlive[i] {
                let rel = Double(v[i] - pvx[i / w.flockSlots])
                entries += 1
                if v[i] < 0 { sawOncoming = true }
                else if rel > 0.5 { sawOvertaking = true }
                else if rel < -0.5 { sawSlowerAhead = true }
                slowestAtEntry = min(slowestAtEntry, abs(rel))
            }
            prevAlive = alive
        }

        print(String(format: "FLOCK: %d entries · oncoming=%@ overtaking=%@ slower-ahead=%@ · "
                     + "slowest relative motion at entry %.2f m/s",
                     entries, sawOncoming ? "y" : "n", sawOvertaking ? "y" : "n",
                     sawSlowerAhead ? "y" : "n", slowestAtEntry))

        XCTAssertGreaterThan(entries, 20, "too few spawns to judge")
        XCTAssertTrue(sawOncoming, "no head-on birds ever spawned")
        XCTAssertTrue(sawOvertaking, "nothing ever overtook from behind — the population is missing")
        XCTAssertTrue(sawSlowerAhead, "no slower birds ahead")
        XCTAssertGreaterThan(slowestAtEntry, w.flockSpeedRange.lowerBound - 1e-3,
                             "a bird entered at \(slowestAtEntry) m/s relative to the pigeon, below "
                             + "the configured floor of \(w.flockSpeedRange.lowerBound)")
    }

    /// An overtaker must be on screen for its whole approach. A hazard that arrives from behind the
    /// camera edge is not dodgeable, it is just unfair.
    func testOvertakersAreVisibleBeforeTheyArrive() {
        let closingSlowest = w.flockSpeedRange.lowerBound
        let visibleBehind = -w.cullBehindPigeon - 2      // spawn sits 2 m inside the rear edge
        let warning = visibleBehind / w.flockSpeedRange.upperBound
        print(String(format: "FLOCK: overtaker warning time %.2f s (slowest closes in %.2f s)",
                     warning, visibleBehind / closingSlowest))
        XCTAssertGreaterThan(warning, w.reactionLatency + w.flockDodgeTime,
                             "the fastest overtaker reaches the pigeon before it can be noticed and "
                             + "climbed away from")
    }

    /// Dodgeable by construction, asserted rather than assumed — the margin is a property of the
    /// tuning, and tuning changes.
    func testEveryFlockSpeedIsDodgeable() {
        print(String(format: "FLOCK: worst closing %.1f m/s · dodgeable up to %.1f m/s (dodge %.2f s)",
                     w.worstFlockClosingSpeed, w.maxFlockClosingSpeed, w.flockDodgeTime))
        XCTAssertLessThan(w.worstFlockClosingSpeed, w.maxFlockClosingSpeed,
                          "an oncoming bird can arrive faster than the player can climb clear of it")
    }

    // MARK: - Slot hygiene ("garbage collection")

    /// **Nothing alive may sit outside the camera window.**
    ///
    /// The arrays are fixed-capacity, so no amount of neglect grows memory — what leaks is
    /// *availability*. A slot that never frees is one the spawner can never reuse, and the symptom
    /// is a world that quietly stops producing traffic rather than anything that looks like a fault.
    func testNoAliveEntityIsEverOutsideTheWindow() {
        var world = World(batch: 2, config: w, seed: 33)
        let lo = Float(w.cullBehindPigeon) - 1
        let hi = Float(w.visibleAheadOfPigeon + Step.cullMargin) + 1

        for step in 0..<2000 {
            Step.advance(&world, intent: Policy.autopilot(world))
            Step.rebaseIfDue(&world)
            guard step % 17 == 0 else { continue }
            let s = world.snapshot()
            for (name, block) in [("target", s.targets), ("flock bird", s.flock),
                                  ("payload", s.payloads)] {
                for i in 0..<block.slots where block.alive[i] {
                    let gap = block.x[i] - s.pigeonX
                    XCTAssertTrue(gap > lo && gap < hi,
                                  "\(name) at gap \(gap) is alive outside the window")
                }
            }
        }
    }

    /// Slots must never all be busy at once, or the spawner silently stops.
    func testSlotsNeverStarve() {
        var world = World(batch: 4, config: w, seed: 44)
        var peakTargets = 0, peakPayloads = 0, peakFlock = 0

        for i in 0..<2400 {
            Step.advance(&world, intent: Policy.autopilot(world))
            Step.rebaseIfDue(&world)
            guard i % 7 == 0 else { continue }
            let liveT = which(world.tgtAlive, MLXArray(Float(1)), MLXArray(Float(0))).sum(axis: 1)
            let liveP = which(world.payAlive, MLXArray(Float(1)), MLXArray(Float(0))).sum(axis: 1)
            let liveF = which(world.flockAlive, MLXArray(Float(1)), MLXArray(Float(0))).sum(axis: 1)
            peakTargets = max(peakTargets, Int(liveT.max().item(Float.self)))
            peakPayloads = max(peakPayloads, Int(liveP.max().item(Float.self)))
            peakFlock = max(peakFlock, Int(liveF.max().item(Float.self)))
        }
        world.evaluate()

        print("SLOTS: peak targets \(peakTargets)/\(w.targetSlots) · payloads "
              + "\(peakPayloads)/\(w.payloadSlots) · flock \(peakFlock)/\(w.flockSlots)")
        XCTAssertLessThan(peakTargets, w.targetSlots, "target slots were exhausted")
        XCTAssertLessThan(peakPayloads, w.payloadSlots, "payload slots were exhausted")
        XCTAssertLessThan(peakFlock, w.flockSlots, "flock slots were exhausted")
        for d in world.droppedReleases.asArray(Float.self) {
            XCTAssertEqual(d, 0, "a release was dropped for want of a free payload slot")
        }
    }
}

import XCTest
@testable import Pig

/// The kernel, exercised the way the game runs it: whole `dt` steps, an `Intent` per frame, nothing
/// reached into directly except to set up a situation.
final class StepTests: XCTestCase {

    private let c = WorldConfig.shipping

    // MARK: - Helpers

    private func intent(_ x: Double = 0, _ z: Double = 0, drop: Bool = false) -> Intent {
        Intent(moveX: Tensor(shape: [1], data: [x]),
               moveZ: Tensor(shape: [1], data: [z]),
               drop: Tensor(shape: [1], data: [drop ? 1 : 0]))
    }

    private func run(_ w: inout World, frames: Int, _ i: Intent) {
        for _ in 0..<frames { Step.advance(&w, intent: i) }
    }

    /// A bare field: no carrots, no dog. A test about walking should only be about walking.
    private func emptyWorld(fat: Double = 0.45, seed: UInt64 = 0xB0A5) -> World {
        var w = World(batch: 1, config: c, seed: seed)
        w.fat = Tensor(shape: [1], data: [fat])
        w.dropAlive = .zeros([1, w.dropSlots])
        w.dogTimer = Tensor(shape: [1], data: [1e9])
        return w
    }

    /// One grown carrot, `distance` metres straight ahead of a pig facing +z.
    private func worldWithCarrot(at distance: Double, amount: Double? = nil,
                                 fat: Double = 0.45) -> World {
        var w = emptyWorld(fat: fat)
        let k = w.dropSlots
        let mass = amount ?? c.carrotUnit
        var alive = [Double](repeating: 0, count: k)
        var zs = [Double](repeating: 0, count: k)
        var amounts = [Double](repeating: 0, count: k)
        var ages = [Double](repeating: 0, count: k)
        alive[0] = 1; zs[0] = distance; amounts[0] = mass; ages[0] = c.growTime
        w.dropAlive = Tensor(shape: [1, k], data: alive)
        w.dropX = .zeros([1, k])
        w.dropZ = Tensor(shape: [1, k], data: zs)
        w.dropAmount = Tensor(shape: [1, k], data: amounts)
        w.dropAge = Tensor(shape: [1, k], data: ages)
        return w
    }

    /// FNV-1a over the raw bit patterns of every simulation field. The bit-level half of the
    /// determinism contract — it catches "this run produced different numbers than that one", which
    /// no physical assertion can see.
    private func digest(_ w: World) -> UInt64 {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        func absorb(_ t: Tensor) {
            for x in t.data {
                var bits = x == 0 ? 0 : (x.isNaN ? 0x7ff8_0000_0000_0000 : x.bitPattern)
                for _ in 0..<8 {
                    h ^= bits & 0xff
                    h = h &* 0x0000_0100_0000_01b3
                    bits >>= 8
                }
            }
        }
        for t in [w.x, w.z, w.heading, w.speed, w.fat, w.gait, w.wob, w.wobV, w.eating, w.eaten,
                  w.dropTimer, w.dropAlive, w.dropX, w.dropZ, w.dropAge, w.dropAmount,
                  w.dogActive, w.dogX, w.dogZ, w.dogTimer] {
            absorb(t)
        }
        return h
    }

    // MARK: - The economy
    //
    // The game is a loop with an exchange rate, and these are that rate. They are config-level
    // theorems: they hold before a single frame is simulated, and if one breaks the game is either
    // unplayable or trivial regardless of how the rest of the engine behaves.

    /// **One drop must cost several meals.** Otherwise the pig can shed weight on demand, the dog
    /// becomes harmless, and the fat/speed trade-off — the entire game — stops being a decision.
    func testOneDropCostsSeveralMeals() {
        XCTAssertGreaterThan(c.carrotsPerDropCost, 2,
                             "a drop costs \(c.carrotsPerDropCost) carrots — cheap enough to spam")
    }

    /// **But the cycle must still come out ahead.** A drop grows `carrotsPerDrop` carrots; if they
    /// return less than the drop cost, every cycle is a net loss and a competent player still
    /// starves. Together with the test above this pins the rate from both sides.
    func testTheCycleReturnsMoreThanItCosts() {
        XCTAssertLessThan(c.carrotsPerDropCost, Double(c.carrotsPerDrop),
                          "one drop yields \(c.carrotsPerDrop) carrots but costs "
                          + "\(c.carrotsPerDropCost) of them — playing the loop is starvation")
        XCTAssertGreaterThan(c.fatPerDrop, c.dropFatCost)
    }

    /// The dog's speed has to sit strictly between a lean pig's and a fat one's, or it is either
    /// scenery or an execution.
    func testTheDogSitsBetweenALeanPigAndAFatOne() {
        XCTAssertLessThan(c.dogSpeed, c.maxSpeed(atFat: 0), "the dog can outrun even a lean pig")
        XCTAssertGreaterThan(c.dogSpeed, c.maxSpeed(atFat: 1), "a fat pig can outrun the dog")
    }

    // MARK: - Walking

    func testTheStickPointsThePigAndThePigWalksThatWay() {
        var w = emptyWorld()
        run(&w, frames: 240, intent(0, 1))
        XCTAssertGreaterThan(w.z[0], 1.0, "the pig did not walk forward")
        XCTAssertEqual(w.x[0], 0, accuracy: 1e-9, "the pig drifted sideways with no sideways input")

        var v = emptyWorld()
        run(&v, frames: 240, intent(1, 0))
        XCTAssertGreaterThan(v.x[0], 1.0, "the pig did not walk along +x for a +x stick")
        XCTAssertEqual(v.heading[0], .pi / 2, accuracy: 1e-3, "heading did not settle facing +x")
    }

    func testTurningIsRateLimited() {
        var w = emptyWorld(fat: 0)
        let before = w.heading[0]
        Step.advance(&w, intent: intent(0, -1))          // demand a 180° reversal in one frame
        let turned = abs(w.heading[0] - before)
        XCTAssertLessThanOrEqual(turned, c.turnRate * c.dt + 1e-12,
                                 "the pig turned faster than its configured rate")
        XCTAssertGreaterThan(turned, c.turnRate * c.dt * 0.99, "the pig barely turned at all")
    }

    /// **Fat is a handling cost.** This is why dropping is worth its price.
    func testFatMakesThePigSlowerAndWiderTurning() {
        var lean = emptyWorld(fat: 0), round = emptyWorld(fat: 1)
        run(&lean, frames: 600, intent(0, 1))
        run(&round, frames: 600, intent(0, 1))
        XCTAssertGreaterThan(lean.z[0], round.z[0] * 1.5,
                             "a fat pig must be markedly slower: lean went \(lean.z[0]) m, "
                             + "fat went \(round.z[0]) m")

        var leanTurn = emptyWorld(fat: 0), roundTurn = emptyWorld(fat: 1)
        Step.advance(&leanTurn, intent: intent(1, 0))
        Step.advance(&roundTurn, intent: intent(1, 0))
        XCTAssertGreaterThan(abs(leanTurn.heading[0]), abs(roundTurn.heading[0]),
                             "a fat pig must turn more slowly")
    }

    func testThePigNeverLeavesThePaddock() {
        var w = emptyWorld(fat: 0)
        for f in 0..<4000 {
            let a = Double(f) * 0.0031
            Step.advance(&w, intent: intent(sin(a), cos(a)))
            let r = (w.x[0] * w.x[0] + w.z[0] * w.z[0]).squareRoot()
            XCTAssertLessThanOrEqual(r, c.paddockRadius + 1e-9,
                                     "the pig is \(r) m from the centre on frame \(f)")
        }
    }

    // MARK: - The gait

    func testTheGaitIsDrivenByDistanceAndNotByTime() {
        var still = emptyWorld()
        run(&still, frames: 300, intent())
        XCTAssertEqual(still.gait[0], 0, accuracy: 1e-12, "a standing pig's walk cycle advanced")

        // The phase is wrapped every cycle, so it is unwrapped here by accumulating per-frame deltas.
        func phasePerMetre(stick: Double) -> Double {
            var w = emptyWorld(fat: 0)
            var previous = w.gait[0], total = 0.0
            for _ in 0..<600 {
                Step.advance(&w, intent: intent(0, stick))
                var d = w.gait[0] - previous
                if d < -Double.pi { d += 2 * .pi }
                total += d
                previous = w.gait[0]
            }
            return total / w.z[0]
        }
        XCTAssertEqual(phasePerMetre(stick: 0.4), c.cadence, accuracy: 0.01,
                       "the walk cycle is not proportional to distance travelled")
        XCTAssertEqual(phasePerMetre(stick: 1.0), c.cadence, accuracy: 0.01,
                       "the walk cycle changed rate with speed")
    }

    // MARK: - Dropping

    /// It fires on the press. A held button drops once, which is what stops the cooldown from being
    /// a suggestion.
    func testDroppingFiresOnThePressAndNotOnTheHold() {
        var w = emptyWorld(fat: 0.9)
        run(&w, frames: 600, intent(drop: true))         // five seconds of holding it down
        XCTAssertEqual(w.dropAlive.data.reduce(0, +), Double(c.carrotsPerDrop),
                       "holding the button dropped more than once")
    }

    func testADropCostsFatAndStartsTheCooldown() {
        var w = emptyWorld(fat: 0.9)
        Step.advance(&w, intent: intent(drop: true))
        XCTAssertEqual(w.fat[0], 0.9 - c.dropFatCost - c.walkBurn * c.dt, accuracy: 1e-12)
        XCTAssertEqual(w.dropTimer[0], c.dropCooldown, accuracy: 1e-12)
        XCTAssertEqual(w.dropAlive.data.reduce(0, +), Double(c.carrotsPerDrop),
                       "one drop must put \(c.carrotsPerDrop) things on the ground")
    }

    func testTheCooldownActuallyBlocksASecondDrop() {
        var w = emptyWorld(fat: 1.0)
        Step.advance(&w, intent: intent(drop: true))
        Step.advance(&w, intent: intent())                       // release
        Step.advance(&w, intent: intent(drop: true))             // press again, far too soon
        XCTAssertEqual(w.dropAlive.data.reduce(0, +), Double(c.carrotsPerDrop),
                       "the cooldown did not block the second drop")

        run(&w, frames: Int(c.dropCooldown / c.dt) + 2, intent())
        Step.advance(&w, intent: intent(drop: true))
        XCTAssertEqual(w.dropAlive.data.reduce(0, +), Double(2 * c.carrotsPerDrop),
                       "the cooldown never expired")
    }

    func testAThinPigHasNothingToDrop() {
        var w = emptyWorld(fat: c.dropMinFat - 0.01)
        Step.advance(&w, intent: intent(drop: true))
        XCTAssertEqual(w.dropAlive.data.reduce(0, +), 0, "an empty pig dropped anyway")
        XCTAssertEqual(w.fat[0], c.dropMinFat - 0.01 - c.walkBurn * c.dt, accuracy: 1e-12,
                       "it was charged for a drop that never happened")
    }

    func testWhatLandsIsBehindThePig() {
        var w = emptyWorld(fat: 0.9)
        run(&w, frames: 240, intent(0, 1))               // walking along +z
        let z = w.z[0]
        Step.advance(&w, intent: intent(0, 1, drop: true))
        for i in 0..<w.dropSlots where w.dropAlive.data[i] > 0.5 {
            XCTAssertLessThan(w.dropZ.data[i], z, "something landed in front of the pig")
        }
    }

    // MARK: - Growing

    /// A fresh dropping is not food, and the only thing that changes that is time.
    func testADroppingIsInedibleUntilItHasGrown() {
        var w = emptyWorld(fat: 0.9)
        Step.advance(&w, intent: intent(drop: true))
        // Park the pig with its SNOUT on the patch — the mouth is what eats, and it is most of a
        // body length in front of the pig's own position.
        let snout = PigShape.scalar(fat: w.fat[0]).length * 0.5 + c.mouthReach
        w.heading = .zeros([1])
        w.x = Tensor(shape: [1], data: [w.dropX.data[0]])
        w.z = Tensor(shape: [1], data: [w.dropZ.data[0] - snout])
        let fat = w.fat[0]
        run(&w, frames: Int((c.growTime - 1) / c.dt), intent())
        XCTAssertEqual(w.eaten[0], 0, "the pig ate a dropping")
        XCTAssertLessThan(w.fat[0], fat, "fat went up while nothing edible existed")

        run(&w, frames: Int(2 / c.dt), intent())
        XCTAssertGreaterThan(w.eaten[0], 0, "the carrot never became edible")
    }

    func testRipenessIsAStraightReadOfAge() {
        let ages = Tensor(shape: [1, 3], data: [0, c.growTime / 2, c.growTime * 3])
        let r = World.ripeness(age: ages, in: c)
        XCTAssertEqual(r.data, [0, 0.5, 1], "ripeness must saturate at 1 and start at 0")
    }

    // MARK: - Eating

    func testEatingFillsThePigAndEmptiesTheCarrot() {
        var w = worldWithCarrot(at: 0.6)
        let fat0 = w.fat[0], amount0 = w.dropAmount.data[0]
        run(&w, frames: 30, intent())
        XCTAssertGreaterThan(w.fat[0], fat0, "the pig did not gain anything")
        XCTAssertLessThan(w.dropAmount.data[0], amount0, "the carrot did not shrink")
        XCTAssertEqual(w.fat[0] - fat0 + c.walkBurn * 0.25,
                       (amount0 - w.dropAmount.data[0]) * c.fatPerCarrotUnit, accuracy: 1e-9,
                       "fat gained does not match the food removed")
        XCTAssertTrue(w.eating[0] > 0.5, "the pig is eating but does not say so")
    }

    func testFinishingACarrotScoresItOnce() {
        var w = worldWithCarrot(at: 0.6)
        run(&w, frames: 400, intent())
        XCTAssertEqual(w.eaten[0], 1, "the carrot should have been counted exactly once")
        XCTAssertEqual(w.dropAlive.data[0], 0, "the finished carrot is still occupying its slot")
    }

    /// **The bite boundary is where the geometry says it is, to a millimetre.**
    ///
    /// Bisected rather than spot-checked, and compared against a closed form written from the config
    /// — snout offset plus mouth reach plus the carrot's own radius. If eating and drawing ever
    /// disagree about how big a carrot is, this is the test that fails.
    func testTheBiteBoundaryIsBracketedToAMillimetre() {
        let fat = 0.45
        let shape = PigShape.scalar(fat: fat)
        let ripe = Tensor(shape: [1], data: [1])
        let radius = World.dropRadius(amount: Tensor(shape: [1], data: [c.carrotUnit]),
                                      ripeness: ripe, in: c)[0]
        let expected = shape.length * 0.5 + c.mouthReach + radius + c.mouthReach

        func eats(at d: Double) -> Bool {
            var w = worldWithCarrot(at: d, fat: fat)
            Step.advance(&w, intent: intent())
            return w.dropAmount.data[0] < c.carrotUnit - 1e-12
        }

        XCTAssertTrue(eats(at: expected - 0.01), "a carrot just inside the mouth was not eaten")
        XCTAssertFalse(eats(at: expected + 0.01), "a carrot just out of reach was eaten anyway")

        var lo = expected - 0.5, hi = expected + 0.5
        for _ in 0..<40 {
            let mid = (lo + hi) / 2
            if eats(at: mid) { lo = mid } else { hi = mid }
        }
        XCTAssertEqual((lo + hi) / 2, expected, accuracy: 0.001,
                       "the reach the engine uses disagrees with the reach the config implies")
    }

    /// Two carrots within reach must feed the pig at the same rate as one. Eating everything the
    /// snout overlaps would make a patch silently worth three times a single carrot — and a patch is
    /// exactly what every drop produces.
    func testOnlyTheNearestCarrotIsEaten() {
        var w = worldWithCarrot(at: 0.9)
        var alive = w.dropAlive.data, zs = w.dropZ.data
        var amounts = w.dropAmount.data, ages = w.dropAge.data
        alive[1] = 1; zs[1] = 1.0; amounts[1] = c.carrotUnit; ages[1] = c.growTime
        w.dropAlive = Tensor(shape: w.dropAlive.shape, data: alive)
        w.dropZ = Tensor(shape: w.dropZ.shape, data: zs)
        w.dropAmount = Tensor(shape: w.dropAmount.shape, data: amounts)
        w.dropAge = Tensor(shape: w.dropAge.shape, data: ages)

        // The snout, not the pig, is what distance is measured from — so which carrot is "nearest"
        // is a question about the snout's position. Ask the engine's own reach for it.
        let snout = PigShape.scalar(fat: w.fat[0]).length * 0.5 + c.mouthReach
        let nearer = abs(0.9 - snout) <= abs(1.0 - snout) ? 0 : 1

        Step.advance(&w, intent: intent())
        let bites = [c.carrotUnit - w.dropAmount.data[0], c.carrotUnit - w.dropAmount.data[1]]
        XCTAssertEqual(bites[0] + bites[1], c.eatRate * c.dt, accuracy: 1e-12,
                       "the pig ate from more than one carrot in a frame")
        XCTAssertGreaterThan(bites[nearer], 0, "the carrot nearer the snout should be the one eaten")
        XCTAssertEqual(bites[1 - nearer], 0, accuracy: 1e-15)
    }

    // MARK: - The whole loop

    /// **Drop, wait, eat it all back — and come out ahead.**
    ///
    /// The end-to-end statement of the economy, played rather than computed: it drops, waits for the
    /// patch to grow, walks the pig onto each carrot in turn, and checks the books at the end. The
    /// config-level tests above say the exchange rate is right; this one says the engine actually
    /// implements it.
    func testAFullCycleEndsFatterThanItStarted() {
        var w = emptyWorld(fat: 0.9)
        let start = w.fat[0]
        Step.advance(&w, intent: intent(drop: true))
        XCTAssertEqual(w.fat[0], start - c.dropFatCost, accuracy: 1e-3)

        run(&w, frames: Int(c.growTime / c.dt) + 4, intent())

        var meals = 0
        for slot in 0..<w.dropSlots where w.dropAlive.data[slot] > 0.5 {
            // Teleport rather than drive: this test is about the exchange rate, and an autopilot
            // would be a second thing that could fail.
            let snout = PigShape.scalar(fat: w.fat[0]).length * 0.5 + c.mouthReach
            w.x = Tensor(shape: [1], data: [w.dropX.data[slot]])
            w.z = Tensor(shape: [1], data: [w.dropZ.data[slot] - snout])
            w.heading = .zeros([1])
            var guard_ = 0
            while w.dropAlive.data[slot] > 0.5 && guard_ < 400 {
                Step.advance(&w, intent: intent())
                guard_ += 1
            }
            meals += 1
        }

        XCTAssertEqual(meals, c.carrotsPerDrop, "the patch was not \(c.carrotsPerDrop) separate meals")
        XCTAssertEqual(Int(w.eaten[0]), c.carrotsPerDrop)
        XCTAssertGreaterThan(w.fat[0], start,
                             "a full cycle lost fat: started \(start), ended \(w.fat[0])")
    }

    // MARK: - The dog

    func testTheDogArrivesGivesUpAndComesBack() {
        var w = World(batch: 1, config: c, seed: 0xD06)
        w.dogTimer = .zeros([1])
        Step.advance(&w, intent: intent())
        XCTAssertTrue(w.dogActive[0] > 0.5, "the dog never arrived")

        // It gives up eventually, even with the pig standing still in front of it… as long as it
        // does not reach it first, so park the pig far away by moving the dog's target out of reach.
        var chased = 0
        while w.dogActive[0] > 0.5 && chased < Int(c.dogHunt.upperBound * 2 / c.dt) {
            // Flee directly away from it, at full speed, as a lean pig.
            let dx = w.x[0] - w.dogX[0], dz = w.z[0] - w.dogZ[0]
            let d = max(1e-6, (dx * dx + dz * dz).squareRoot())
            w.fat = .zeros([1])
            Step.advance(&w, intent: intent(dx / d, dz / d))
            chased += 1
        }
        XCTAssertFalse(w.dogActive[0] > 0.5, "the dog never gave up")
        XCTAssertGreaterThan(w.dogTimer[0], 0, "it did not go away for a rest")
    }

    /// **A lean pig outruns the dog; a fat one cannot.** The single most important consequence of the
    /// whole design, and the reason the drop button exists.
    func testALeanPigEscapesAndAFatPigIsCaught() {
        // The dog starts close, so five seconds is enough to settle the question either way. At the
        // shipping spawn distance a fat pig is still caught, but only after eleven seconds — a
        // slower test that measures the same thing.
        var near = c
        near.dogSpawnDistance = 4

        func flee(fat: Double) -> Bool {
            var w = World(batch: 1, config: near, seed: 0xD09)
            w.fat = Tensor(shape: [1], data: [fat])
            w.dropAlive = .zeros([1, w.dropSlots])       // no snacks to stop for
            w.dogTimer = .zeros([1])
            var caught = false
            for _ in 0..<600 {                            // five seconds
                let dx = w.x[0] - w.dogX[0], dz = w.z[0] - w.dogZ[0]
                let d = max(1e-6, (dx * dx + dz * dz).squareRoot())
                w.fat = Tensor(shape: [1], data: [fat])   // hold the weight fixed for the experiment
                Step.advance(&w, intent: intent(dx / d, dz / d))
                if w.dogCaught[0] > 0.5 { caught = true }
            }
            return caught
        }
        XCTAssertFalse(flee(fat: 0.0), "a lean pig was caught — the dog is too fast")
        XCTAssertTrue(flee(fat: 1.0), "a fat pig escaped — the dog is too slow")
    }

    /// Being caught shakes fat loose, and what it shakes loose lands on the ground: the punishment is
    /// also, in nine seconds, lunch.
    func testBeingCaughtCostsFatAndLeavesItOnTheGround() {
        var w = World(batch: 1, config: c, seed: 0xD11)
        w.fat = Tensor(shape: [1], data: [1.0])
        w.dropAlive = .zeros([1, w.dropSlots])
        w.dogTimer = .zeros([1])
        var caughtAt: Double?
        for _ in 0..<900 {
            w.fat = Tensor(shape: [1], data: [min(1.0, w.fat[0])])
            let before = w.fat[0]
            Step.advance(&w, intent: intent())
            if w.dogCaught[0] > 0.5 { caughtAt = before; break }
        }
        let before = try? XCTUnwrap(caughtAt)
        XCTAssertNotNil(before, "the dog never caught a stationary fat pig")
        XCTAssertEqual(w.fat[0], (before ?? 0) - c.dogFright - c.walkBurn * c.dt, accuracy: 1e-9)
        XCTAssertEqual(w.dropAlive.data.reduce(0, +), Double(c.carrotsPerDrop),
                       "the fright did not land on the ground")
        XCTAssertFalse(w.dogActive[0] > 0.5, "the dog stayed after catching it")
    }

    // MARK: - Fat is bounded

    func testFatIsClampedToTheUnitInterval() {
        var full = worldWithCarrot(at: 0.6, amount: 1e9)
        run(&full, frames: 6000, intent())
        XCTAssertLessThanOrEqual(full.fat[0], 1)
        XCTAssertGreaterThan(full.fat[0], 0.99, "the pig should be able to reach maximum fatness")

        var empty = emptyWorld(fat: 0.05)
        run(&empty, frames: 60_000, intent())
        XCTAssertGreaterThanOrEqual(empty.fat[0], 0)
    }

    // MARK: - Slots

    func testSlotsAreRecycledAndNeverOverflow() {
        var w = World(batch: 1, config: c, seed: 0x51EED)
        for f in 0..<20_000 {
            // Drop whenever it is allowed, and never eat: the worst case for slot pressure.
            Step.advance(&w, intent: intent(drop: f % 8 == 0))
            let live = w.dropAlive.data.reduce(0, +)
            XCTAssertLessThanOrEqual(live, Double(w.dropSlots), "more drops than slots on frame \(f)")
        }
    }

    func testEverythingDroppedStaysInsideThePaddock() {
        var w = World(batch: 1, config: c, seed: 0x11AA)
        for f in 0..<6000 {
            let a = Double(f) * 0.004
            Step.advance(&w, intent: intent(sin(a), cos(a), drop: f % 9 == 0))
            for i in 0..<w.dropSlots where w.dropAlive.data[i] > 0.5 {
                let r = (w.dropX.data[i] * w.dropX.data[i] + w.dropZ.data[i] * w.dropZ.data[i])
                    .squareRoot()
                XCTAssertLessThanOrEqual(r, c.paddockRadius + c.carrotSpread + c.dropBehind + 1e-9,
                                         "something landed outside the fence")
            }
        }
    }

    // MARK: - Determinism and batching

    func testTheSameSeedProducesTheSameRunToTheBit() {
        func play(_ seed: UInt64) -> UInt64 {
            var w = World(batch: 1, config: c, seed: seed)
            for f in 0..<2000 {
                let a = Double(f) * 0.004
                Step.advance(&w, intent: intent(sin(a), cos(a), drop: f % 300 == 0))
            }
            return digest(w)
        }
        XCTAssertEqual(play(0xC0FFEE), play(0xC0FFEE), "the same seed diverged")
        XCTAssertNotEqual(play(0xC0FFEE), play(0xC0FFEF), "two different seeds played identically")
    }

    /// **World 0 is unaffected by how many worlds accompany it.**
    ///
    /// The property the whole batch-first layout exists for, and the one that a shape-dependent RNG
    /// silently destroys.
    func testABatchOfOneMatchesTheSameWorldInsideABatchOfSixtyFour() {
        let seed: UInt64 = 0x9A17
        var alone = World(batch: 1, config: c, seed: seed)
        var crowd = World(batch: 64, config: c, seed: seed)

        for f in 0..<1500 {
            let a = Double(f) * 0.004
            let d = f % 250 == 0
            Step.advance(&alone, intent: intent(sin(a), cos(a), drop: d))
            Step.advance(&crowd, intent: Intent(
                moveX: Tensor(repeating: sin(a), shape: [64]),
                moveZ: Tensor(repeating: cos(a), shape: [64]),
                drop: Tensor(repeating: d ? 1 : 0, shape: [64])))
        }

        XCTAssertEqual(alone.x[0], crowd.x[0], "x diverged")
        XCTAssertEqual(alone.z[0], crowd.z[0], "z diverged")
        XCTAssertEqual(alone.fat[0], crowd.fat[0], "fat diverged")
        XCTAssertEqual(alone.eaten[0], crowd.eaten[0], "score diverged")
        XCTAssertEqual(alone.dogX[0], crowd.dogX[0], "the dog diverged")
        XCTAssertEqual(alone.dropX.row(0), crowd.dropX.row(0), "the food differs")
    }

    /// The snapshot the renderer reads must agree with the state the engine holds — it is the only
    /// thing standing between "the physics is right" and "what you see is right".
    func testTheSnapshotAgreesWithTheWorld() {
        var w = worldWithCarrot(at: 0.6, fat: 0.4)
        run(&w, frames: 300, intent(0, 1))
        let s = w.snapshot()
        XCTAssertEqual(Double(s.x), w.x[0], accuracy: 1e-6)
        XCTAssertEqual(Double(s.fat), w.fat[0], accuracy: 1e-6)
        XCTAssertEqual(Double(s.heading), w.heading[0], accuracy: 1e-6)
        XCTAssertEqual(s.shape.belly, PigShape.scalar(fat: w.fat[0]).belly,
                       "the drawn body is not the simulated body")
        XCTAssertEqual(s.dropAlive.count, w.dropSlots, "slots must be handed over whole, dead ones too")
        XCTAssertEqual(s.dropReadiness, 1, "a pig that has not dropped should be ready to")
    }
}

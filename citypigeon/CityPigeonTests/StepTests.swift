import XCTest
import MLX
@testable import CityPigeon

/// The game step: determinism, batch invariance, slot hygiene, and whether the thing is playable.
final class StepTests: XCTestCase {

    let w = WorldConfig.shipping

    /// The shipping tuning with the hazard switched off.
    ///
    /// Tests in this file measure the **scoring loop** and **coordinate hygiene**. Once the flock
    /// existed they started measuring survival instead — two of eight worlds came back with a score
    /// of zero and the odometer test recorded 44 m instead of 800, because the pilot had crashed and
    /// frozen. Both were correct reports of a game that now has a fail state, and both were the wrong
    /// question for the test asking them. Mortality is `FlockAndSlotTests`' subject; here it is noise.
    var noFlock: WorldConfig {
        var c = w
        c.minFlock = 0
        c.maxFlock = 0
        return c
    }

    private func run(batch: Int, steps: Int, seed: UInt64 = 99) -> World {
        var world = World(batch: batch, config: noFlock, seed: seed)
        for _ in 0..<steps {                    // host time loop; the STEP contains no loops
            Step.advance(&world, intent: Policy.autopilot(world))
            Step.rebaseIfDue(&world)
        }
        world.evaluate()
        return world
    }

    // MARK: - It is actually a game

    /// **The end-to-end test.** A pilot built from the same functions the oracle certifies must be
    /// able to score. If this fails, some pair of {config, closed form, window, spawner, step}
    /// disagree, and no unit test would tell you which.
    func testTheAutopilotReliablyScores() {
        let world = run(batch: 8, steps: 3600)          // one minute at 60 Hz, eight worlds
        let scores = world.score.asArray(Float.self)
        let dropped = world.droppedReleases.asArray(Float.self)
        print("STEP autopilot after 60 s: scores \(scores.map { Int($0) }), "
              + "dropped releases \(dropped.map { Int($0) })")

        for (i, s) in scores.enumerated() {
            XCTAssertGreaterThan(s, 0, "world \(i) scored nothing in a minute of play — the loop is "
                                 + "not closing somewhere between spawn and impact")
        }
        // Not a stunt: the guarantee is that targets are hittable, so a pilot using the same
        // mathematics should hit a good share of them.
        XCTAssertGreaterThan(scores.reduce(0, +) / Float(scores.count), 1000,
                             "the autopilot scores, but barely — the windows may be technically fair "
                             + "and practically unusable")
    }

    /// Slots must always be recycled. A leak shows up as the game quietly refusing to fire.
    func testPayloadSlotsNeverLeak() {
        var world = World(batch: 4, config: noFlock, seed: 3)
        for _ in 0..<3600 {
            Step.advance(&world, intent: Policy.autopilot(world))
            Step.rebaseIfDue(&world)
        }
        world.evaluate()
        let live = which(world.payAlive, MLXArray(Float(1)), MLXArray(Float(0))).sum(axis: 1)
        for (i, n) in live.asArray(Float.self).enumerated() {
            XCTAssertLessThan(n, Float(w.payloadSlots),
                              "world \(i) ended with every payload slot occupied — impacts are not "
                              + "retiring their slots")
        }
    }

    /// Every payload must eventually land, whether or not it hits anything. A payload with no
    /// scheduled impact would hold its slot forever.
    func testEveryLivePayloadHasAFutureImpact() {
        let world = run(batch: 4, steps: 900)
        let alive = world.payAlive.asArray(Bool.self)
        let impact = world.payImpactTime.asArray(Float.self)
        let t = Float(world.frame) * Float(w.dt)
        for (i, isAlive) in alive.enumerated() where isAlive {
            XCTAssertGreaterThan(impact[i], t - 1e-3,
                                 "a live payload's impact is already in the past — it will never retire")
            XCTAssertLessThan(impact[i], t + 10,
                              "a live payload is scheduled to land more than ten seconds out")
        }
    }

    // MARK: - Determinism

    /// Same seed, same run. Everything downstream — replay, batch testing, RL — needs this.
    func testTheSameSeedProducesTheSameRun() {
        let a = run(batch: 2, steps: 600, seed: 12345)
        let b = run(batch: 2, steps: 600, seed: 12345)
        XCTAssertEqual(a.score.asArray(Float.self), b.score.asArray(Float.self))
        XCTAssertEqual(a.pigeonX.asArray(Float.self), b.pigeonX.asArray(Float.self))
        XCTAssertEqual(a.tgtX0.asArray(Float.self), b.tgtX0.asArray(Float.self))
        XCTAssertEqual(a.payImpactTime.asArray(Float.self), b.payImpactTime.asArray(Float.self))
    }

    func testDifferentSeedsProduceDifferentRuns() {
        let a = run(batch: 1, steps: 600, seed: 1)
        let b = run(batch: 1, steps: 600, seed: 2)
        XCTAssertNotEqual(a.tgtX0.asArray(Float.self), b.tgtX0.asArray(Float.self))
    }

    /// **Batch invariance — the claim the whole architecture rests on.**
    ///
    /// "One world and ten thousand worlds are the same code path" means world *i* must be unaffected
    /// by how many neighbours it was computed alongside. It does **not** mean the worlds agree with
    /// each other — they must not, or a batch of 64 is 64 copies of one run and worth nothing for
    /// training. So: world 0 alone must equal world 0 in company, and the others must differ.
    ///
    /// This failed on the first run, and the cause was worth finding: `MLXRandom.uniform(shape:key:)`
    /// yields a different sequence for a different output shape, so world 0 drew different traffic
    /// at B=1 than at B=64. Hashing the world index directly fixed it. MLX GPU reductions are also
    /// not contractually bitwise batch-invariant, so this stays as a standing check rather than an
    /// assumption.
    func testAWorldIsUnaffectedByItsNeighbours() {
        let alone = run(batch: 1, steps: 900, seed: 777)
        let crowded = run(batch: 64, steps: 900, seed: 777)

        let soloScore = alone.score.asArray(Float.self)[0]
        let soloX = alone.pigeonX.asArray(Float.self)[0]
        let batchScores = crowded.score.asArray(Float.self)
        let batchX = crowded.pigeonX.asArray(Float.self)

        print("STEP batch invariance: world 0 solo \(soloScore), in a batch of 64 \(batchScores[0])")
        XCTAssertEqual(batchScores[0], soloScore,
                       "world 0 scored differently depending on batch size — the step is not "
                       + "batch-invariant, and every claim about batched sweeps rests on it")
        XCTAssertEqual(batchX[0], soloX, accuracy: 1e-4)

        // And the batch must actually be a batch.
        let distinct = Set(batchScores.map { Int($0) })
        print("STEP batch diversity: \(distinct.count) distinct scores across 64 worlds")
        XCTAssertGreaterThan(distinct.count, 10,
                             "64 worlds produced only \(distinct.count) distinct outcomes — the "
                             + "per-world RNG is not decorrelating, so batched training would be "
                             + "learning from near-duplicates")
    }

    /// The engine must never reach for the system RNG. One call and replay is gone.
    func testTheRunIsReproducibleAcrossInterleavedWork() {
        var a = World(batch: 2, config: noFlock, seed: 42)
        var b = World(batch: 2, config: noFlock, seed: 42)
        for _ in 0..<300 {
            Step.advance(&a, intent: Policy.autopilot(a))
            // Interleave unrelated random work; a stateful generator would desynchronise here.
            _ = Rng.uniform([16], seed: 999, frame: 7, stream: .targetKind)
            Step.advance(&b, intent: Policy.autopilot(b))
        }
        a.evaluate(); b.evaluate()
        XCTAssertEqual(a.score.asArray(Float.self), b.score.asArray(Float.self))
    }

    // MARK: - Float32 hygiene

    /// The rebase must keep coordinates small without changing the game.
    func testRebaseKeepsCoordinatesBoundedAndChangesNothing() {
        var world = World(batch: 2, config: noFlock, seed: 5)
        var maxAbsX: Float = 0
        for _ in 0..<(Step.rebaseInterval * 4) {
            Step.advance(&world, intent: Policy.autopilot(world))
            Step.rebaseIfDue(&world)
            maxAbsX = max(maxAbsX, abs(world.pigeonX.asArray(Float.self)[0]))
        }
        world.evaluate()
        let travelled = world.odometer[0] + Double(world.pigeonX.asArray(Float.self)[0])
        print("STEP rebase: |x| stayed under \(maxAbsX) m while travelling \(Int(travelled)) m")

        XCTAssertLessThan(maxAbsX, 1500, "the rebase is not keeping x small")
        XCTAssertGreaterThan(travelled, 700, "the odometer is not accumulating the real distance")
    }

    /// No lane may ever go non-finite. One NaN would propagate through the reductions and corrupt
    /// every world in the batch.
    func testNoLaneEverGoesNonFinite() {
        let world = run(batch: 16, steps: 1800, seed: 8)
        for (name, a) in [("pigeonX", world.pigeonX), ("pigeonY", world.pigeonY),
                          ("score", world.score), ("payImpactX", world.payImpactX),
                          ("payImpactTime", world.payImpactTime), ("tgtX0", world.tgtX0)] {
            XCTAssertTrue(a.asArray(Float.self).allSatisfy { $0.isFinite }, "\(name) went non-finite")
        }
    }

    // MARK: - Anti-spam

    /// Holding the button forever must not produce a stream of payloads: the reserve has to bite.
    func testSpammingIsRateLimitedByTheReserve() {
        var world = World(batch: 1, config: noFlock, seed: 11)
        var releases = 0
        // Alternate hold/release as fast as the frame rate allows — the worst-case spammer.
        for i in 0..<600 {
            let hold = MLXArray([i % 2 == 0])
            let before = world.ammo.item(Float.self)
            Step.advance(&world, intent: Intent(moveX: MLXArray.zeros([1]),
                                                moveY: MLXArray.zeros([1]), hold: hold))
            if world.ammo.item(Float.self) < before { releases += 1 }
        }
        let seconds = 600 * w.dt
        let rate = Double(releases) / seconds
        print("STEP spam: \(releases) releases in \(seconds) s = \(rate)/s")
        // Sustained rate is bounded by regeneration, plus the initial full reserve.
        XCTAssertLessThan(rate, w.ammoRegenPerSecond * 2.5,
                          "a button masher achieved \(rate) drops/s against a \(w.ammoRegenPerSecond)/s "
                          + "regen — the reserve is not limiting anything")
    }
}

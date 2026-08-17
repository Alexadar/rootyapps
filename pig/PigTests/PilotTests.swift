import XCTest
@testable import Pig

/// The scripted pilot, measured rather than described.
///
/// Written in the house style for this kind of test: **assert the effect, not an absolute.** An
/// absolute ("the pilot eats at least N carrots") is a number nobody can defend and that has to be
/// re-tuned every time the economy moves. The effect ("the pilot eats materially more than a pig
/// that does nothing") is what the pilot is actually for, and it stays true across retuning.
///
/// Sample counts are cut per test to keep the suite quick — the Foundation `Tensor` is scalar loops,
/// so a batch of 64 stepped for a minute is 64 × 7200 kernel passes.
final class PilotTests: XCTestCase {

    private let c = WorldConfig.shipping

    /// Run `worlds` seeded worlds for `seconds` and return the per-world carrot count and the number
    /// of times the dog got hold of them.
    private func play(worlds: Int, seconds: Double, seed: UInt64,
                      pilot: Bool) -> (eaten: [Double], caught: [Double], fat: [Double]) {
        var w = World(batch: worlds, config: c, seed: seed)
        var caught = [Double](repeating: 0, count: worlds)
        let steps = Int(seconds / c.dt)
        for _ in 0..<steps {
            let intent = pilot ? Pilot.intent(w) : Intent.idle(batch: worlds)
            Step.advance(&w, intent: intent)
            let hits = w.dogCaught.data
            for i in 0..<worlds where hits[i] > 0.5 { caught[i] += 1 }
        }
        return (w.eaten.data, caught, w.fat.data)
    }

    /// **The end-to-end test.** If the loop is broken anywhere between "there is a carrot" and "the
    /// pig is fatter", a pilot that only ever walks at food will find it.
    func testThePilotFeedsItself() {
        let run = play(worlds: 8, seconds: 45, seed: 0xF00D, pilot: true)
        for (i, n) in run.eaten.enumerated() {
            XCTAssertGreaterThan(n, 0, "world \(i) never ate anything — the loop is not closing")
        }
        let mean = run.eaten.reduce(0, +) / Double(run.eaten.count)
        XCTAssertGreaterThan(mean, 3,
                             "the pilot averaged \(mean) carrots in 45 s; the three it starts beside "
                             + "are free, so anything at or under 3 means it never grew its own")
    }

    /// A pig that does nothing eats nothing. Stated because it is the baseline every other claim here
    /// is measured against, and because it would catch a world that force-feeds itself.
    func testDoingNothingFeedsNobody() {
        let idle = play(worlds: 4, seconds: 30, seed: 0xF00D, pilot: false)
        XCTAssertEqual(idle.eaten.reduce(0, +), 0, "a pig standing still ate a carrot")
    }

    /// **The pilot escapes what an idle pig does not.** This is the property the whole fat/speed
    /// design exists to produce, and the one thing the pilot genuinely does well: it runs, and it
    /// drops when it is too heavy to outrun what is chasing it.
    func testFleeingAndDroppingBeatStandingStill() {
        let seconds = 60.0
        let idle = play(worlds: 10, seconds: seconds, seed: 0xD06, pilot: false)
        let flee = play(worlds: 10, seconds: seconds, seed: 0xD06, pilot: true)

        let idleCaught = idle.caught.reduce(0, +)
        let fleeCaught = flee.caught.reduce(0, +)
        XCTAssertGreaterThan(idleCaught, 0, "the dog never caught a stationary pig in ten worlds")
        XCTAssertLessThan(fleeCaught, idleCaught,
                          "fleeing (\(fleeCaught) catches) was no better than standing there "
                          + "(\(idleCaught)) — the pilot is not using the speed it pays for")
    }

    /// It must not park itself: a pilot that walks into the fence and stays there films badly and
    /// measures nothing. Checked as distance covered, which is the symptom a viewer would see.
    func testThePilotKeepsMoving() {
        var w = World(batch: 4, config: c, seed: 0x60)
        var travelled = [Double](repeating: 0, count: 4)
        var lastX = w.x.data, lastZ = w.z.data
        for _ in 0..<Int(40 / c.dt) {
            Step.advance(&w, intent: Pilot.intent(w))
            for i in 0..<4 {
                let dx = w.x.data[i] - lastX[i], dz = w.z.data[i] - lastZ[i]
                travelled[i] += (dx * dx + dz * dz).squareRoot()
            }
            lastX = w.x.data; lastZ = w.z.data
        }
        for (i, d) in travelled.enumerated() {
            XCTAssertGreaterThan(d, 20, "world \(i) covered only \(d) m in 40 s — the pilot is stuck")
        }
    }

    /// The pilot asks for a drop when it is heavy, and the engine's cooldown is what decides whether
    /// it gets one. Asserted at the seam so a change to either side shows up here.
    func testAHeavyPilotAsksToDrop() {
        var heavy = World(batch: 1, config: c, seed: 1)
        heavy.fat = Tensor(shape: [1], data: [0.95])
        XCTAssertGreaterThan(Pilot.intent(heavy).drop[0], 0.5, "a very fat pilot did not ask to drop")

        var light = World(batch: 1, config: c, seed: 1)
        light.fat = Tensor(shape: [1], data: [0.2])
        light.dogActive = .zeros([1])
        XCTAssertLessThan(Pilot.intent(light).drop[0], 0.5, "a thin pilot dropped for no reason")
    }

    /// Goals steer it: `.walk` sends it somewhere specific, `.wait` stops it dead.
    func testTheScenarioGoalsOverrideTheDefaultBehaviour() {
        var w = World(batch: 1, config: c, seed: 7)
        w.dogTimer = Tensor(shape: [1], data: [1e9])
        for _ in 0..<Int(6 / c.dt) {
            Step.advance(&w, intent: Pilot.intent(w, goal: .walk(x: 6, z: -4)))
        }
        let gap = ((w.x[0] - 6) * (w.x[0] - 6) + (w.z[0] + 4) * (w.z[0] + 4)).squareRoot()
        XCTAssertLessThan(gap, 1.5, "`.walk` did not arrive: still \(gap) m away")

        let before = (w.x[0], w.z[0])
        for _ in 0..<Int(2 / c.dt) {
            Step.advance(&w, intent: Pilot.intent(w, goal: .wait))
        }
        XCTAssertEqual(w.x[0], before.0, accuracy: 0.05, "`.wait` wandered off")
        XCTAssertEqual(w.z[0], before.1, accuracy: 0.05, "`.wait` wandered off")
    }

    /// **World 0 is unaffected by how many worlds accompany it**, through the pilot as well as the
    /// step — otherwise a batched sweep would be measuring a different pilot from the one that plays.
    func testThePilotIsBatchInvariant() {
        var alone = World(batch: 1, config: c, seed: 0xB1)
        var crowd = World(batch: 32, config: c, seed: 0xB1)
        for _ in 0..<1200 {
            Step.advance(&alone, intent: Pilot.intent(alone))
            Step.advance(&crowd, intent: Pilot.intent(crowd))
        }
        XCTAssertEqual(alone.x[0], crowd.x[0], "x diverged")
        XCTAssertEqual(alone.fat[0], crowd.fat[0], "fat diverged")
        XCTAssertEqual(alone.eaten[0], crowd.eaten[0], "score diverged")
    }
}

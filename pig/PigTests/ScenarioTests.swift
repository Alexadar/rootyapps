import XCTest
@testable import Pig

/// The filmed run, checked without filming anything.
///
/// `Scenario` is a pure function of elapsed time, which is the entire reason it is worth writing that
/// way: every beat of a forty-second take can be checked in milliseconds, and a recording that goes
/// wrong is a bug in something else.
final class ScenarioTests: XCTestCase {

    private let c = WorldConfig.shipping

    func testTheBeatsRunInOrderAndCoverTheWholeTake() {
        let s = Scenario()
        var seen: [String] = []
        var t = 0.0
        while t < Scenario.duration {
            let key = s.beat(at: t).key
            if seen.last != key { seen.append(key) }
            t += 0.05
        }
        XCTAssertEqual(seen, ["walk", "eat", "fatten", "drop", "grow", "dog"],
                       "the beats did not play in order, or one was skipped entirely")
    }

    func testTheBoundariesTileTheTakeWithoutGapsOrOverlaps() {
        let bounds = Scenario.boundaries
        XCTAssertEqual(bounds.first?.start, 0)
        XCTAssertEqual(bounds.last?.end ?? 0, Scenario.duration, accuracy: 1e-9)
        for (a, b) in zip(bounds, bounds.dropFirst()) {
            XCTAssertEqual(a.end, b.start, accuracy: 1e-9,
                           "a gap between \(a.key) and \(b.key) would show as a caption flicker")
        }
    }

    /// The take has to fit the shot list it was written for, and it has to be long enough that the
    /// nine-second growth beat is actually witnessed rather than cut around.
    func testTheTakeIsAboutFortySecondsAndTheGrowthBeatOutlastsGrowing() {
        XCTAssertEqual(Scenario.duration, 42.5, accuracy: 0.01)
        let grow = Scenario.boundaries.first { $0.key == "grow" }
        XCTAssertNotNil(grow)
        XCTAssertGreaterThan((grow?.end ?? 0) - (grow?.start ?? 0), c.growTime,
                             "the growth beat is shorter than growing takes, so the payoff lands "
                             + "after the camera has moved on")
    }

    func testProgressRunsZeroToOneInsideEachBeatAndTheTakeEnds() {
        let s = Scenario()
        for b in Scenario.boundaries {
            XCTAssertEqual(s.beat(at: b.start + 1e-6).progress, 0, accuracy: 0.01,
                           "\(b.key) did not start at zero progress")
            XCTAssertGreaterThan(s.beat(at: b.end - 1e-6).progress, 0.98,
                                 "\(b.key) did not reach full progress")
        }
        XCTAssertFalse(s.beat(at: Scenario.duration - 0.5).isOver)
        XCTAssertTrue(s.beat(at: Scenario.duration + 0.5).isOver, "the take never ends")
    }

    /// Every beat has something to say, and no caption is long enough to wrap on a 1920×1080 frame.
    func testEveryBeatCarriesALegibleCaption() {
        let s = Scenario()
        for b in Scenario.boundaries {
            let caption = s.beat(at: (b.start + b.end) / 2).caption
            XCTAssertFalse(caption.isEmpty, "\(b.key) has no caption")
            XCTAssertLessThan(caption.count, 52, "\(b.key)'s caption will wrap: \"\(caption)\"")
        }
    }

    /// **The runner is driven by simulation time, not by a clock**, so two takes of the same seed are
    /// the same take. Advancing by `dt` a fixed number of times must land on exactly the same beat
    /// every run, on any machine, however slowly it got there.
    func testTheRunnerAdvancesOnSimulationTimeAlone() {
        func keyAfter(_ steps: Int) -> String {
            let r = ScenarioRunner()
            for _ in 0..<steps { r.advance(dt: c.dt) }
            return r.beat.key
        }
        XCTAssertEqual(keyAfter(600), keyAfter(600))
        XCTAssertEqual(keyAfter(Int(1 / c.dt)), "walk")
        XCTAssertEqual(keyAfter(Int(20 / c.dt)), "fatten")
        XCTAssertEqual(keyAfter(Int(41 / c.dt)), "dog")
    }

    /// **No beat may hang a recording.** The whole take is played by the real pilot against the real
    /// engine, from several seeds, and every beat must be reached — a scenario that stalls on one seed
    /// wastes a capture session and is invisible until someone watches the file.
    func testTheWholeTakePlaysThroughFromEverySeed() {
        for seed in [0x5EED_9160, 0x11, 0xA5A5, 0xBEEF] as [UInt64] {
            var w = World(batch: 1, config: c, seed: seed)
            let runner = ScenarioRunner()
            var reached: Set<String> = []
            while !runner.beat.isOver {
                let beat = runner.advance(dt: c.dt)
                reached.insert(beat.key)
                if beat.key == "dog" && w.dogActive[0] < 0.5 && w.dogTimer[0] > 0 {
                    w.dogTimer = .zeros([1])
                }
                Step.advance(&w, intent: Pilot.intent(w, goal: beat.goal))
                XCTAssertTrue(w.fat[0].isFinite, "seed \(seed) went non-finite during \(beat.key)")
            }
            XCTAssertEqual(reached.count, 6, "seed \(seed) only reached \(reached.sorted())")
            // The take is supposed to end with a fed pig and a story: it ate, it dropped, it survived.
            XCTAssertGreaterThan(w.eaten[0], 0, "seed \(seed) filmed a pig that never ate")
            XCTAssertGreaterThan(w.dropAlive.data.reduce(0, +), 0,
                                 "seed \(seed) filmed a field with nothing growing in it")
        }
    }

    /// The dog has to actually turn up during the beat named after it, or the last eight seconds of
    /// the video are a pig walking.
    func testTheDogArrivesDuringTheDogBeat() {
        var w = World(batch: 1, config: c, seed: 0x5EED_9160)
        let runner = ScenarioRunner()
        var sawDog = false
        while !runner.beat.isOver {
            let beat = runner.advance(dt: c.dt)
            if beat.key == "dog" && w.dogActive[0] < 0.5 && w.dogTimer[0] > 0 {
                w.dogTimer = .zeros([1])
            }
            Step.advance(&w, intent: Pilot.intent(w, goal: beat.goal))
            if beat.key == "dog" && w.dogActive[0] > 0.5 { sawDog = true }
        }
        XCTAssertTrue(sawDog, "the dog never showed up in its own beat")
    }
}

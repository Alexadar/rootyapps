import Foundation

/// The take, as arithmetic.
///
/// Pure on purpose: every beat of a filmed run is decided here, by a function of elapsed time and
/// nothing else. Ported in shape from `tarot/Tarot/Debug/ScenarioTimeline.swift`, including the two
/// disciplines that make takes comparable:
///
///  * **the clock is the simulation's own fixed `dt`, never `Date()`.** A dropped frame then slips the
///    pig and the script *together* instead of desynchronising them, so two recordings of the same
///    seed are the same recording.
///  * **named markers**, emitted once each, so a capture log can be aligned to the footage later
///    without anyone counting frames by eye.
///
/// It steers the pilot rather than replacing it: each beat hands `Pilot` a goal, and the pilot still
/// does the driving. What gets filmed is therefore the same policy the tests measure, which is the
/// whole reason not to write a separate "camera path" version of the game.
struct Scenario {

    /// What the director injects on a given frame.
    struct Beat: Equatable {
        var key: String
        var goal: Pilot.Goal
        /// Caption shown while this beat runs. Empty draws nothing.
        var caption: String
        /// Where the camera should sit, as a yaw offset from the pig's heading, and a pitch.
        var cameraYaw: Float
        var cameraPitch: Float
        /// How much of the beat has elapsed, 0…1. The caption fades on this.
        var progress: Float
        var isOver: Bool
    }

    /// One entry in the script.
    private struct Step {
        let key: String
        let seconds: Double
        let caption: String
        let yaw: Float
        let pitch: Float
        let goal: Pilot.Goal
    }

    /// **The basic-features run, in the order a person would learn them.**
    ///
    /// Six beats, about forty seconds. It is a demonstration reel, not a tutorial — this game ships
    /// silent by `docs/PRINCIPLES_game_design.md` §2, and the captions exist for the video only.
    ///
    /// The growth beat is the one that cannot be shortened: nine seconds is what a carrot takes, and
    /// showing it honestly is the point. The camera swings round the standing pig to cover it.
    private static let script: [Step] = [
        Step(key: "walk", seconds: 6.0, caption: "Walk the field",
             yaw: 0.5, pitch: 0.34, goal: .walk(x: 4.5, z: 5.0)),
        Step(key: "eat", seconds: 7.0, caption: "Eat a carrot — you get fatter",
             yaw: 0.1, pitch: 0.30, goal: .forage),
        Step(key: "fatten", seconds: 8.0, caption: "Fatter is slower, and wider through the turns",
             yaw: -0.6, pitch: 0.28, goal: .forage),
        Step(key: "drop", seconds: 4.0, caption: "Drop to get light again — it costs a few meals",
             yaw: -0.2, pitch: 0.40, goal: .drop),
        // Stand over the patch, not away from it: the first take walked the pig three metres off and
        // filmed nine seconds of grass while the payoff happened behind the camera. The drop lands
        // just behind the pig, so standing still is what keeps it in frame — and the raised pitch is
        // what makes the shoots visible from above.
        Step(key: "grow", seconds: 9.5, caption: "What you drop grows into three carrots",
             yaw: 0.9, pitch: 0.55, goal: .wait),
        Step(key: "dog", seconds: 8.0, caption: "The dog only catches a fat pig",
             yaw: 0.2, pitch: 0.32, goal: .play),
    ]

    static var duration: Double { script.reduce(0) { $0 + $1.seconds } }

    /// The beat at elapsed time `t`.
    ///
    /// A linear scan over six entries — a loop over the SCRIPT, not over worlds or slots, and the same
    /// exemption `VectorDisciplineTests` grants any loop whose bound is a constant of the program
    /// rather than a count of things being simulated. It is listed in that test's allowlist with this
    /// reason.
    func beat(at t: Double) -> Beat {
        var elapsed = 0.0
        for step in Scenario.script {
            if t < elapsed + step.seconds || step.key == Scenario.script.last?.key {
                let local = min(max((t - elapsed) / step.seconds, 0), 1)
                return Beat(key: step.key, goal: step.goal, caption: step.caption,
                            cameraYaw: step.yaw, cameraPitch: step.pitch,
                            progress: Float(local), isOver: t >= Scenario.duration)
            }
            elapsed += step.seconds
        }
        return Beat(key: "end", goal: .wait, caption: "", cameraYaw: 0, cameraPitch: 0.36,
                    progress: 1, isOver: true)
    }

    /// The beat boundaries, in seconds, for cutting captions onto the footage afterwards.
    static var boundaries: [(key: String, start: Double, end: Double)] {
        var out: [(String, Double, Double)] = []
        var t = 0.0
        for step in script {
            out.append((step.key, t, t + step.seconds))
            t += step.seconds
        }
        return out
    }
}

/// Drives one demo run: holds the clock, hands out beats, and logs each marker exactly once.
///
/// Separate from `Scenario` because `Scenario` is a pure function and this is the thing with state.
/// Keeping the arithmetic pure is what lets `ScenarioTests` check every beat without running a game.
final class ScenarioRunner {

    private let scenario = Scenario()
    private(set) var elapsed: Double = 0
    private var announced: Set<String> = []
    private(set) var beat: Scenario.Beat

    init() {
        beat = scenario.beat(at: 0)
    }

    /// Advance by one simulation step and return the beat to play.
    ///
    /// `dt` comes from `WorldConfig`, so the script runs on simulation time — see the note on
    /// `Scenario`. Markers go to stderr, which is where a capture script can read them without them
    /// landing in the game's own output.
    @discardableResult
    func advance(dt: Double) -> Scenario.Beat {
        if announced.isEmpty { mark("SCENARIO_T0") }
        elapsed += dt
        beat = scenario.beat(at: elapsed)
        mark("SCENARIO_BEAT \(beat.key)")
        if beat.isOver { mark("SCENARIO_END") }
        return beat
    }

    private func mark(_ text: String) {
        guard !announced.contains(text) else { return }
        announced.insert(text)
        FileHandle.standardError.write(Data("\(text) \(String(format: "%.3f", elapsed))\n".utf8))
    }
}

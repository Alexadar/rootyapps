import Foundation
import SwiftUI
import MLX

/// The seam between the player and the engine.
///
/// Holds one `World`, converts input into an `Intent`, advances the fixed-timestep simulation, and
/// publishes a `Snapshot` for the renderer and the HUD. It contains no rules and no physics — every
/// decision about what happens lives in `Engine/`, which is what lets the same engine run headless.
@MainActor
final class Game: ObservableObject {

    enum Phase { case menu, playing, over }

    let config: WorldConfig
    @Published private(set) var phase: Phase = .menu
    @Published private(set) var snapshot = Snapshot()
    @Published private(set) var bestScore: Float = 0

    /// Attract mode: the scripted pilot flies while nobody is playing. It is also what the demo
    /// recording captures, so what gets shown is real play rather than a puppet.
    @Published var autopilot = false

    var renderer: Renderer?

    private var world: World
    private var lastPayloadCount = 0
    private var elapsed: Double = 0

    /// Live input, written by the platform layers.
    var inputMove = SIMD2<Float>(0, 0)
    var inputHold = false

    /// Set by `CITYPIGEON_DEMO=1`: skip the menu and let the scripted pilot fly.
    ///
    /// This is how the demo clip is recorded, and it is deliberately the *same* code path as attract
    /// mode rather than a capture-only mode — a recording of a special build is a recording of
    /// something nobody can play.
    static let demoMode = ProcessInfo.processInfo.environment["CITYPIGEON_DEMO"] == "1"

    init(config: WorldConfig = .shipping) {
        self.config = config
        // A demo must be reproducible, so it gets a fixed seed rather than the clock.
        let seed: UInt64 = Game.demoMode ? 0x5EED_C170 : Game.freshSeed()
        self.world = World(batch: 1, config: config, seed: seed)
        self.bestScore = Float(UserDefaults.standard.double(forKey: "bestScore"))
        self.snapshot = world.snapshot()
        if Game.demoMode {
            self.autopilot = true
            self.phase = .playing
        }
    }

    /// A seed per session, taken from the wall clock **once, here, outside the engine**.
    ///
    /// The engine itself never touches a clock or a system RNG — that is what makes a run
    /// reproducible from its seed alone. Choosing which run to play is the one decision that is
    /// allowed to be arbitrary, and it happens exactly here.
    private static func freshSeed() -> UInt64 {
        UInt64(Date().timeIntervalSince1970 * 1000) & 0xFFFF_FFFF
    }

    func start() {
        world = World(batch: 1, config: config, seed: Game.freshSeed())
        elapsed = 0
        lastPayloadCount = 0
        phase = .playing
        snapshot = world.snapshot()
    }

    func backToMenu() {
        phase = .menu
        autopilot = true
    }

    /// One fixed simulation step.
    func tick() {
        guard phase == .playing || autopilot else { return }

        let intent: Intent
        if autopilot {
            intent = Policy.autopilot(world)
        } else {
            intent = Intent(moveX: MLXArray([inputMove.x]),
                            moveY: MLXArray([inputMove.y]),
                            hold: MLXArray([inputHold]))
        }

        Step.advance(&world, intent: intent)
        Step.rebaseIfDue(&world)
        elapsed += config.dt

        let s = world.snapshot()
        // Splats are the renderer's business, but only the game can see an impact happen: a payload
        // that was alive last frame and is gone this frame has landed.
        if s.payloads.liveCount < lastPayloadCount, let r = renderer {
            r.noteImpact(x: s.pigeonX + Float(config.cruiseSpeed) * 0.0, mass: 0.6, at: s.time)
        }
        lastPayloadCount = s.payloads.liveCount
        snapshot = s

        if phase == .playing, s.score > bestScore {
            bestScore = s.score
            UserDefaults.standard.set(Double(bestScore), forKey: "bestScore")
        }

        // The one fail state: hitting another pigeon ends the run.
        if !s.alive {
            if autopilot {
                // **Attract mode has to survive dying.** The scripted pilot flies behind the menu and
                // will eventually crash; showing it the game-over card would leave the menu sitting on
                // a frozen scene, which reads as a hang rather than as a death. Restart quietly with a
                // fresh seed instead. The demo recording depends on this too.
                world = World(batch: 1, config: config, seed: Game.freshSeed())
                elapsed = 0
                lastPayloadCount = 0
            } else if phase == .playing {
                phase = .over
            }
        }
    }

    /// Seconds of play, for the HUD.
    var playTime: Double { elapsed }
}

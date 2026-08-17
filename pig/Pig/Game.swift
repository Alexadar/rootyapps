import Foundation
import SwiftUI
import simd

/// The seam between the player and the engine.
///
/// Holds one `World`, converts input into an `Intent`, advances the fixed-timestep simulation, and
/// publishes what the HUD needs. It contains no rules and no physics — every decision about what
/// happens lives in `Engine/`, which is what lets the same engine run headless.
@MainActor
final class Game: ObservableObject {

    /// What the HUD draws. Deliberately NOT the whole snapshot: republishing 33 fields at 120 Hz
    /// would re-render the SwiftUI overlay on every simulation step, which costs more than the
    /// simulation does. The renderer reads `snapshot` directly and never goes through `@Published`.
    struct HUD: Equatable {
        var fat: Float = 0
        var eaten: Int = 0
        var dropReadiness: Float = 1
        var canDrop = false
        var eating = false
        var dogActive = false
        var dogClose = false
    }

    let config: WorldConfig
    @Published private(set) var hud = HUD()

    /// Read by the renderer every frame. Plain stored property on purpose — see `HUD`.
    private(set) var snapshot = Snapshot()

    weak var renderer: Renderer?

    private var world: World

    // MARK: - Live input, written by the platform layers
    //
    // `stick` is CAMERA-space: y is "away from the camera". The rotation into world space happens
    // here, in one place, so the engine never learns that a camera exists.

    var stick = SIMD2<Float>(0, 0)
    var look = SIMD2<Float>(0, 0)
    /// Held by the button; the engine takes the PRESS edge off it, so holding it down drops once.
    var dropHeld = false

    private(set) var cameraYaw: Float = 0
    private(set) var cameraPitch: Float = 0.36

    /// Rate at which the look control turns the camera, rad/s at full deflection.
    private let lookRate: Float = 2.6
    /// How fast the camera eases around to sit behind a moving pig, rad/s. Well under the pig's own
    /// turn rate, which is what keeps the camera-relative stick from oscillating.
    private static let followRate: Float = 1.5
    /// Pitch is clamped, never wrapped: past these the camera is inside the ground or overhead.
    private static let minPitch: Float = -0.05
    private static let maxPitch: Float = 0.85

    /// Inverted look, for the people who hold a camera rather than push a pivot. Off by default,
    /// which is the convention every mainstream third-person game ships with.
    var invertLook = false

    // MARK: - Demo mode
    //
    // `PIG_DEMO=1` hands the controls to the scripted pilot and runs the scenario. It is deliberately
    // the SAME code path as normal play — citypigeon's rule, and the reason its attract mode and its
    // recording are the same thing: a recording of a special build is a recording of something nobody
    // can play.

    static let demoMode = ProcessInfo.processInfo.environment["PIG_DEMO"] == "1"
    private let runner = ScenarioRunner()

    /// What the pilot is "pressing", plus the beat's caption — everything the recording overlays.
    ///
    /// One published struct, quantised and compared before assignment, for the same reason `HUD` is:
    /// publishing a `Float` that changes every frame re-renders the whole overlay at 120 Hz, which
    /// costs more than the simulation does.
    struct DemoOverlay: Equatable {
        var stick = SIMD2<Float>(0, 0)
        var look = SIMD2<Float>(0, 0)
        var drop = false
        var caption = ""
    }

    @Published private(set) var demo = DemoOverlay()


    init(config: WorldConfig = .shipping) {
        self.config = config
        // A demo must be reproducible, so it gets a fixed seed rather than the clock.
        self.world = World(batch: 1, config: config,
                           seed: Game.demoMode ? 0x5EED_9160 : Game.freshSeed())

        // The shape-inspection hook. `PIG_FAT=0.8 PIG_YAW=1.2` starts the game already that fat and
        // already turned, which is how the body is checked across its whole range without spending
        // two minutes eating. It sets simulation STATE and nothing else — there is no special render
        // path here, so what it shows is what the game draws.
        let env = ProcessInfo.processInfo.environment
        if let v = env["PIG_FAT"].flatMap(Double.init) {
            world.fat = Tensor(shape: [1], data: [min(max(v, 0), 1)])
        }
        if let v = env["PIG_YAW"].flatMap(Float.init) { cameraYaw = v }
        if let v = env["PIG_PITCH"].flatMap(Float.init) { cameraPitch = v }
        if env["PIG_DOG"] == "1" { world.dogTimer = .zeros([1]) }
        if env["PIG_STAGES"] == "1" { Game.layOutGrowthStages(&world) }

        self.snapshot = world.snapshot()
    }

    /// `PIG_STAGES=1` lines the six stages of growing up in a row in front of the pig, so the whole
    /// dropping-to-carrot progression can be checked in one frame rather than by waiting nine seconds
    /// six times. It writes simulation STATE and nothing else — there is no special render path, so
    /// what it shows is what the game draws.
    private static func layOutGrowthStages(_ w: inout World) {
        let k = w.dropSlots
        var alive = w.dropAlive.data, xs = w.dropX.data, zs = w.dropZ.data
        var ages = w.dropAge.data, amounts = w.dropAmount.data, look = w.dropLook.data
        for i in 0..<min(6, k) {
            alive[i] = 1
            xs[i] = Double(i) * 1.1 - 2.75
            zs[i] = 2.4
            ages[i] = w.config.growTime * Double(i) / 5
            amounts[i] = w.config.carrotUnit
            look[i] = Double(i) * 0.17
        }
        w.dropAlive = Tensor(shape: [1, k], data: alive)
        w.dropX = Tensor(shape: [1, k], data: xs)
        w.dropZ = Tensor(shape: [1, k], data: zs)
        w.dropAge = Tensor(shape: [1, k], data: ages)
        w.dropAmount = Tensor(shape: [1, k], data: amounts)
        w.dropLook = Tensor(shape: [1, k], data: look)
    }

    /// A seed per session, taken from the wall clock **once, here, outside the engine**.
    ///
    /// The engine itself never touches a clock or a system RNG — that is what makes a run
    /// reproducible from its seed alone. Choosing which run to play is the one decision that is
    /// allowed to be arbitrary, and it happens exactly here.
    private static func freshSeed() -> UInt64 {
        UInt64(Date().timeIntervalSince1970 * 1000) & 0xFFFF_FFFF
    }

    /// One fixed simulation step.
    func tick() {
        let dt = Float(config.dt)
        if Game.demoMode { tickDemo(dt: dt); return }

        // ── Look ────────────────────────────────────────────────────────────────────────────
        //
        // `look.x` is "drag right", `look.y` is "drag up", and both are non-inverted by the usual
        // convention: dragging right turns the view right, dragging up looks up.
        //
        // Both signs are SUBTRACTIONS, and neither is arbitrary. Yaw is measured from +z toward −x,
        // so turning the view right means yaw goes down; pitch is the camera's elevation above the
        // pig, so looking up means dropping the camera. Getting either backwards is invisible in the
        // code and instantly obvious in the hand — which is exactly what shipped in the first pass.
        cameraYaw -= look.x * lookRate * dt
        let pitchInput = look.y * (invertLook ? -1 : 1)
        cameraPitch = min(Game.maxPitch, max(Game.minPitch,
                                             cameraPitch - pitchInput * lookRate * 0.6 * dt))

        // ── The camera trails ───────────────────────────────────────────────────────────────
        //
        // Standard third-person behaviour: when the player is moving and is NOT touching the look
        // control, the camera eases around to sit behind them. It is slow enough that the player can
        // always overrule it, and it is what stops a long walk turning into a side-on view.
        //
        // It is stable despite looking like a feedback loop — the stick is camera-relative, so the
        // camera chases the pig's heading while the pig chases the stick — because the camera's rate
        // is well below the pig's turn rate, so the two converge rather than orbit.
        if abs(look.x) < 0.05 && snapshot.speed > 0.4 {
            let turn = CameraFrame.shortestTurn(from: cameraYaw, to: snapshot.heading)
            let cap = Game.followRate * dt * min(1, snapshot.speed / Float(config.walkSpeed))
            cameraYaw += max(-cap, min(cap, turn))
        }

        // ── Move ────────────────────────────────────────────────────────────────────────────
        //
        // Camera-relative, through the one shared basis: `y` is away from the camera, `x` is
        // screen-right. The pig then turns toward that world direction at its own rate.
        let dir = CameraFrame.worldDirection(stick: stick, yaw: cameraYaw)

        Step.advance(&world, intent: Intent(
            moveX: Tensor(shape: [1], data: [Double(dir.x)]),
            moveZ: Tensor(shape: [1], data: [Double(dir.y)]),
            drop: Tensor(shape: [1], data: [dropHeld ? 1 : 0])))

        snapshot = world.snapshot()
        // Pull in when looking up and out when looking down, which is the ordinary platformer rule
        // and keeps the pig from being buried behind its own shoulder at a low angle.
        let framing = 1 - 0.22 * (Game.maxPitch - cameraPitch) / (Game.maxPitch - Game.minPitch)
        renderer?.camera = Renderer.Camera(yaw: cameraYaw, pitch: cameraPitch,
                                           distance: 3.4 * framing)

        publishHUD()
    }

    /// The demo's step: the scenario picks a goal, the pilot flies it, the camera follows the script.
    ///
    /// Nothing here reaches into the engine that the player's path does not — the only difference is
    /// where the `Intent` comes from.
    private func tickDemo(dt: Float) {
        let beat = runner.advance(dt: config.dt)

        // The director's one direct intervention: staging the dog. It is on a random timer, so left
        // alone it wanders into the middle of the "fatter is slower" beat and steals its own reveal —
        // which is exactly what the first take filmed. Held off until its beat, then summoned.
        //
        // This sets simulation STATE, the same thing `PIG_DOG=1` does. The dog that arrives is the
        // real dog, running the real chase; only *when* it sets off is scripted.
        if beat.key == "dog" {
            if world.dogActive[0] < 0.5 && world.dogTimer[0] > 0 { world.dogTimer = .zeros([1]) }
        } else {
            world.dogActive = .zeros([1])
            world.dogTimer = Tensor(shape: [1], data: [1e9])
        }

        let intent = Pilot.intent(world, goal: beat.goal)

        // The ghost controls: the pilot's world-space direction projected back onto the camera's own
        // basis, which is exactly the deflection a thumb would have had to make. Going through
        // `CameraFrame` rather than re-deriving it means the drawn stick cannot disagree with the
        // movement it is supposed to explain.
        let dir = SIMD2<Float>(Float(intent.moveX[0]), Float(intent.moveZ[0]))
        let f = CameraFrame.forward(yaw: cameraYaw), r = CameraFrame.right(yaw: cameraYaw)
        let stick = SIMD2<Float>(dir.x * r.x + dir.y * r.y, dir.x * f.x + dir.y * f.y)

        Step.advance(&world, intent: intent)
        snapshot = world.snapshot()

        // The camera sits at a scripted offset from wherever the pig is facing, eased rather than cut
        // so the shot never snaps between beats.
        let wantYaw = snapshot.heading + beat.cameraYaw
        let yawStep = CameraFrame.shortestTurn(from: cameraYaw, to: wantYaw)
        let cap = Game.demoCameraRate * dt
        let applied = max(-cap, min(cap, yawStep))
        cameraYaw += applied
        let pitchStep = (beat.cameraPitch - cameraPitch) * min(1, dt / 0.6)
        cameraPitch += pitchStep
        let look = SIMD2<Float>(max(-1, min(1, -applied / (lookRate * dt))),
                                max(-1, min(1, -pitchStep / (lookRate * 0.6 * dt))))

        renderer?.camera = Renderer.Camera(yaw: cameraYaw, pitch: cameraPitch, distance: 3.4)

        let next = DemoOverlay(stick: Game.quantise(stick), look: Game.quantise(look),
                               drop: intent.drop[0] > 0.5, caption: beat.caption)
        if next != demo { demo = next }
        publishHUD()
    }

    /// How fast the demo camera may swing, rad/s. Slower than the player's, because a shot that whips
    /// around is unreadable on a forty-second recording.
    private static let demoCameraRate: Float = 1.1

    /// Round to twentieths, so a drifting stick republishes a few times a second instead of 120.
    private static func quantise(_ v: SIMD2<Float>) -> SIMD2<Float> {
        SIMD2((v.x * 20).rounded() / 20, (v.y * 20).rounded() / 20)
    }

    private func publishHUD() {
        // Publish only when something a human could read has actually changed.
        let next = HUD(fat: (snapshot.fat * 100).rounded() / 100,
                       eaten: snapshot.eaten,
                       dropReadiness: (snapshot.dropReadiness * 20).rounded() / 20,
                       canDrop: snapshot.canDrop,
                       eating: snapshot.eating,
                       dogActive: snapshot.dogActive,
                       dogClose: snapshot.dogActive && snapshot.dogDistance < 6)
        if next != hud { hud = next }
    }
}

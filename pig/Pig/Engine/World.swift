import Foundation

/// The whole game state, as Structure-of-Arrays with a leading batch dimension.
///
/// Every field is a `Tensor` whose first axis is the world index. `N = 1` is the game; `N = 512` is
/// the oracle sweep; they are the same arrays and the same kernel, which is the entire point of the
/// architecture. Nothing here is a Swift object per entity, and nothing is ever appended to —
/// capacities are fixed at init and slots are recycled by mask.
///
/// **Droppings and carrots are the same slot.** A carrot is a dropping that has been sitting for
/// `growTime`; there is no hand-off between two systems, no second array, and therefore no way for
/// "how many carrots exist" and "how many droppings grew" to disagree. `dropAge` is the only thing
/// that distinguishes them.
struct World {

    let batch: Int
    let dropSlots: Int
    let config: WorldConfig
    let seed: UInt64

    /// Lockstep across the whole batch. Time is `Double(frame) * dt` — never an accumulated sum, and
    /// never a frame delta.
    var frame: Int = 0
    var time: Double { Double(frame) * config.dt }

    // MARK: - The pig, [N]

    var x, z: Tensor
    var heading: Tensor          // radians; 0 faces +z
    var speed: Tensor            // m/s along the heading
    /// The one number the whole game is about. `Shape.swift` turns it into an animal.
    var fat: Tensor
    /// Radians of gait, advanced by DISTANCE travelled rather than by time.
    var gait: Tensor
    /// Second-order spring: the belly's displacement and its rate. Feel maths, in the engine where it
    /// can be tested, not in the renderer where it cannot.
    var wob, wobV: Tensor
    /// 1 on any frame where the pig took a bite.
    var eating: Tensor
    /// Carrots finished off. The score.
    var eaten: Tensor

    /// Seconds until the pig can drop again. Counting down rather than storing "when it last did"
    /// keeps the HUD's ring a straight read of state instead of a subtraction it could get wrong.
    var dropTimer: Tensor
    /// Whether the drop button was down last frame, so a drop fires on the press and not on the hold.
    var dropHeld: Tensor
    /// 1 on the frame a drop actually left. Drives the sound, the shove and the HUD flash.
    var dropped: Tensor

    // MARK: - Droppings and carrots, [N, K]

    var dropAlive: Tensor
    var dropX, dropZ: Tensor
    /// Seconds since it landed. Below `growTime` it is a dropping and inedible; above, a carrot.
    var dropAge: Tensor
    /// Carrot units remaining. Only meaningful once grown.
    var dropAmount: Tensor
    /// A per-slot `[0,1)` roll, purely so no two carrots look identical.
    var dropLook: Tensor

    // MARK: - The dog, [N]

    var dogActive: Tensor
    var dogX, dogZ: Tensor
    var dogGait: Tensor
    /// Counts down. While active it is time left to hunt; while inactive, time until it returns.
    var dogTimer: Tensor
    /// 1 on the frame it catches the pig.
    var dogCaught: Tensor

    init(batch: Int, config: WorldConfig = .shipping, seed: UInt64 = 0x9160_9160) {
        self.batch = batch
        self.config = config
        self.seed = seed
        self.dropSlots = config.dropSlots

        let n = [batch], nk = [batch, config.dropSlots]

        x = .zeros(n); z = .zeros(n)
        heading = .zeros(n)
        speed = .zeros(n)
        fat = Tensor(repeating: 0.45, shape: n)
        gait = .zeros(n)
        wob = .zeros(n); wobV = .zeros(n)
        eating = .zeros(n)
        eaten = .zeros(n)
        dropTimer = .zeros(n)
        dropHeld = .zeros(n)
        dropped = .zeros(n)

        // A few carrots are already up when the run starts. Without them the first thing the player
        // could do is drop, and the first thing they would learn is that the game makes you wait.
        let lane = Tensor.lanes(batch: batch, slots: config.dropSlots)
        let seeded = lane .< Double(config.startingCarrots)
        let angle = Rng.uniform(nk, seed: seed, frame: -1, stream: .dropAngle) * (2 * Double.pi)
        let radius = Rng.scaled(Rng.uniform(nk, seed: seed, frame: -2, stream: .dropRadius),
                                into: 3.5...9.0)

        dropAlive = seeded
        dropX = Tensor.which(seeded, angle.sine * radius, 0)
        dropZ = Tensor.which(seeded, angle.cosine * radius, 0)
        dropAge = Tensor.which(seeded, config.growTime, 0)
        dropAmount = Tensor.which(seeded, config.carrotUnit, 0)
        dropLook = Rng.uniform(nk, seed: seed, frame: -3, stream: .dropLook)

        dogActive = .zeros(n)
        dogX = .zeros(n); dogZ = .zeros(n)
        dogGait = .zeros(n)
        dogTimer = Rng.scaled(Rng.uniform(n, seed: seed, frame: -4, stream: .dogTimer),
                              into: config.dogRest)
        dogCaught = .zeros(n)
    }

    /// How grown a slot is, 0…1. One definition, read by the bite test in `Step` and by the renderer,
    /// so what looks edible is exactly what is edible.
    static func ripeness(age: Tensor, in c: WorldConfig) -> Tensor {
        (age / c.growTime).clamped(min: 0, max: 1)
    }

    /// A slot's drawn radius, from what is left of it.
    static func dropRadius(amount: Tensor, ripeness: Tensor, in c: WorldConfig) -> Tensor {
        // A dropping is a fixed lump; a carrot's reach shrinks as it is eaten.
        let dung = Tensor(repeating: 0.26, shape: amount.shape)
        let carrot = (amount / c.carrotUnit).clamped(min: 0, max: 1) * 0.18 + 0.10
        return Tensor.which(ripeness .>= 1, carrot, dung)
    }
}

/// What the player (or a scripted pilot) asks of the pig this step.
///
/// Shaped `[N]` so a human at `N = 1` and a sweep at `N = 512` present the same thing to the engine.
/// There is no separate "human" code path, which is what stops the two drifting.
///
/// `moveX`/`moveZ` are a **world-space** direction, already rotated out of camera space by the input
/// layer: the engine knows nothing about where the camera is pointing, and the camera is not
/// simulation state.
struct Intent {
    var moveX: Tensor
    var moveZ: Tensor
    /// 0/1. The drop fires on the frame this goes down, not while it is held.
    var drop: Tensor

    static func idle(batch n: Int) -> Intent {
        Intent(moveX: .zeros([n]), moveZ: .zeros([n]), drop: .zeros([n]))
    }
}

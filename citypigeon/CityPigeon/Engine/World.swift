import Foundation
import MLX

/// The whole game state, as Structure-of-Arrays with a leading batch dimension.
///
/// Every field is an `MLXArray` whose first axis is the world index. `B = 1` is the game; `B = 10000`
/// is a batched sweep; they are the same arrays and the same kernel, which is the entire point of
/// the architecture. Nothing here is a Swift object per entity, and nothing is ever appended to —
/// capacities are fixed at init and slots are recycled by mask.
///
/// **Payloads and targets are never integrated.** Each carries `(state at release, release time)`
/// and its position is evaluated analytically at the current time. That makes replay exact, rewind
/// free, sub-frame rendering possible, and accumulation drift impossible. The only genuine
/// accumulators are the pigeon (which the player drives), the score, and the alive masks.
public struct World {

    // MARK: - Shape

    public let batch: Int
    public let payloadSlots: Int
    public let targetSlots: Int
    public let flockSlots: Int
    public let config: WorldConfig
    public let seed: UInt64

    /// Lockstep across the whole batch. Time is `Float(frame) * dt` — never an accumulated sum, and
    /// never a frame delta.
    public var frame: Int = 0
    public var time: Double { Double(frame) * config.dt }

    /// Per-kind values, derived from `tgtIsPedestrian`. The renderer and the pilot read these.
    public var targetTopY: MLXArray {
        MLXArray(Float(config.car.topY)) + tgtIsPedestrian * Float(config.pedestrian.topY - config.car.topY)
    }
    public var targetRadius: MLXArray {
        MLXArray(Float(config.hitRadius(config.car)))
            + tgtIsPedestrian * Float(config.hitRadius(config.pedestrian) - config.hitRadius(config.car))
    }

    // MARK: - Pigeon, [B]

    public var pigeonX, pigeonY, pigeonVX, pigeonVY: MLXArray
    public var charge: MLXArray
    public var holding: MLXArray          // Bool
    public var ammo: MLXArray
    public var score, multiplier: MLXArray
    /// **False once the pigeon has hit another bird.** Until v2 this was a vestigial array that
    /// nothing read or wrote; the crash gives it its meaning. A dead world stops moving, scoring and
    /// spawning rather than drifting on, which matters when thousands are being swept at once.
    public var alive: MLXArray            // Bool

    /// Host-side, `Double`, and deliberately outside the tensors: `x` grows without bound while
    /// `x_t − x_p` becomes a cancelling difference of large Float32 numbers. The engine rebases its
    /// origin on a fixed schedule and this carries the accumulated distance for score and display.
    public var odometer: [Double]

    // MARK: - Payloads, [B, P]

    public var payAlive: MLXArray         // Bool
    public var payX0, payY0, payVX0, payU0, payT0: MLXArray
    /// Resolved at release, in closed form. See `Step` — this is what makes tunnelling impossible.
    public var payImpactTime, payImpactX: MLXArray
    /// Index into the target axis, or −1 for "lands on the road".
    public var payVictim: MLXArray
    public var payMass: MLXArray

    // MARK: - Targets, [B, M]

    public var tgtAlive: MLXArray         // Bool
    public var tgtX0, tgtV, tgtT0: MLXArray
    /// **Only the kind flag is stored.** `topY`, `halfLength`, `points` and the hit radius are all
    /// pure functions of it, so keeping them as four more [B, M] arrays would be four more arrays to
    /// write at spawn, carry between frames and evaluate every step — for values a single
    /// multiply-add reproduces where they are actually read.
    public var tgtIsPedestrian: MLXArray   // Float 0/1
    public var tgtHit: MLXArray           // Bool
    public var tgtHitAt: MLXArray

    // MARK: - Other pigeons, [B, K]
    //
    // A hazard rather than a target: the payload never interacts with these, the *pigeon* does.
    // Same idioms as every other entity block — fixed capacity, alive mask, one-hot slot writes.

    public var flockAlive: MLXArray        // Bool
    public var flockX, flockY, flockV: MLXArray

    // MARK: - Spawn scheduling, [B]

    public var nextSpawnTime: MLXArray

    // MARK: - Frame telemetry, [B]
    //
    // Read by the HUD and by tests. Dropping a release because every payload slot is busy is a
    // gameplay event that feels like an input bug, so it is counted rather than ignored.

    public var droppedReleases: MLXArray
    public var lastGained: MLXArray

    public init(batch: Int, config: WorldConfig = .shipping, seed: UInt64 = 0xC17_9160) {
        self.batch = batch
        self.config = config
        self.seed = seed
        self.payloadSlots = config.payloadSlots
        self.targetSlots = config.targetSlots
        self.flockSlots = config.flockSlots

        let B = batch, P = config.payloadSlots, M = config.targetSlots, K = config.flockSlots

        pigeonX = MLXArray.zeros([B])
        pigeonY = MLXArray.zeros([B]) + Float(config.cruiseAltitude)
        pigeonVX = MLXArray.zeros([B]) + Float(config.cruiseSpeed)
        pigeonVY = MLXArray.zeros([B])
        charge = MLXArray.zeros([B])
        holding = MLXArray.zeros([B]) .> 0.5
        ammo = MLXArray.zeros([B]) + Float(config.ammoCapacity)
        score = MLXArray.zeros([B])
        multiplier = MLXArray.ones([B])
        alive = MLXArray.ones([B]) .> 0.5
        odometer = Array(repeating: 0, count: B)

        payAlive = MLXArray.zeros([B, P]) .> 0.5
        payX0 = MLXArray.zeros([B, P]); payY0 = MLXArray.zeros([B, P])
        payVX0 = MLXArray.zeros([B, P]); payU0 = MLXArray.zeros([B, P])
        payT0 = MLXArray.zeros([B, P])
        payImpactTime = MLXArray.zeros([B, P]); payImpactX = MLXArray.zeros([B, P])
        payVictim = MLXArray.zeros([B, P]) - 1
        payMass = MLXArray.zeros([B, P])

        tgtAlive = MLXArray.zeros([B, M]) .> 0.5
        tgtX0 = MLXArray.zeros([B, M]); tgtV = MLXArray.zeros([B, M])
        tgtT0 = MLXArray.zeros([B, M])
        tgtIsPedestrian = MLXArray.zeros([B, M])
        tgtHit = MLXArray.zeros([B, M]) .> 0.5
        tgtHitAt = MLXArray.zeros([B, M])

        flockAlive = MLXArray.zeros([B, K]) .> 0.5
        flockX = MLXArray.zeros([B, K]); flockY = MLXArray.zeros([B, K])
        flockV = MLXArray.zeros([B, K])

        nextSpawnTime = MLXArray.zeros([B])

        droppedReleases = MLXArray.zeros([B])
        lastGained = MLXArray.zeros([B])
    }

    /// Force every pending array to be materialised. One call per step, at the end — never
    /// `.item()` mid-kernel, which would sync the GPU and destroy the graph.
    public mutating func evaluate() {
        eval(pigeonX, pigeonY, pigeonVX, pigeonVY, charge, holding, ammo, score, multiplier, alive,
             payAlive, payX0, payY0, payVX0, payU0, payT0, payImpactTime, payImpactX, payVictim,
             payMass, tgtAlive, tgtX0, tgtV, tgtT0, tgtIsPedestrian, tgtHit, tgtHitAt,
             flockAlive, flockX, flockY, flockV,
             nextSpawnTime, droppedReleases, lastGained)
    }
}

/// What the player (or a policy) asks of the pigeon this step.
///
/// Shaped `[B]` so a human at `B = 1` and a scripted pilot at `B = 10000` present the same thing to
/// the engine. There is no separate "human" code path, which is what stops the two drifting.
public struct Intent {
    public var moveX: MLXArray      // −1…1, forward/back within the frame
    public var moveY: MLXArray      // −1…1, climb/dive
    public var hold: MLXArray       // Bool

    public init(moveX: MLXArray, moveY: MLXArray, hold: MLXArray) {
        self.moveX = moveX
        self.moveY = moveY
        self.hold = hold
    }

    public static func idle(batch: Int) -> Intent {
        Intent(moveX: MLXArray.zeros([batch]), moveY: MLXArray.zeros([batch]),
               hold: MLXArray.zeros([batch]) .> 0.5)
    }
}

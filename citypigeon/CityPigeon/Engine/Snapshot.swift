import Foundation
import MLX

/// A plain-data, host-side view of one world, for drawing.
///
/// This is the entire boundary between the engine and the renderer. The engine never names a Metal
/// or SwiftUI type; the renderer never touches an `MLXArray`.
///
/// **Flat arrays, not structs.** Earlier versions marshalled each live entity into a Swift struct,
/// which meant three `for` loops living in `Engine/` purely to serve drawing. Handing the flat
/// readbacks across instead moves that iteration to the renderer, where building an instance buffer
/// is inherently a loop and is decor rather than simulation. The engine is now loop-free apart from
/// the odometer and two start-up config sweeps.
///
/// Slots are handed over **whole, including the dead ones**, with their alive mask. Compacting them
/// here would be a gather, and a gather is the thing the whole SoA layout exists to avoid.
public struct Snapshot {

    /// One entity block: parallel flat arrays of length `slots`, plus the mask saying which are real.
    public struct Block {
        public var alive: [Bool] = []
        public var x: [Float] = []
        public var y: [Float] = []
        /// Signed velocity where the renderer needs facing or motion; unused for payloads.
        public var v: [Float] = []
        /// Kind or mass, depending on the block. Payloads carry charge; targets carry 0/1 pedestrian.
        public var kind: [Float] = []
        /// Targets only: already struck.
        public var hit: [Bool] = []

        public var slots: Int { alive.count }
        /// How many are real. The renderer iterates the mask; this is for telemetry and tests.
        public var liveCount: Int { alive.reduce(0) { $0 + ($1 ? 1 : 0) } }
    }

    public var time: Float = 0
    public var pigeonX: Float = 0
    public var pigeonY: Float = 0
    public var pigeonVX: Float = 0
    public var pigeonVY: Float = 0
    public var charge: Float = 0
    public var holding = false
    public var ammo: Float = 0
    public var score: Float = 0
    public var multiplier: Float = 1
    public var odometer: Double = 0
    /// False once the run has ended in a collision.
    public var alive = true

    public var payloads = Block()
    public var targets = Block()
    /// Other pigeons. `v` is signed — negative is oncoming, which the renderer uses for facing.
    public var flock = Block()

    /// The predicted arc at the current charge, and where it lands. Empty while not charging.
    public var arc: [SIMD2<Float>] = []
    public var landingX: Float?
    /// Whether the predicted landing point coincides with something worth hitting. Drives the
    /// marker's colour, and nothing else — the shot is legal either way.
    public var landingOnTarget = false
}

extension World {

    /// Read world `index` back to the host.
    ///
    /// The arc is computed **on device**, through the same batched `Drop` the physics uses, so what
    /// the player is shown and what the payload will do cannot drift apart. It used to be sampled in
    /// a host loop against a second, scalar implementation of the same parabola — two copies of one
    /// equation, which is one more than is safe.
    public func snapshot(world index: Int = 0, arcSamples: Int = 24) -> Snapshot {
        var s = Snapshot()
        let c = config
        s.time = Float(frame) * Float(c.dt)

        s.pigeonX = pigeonX.asArray(Float.self)[index]
        s.pigeonY = pigeonY.asArray(Float.self)[index]
        s.pigeonVX = pigeonVX.asArray(Float.self)[index]
        s.pigeonVY = pigeonVY.asArray(Float.self)[index]
        s.charge = charge.asArray(Float.self)[index]
        s.holding = holding.asArray(Bool.self)[index]
        s.ammo = ammo.asArray(Float.self)[index]
        s.score = score.asArray(Float.self)[index]
        s.multiplier = multiplier.asArray(Float.self)[index]
        s.alive = alive.asArray(Bool.self)[index]
        s.odometer = odometer[index]

        let now = MLXArray(s.time)

        // Payload positions, evaluated analytically from the release state — the same reason replay
        // is exact — and on device, so no host arithmetic duplicates the physics.
        let payDt = now - payT0
        let payX = payX0 + payVX0 * payDt
        let payY = payY0 + payU0 * payDt - 0.5 * Float(c.gravity) * payDt * payDt
        s.payloads = Snapshot.Block(alive: row(payAlive, index, payloadSlots),
                                    x: row(payX, index, payloadSlots),
                                    y: row(payY, index, payloadSlots),
                                    v: row(payVX0, index, payloadSlots),
                                    kind: row(payMass, index, payloadSlots))

        let tgtNow = tgtX0 + tgtV * (now - tgtT0)
        s.targets = Snapshot.Block(alive: row(tgtAlive, index, targetSlots),
                                   x: row(tgtNow, index, targetSlots),
                                   y: row(targetTopY, index, targetSlots),
                                   v: row(tgtV, index, targetSlots),
                                   kind: row(tgtIsPedestrian, index, targetSlots),
                                   hit: row(tgtHit, index, targetSlots))

        s.flock = Snapshot.Block(alive: row(flockAlive, index, flockSlots),
                                 x: row(flockX, index, flockSlots),
                                 y: row(flockY, index, flockSlots),
                                 v: row(flockV, index, flockSlots))

        // The predicted arc, at the charge currently held. Drawn only while charging: a permanent
        // arc turns a game of feel into a game of reading a line.
        if s.holding {
            let cc = min(max(Double(s.charge), c.chargeFloor), c.chargeCeiling)
            let H = MLXArray(s.pigeonY)
            let T = Drop.flightTime(drop: H, climb: MLXArray(s.pigeonVY),
                                    charge: MLXArray(Float(cc)), in: c)
            if T.valid.item(Bool.self) {
                let u = Drop.releaseVelocity(flightTime: T.value, drop: H, in: c)
                let flight = T.value.item(Float.self)
                // A [samples] ramp of times, one batched evaluation, no loop.
                let ts = MLXArray.arange(arcSamples + 1, dtype: .float32) * (flight / Float(arcSamples))
                let p = Drop.position(x0: MLXArray(s.pigeonX), y0: H,
                                      vx0: MLXArray(s.pigeonVX), u0: u.value,
                                      elapsed: ts, in: c)
                let xs = p.x.asArray(Float.self), ys = p.y.asArray(Float.self)
                s.arc = zip(xs, ys).map { SIMD2($0, max(0, $1)) }

                let land = s.pigeonX + s.pigeonVX * flight
                s.landingX = land
                let tgtAtImpact = tgtNow + tgtV * flight
                let onTarget = logicalAnd(logicalAnd(tgtAlive, logicalNot(tgtHit)),
                                          lessEqual(abs(tgtAtImpact - MLXArray(land)), targetRadius))
                s.landingOnTarget = which(onTarget, MLXArray(Float(1)), MLXArray(Float(0)))
                    .max(axis: 1).asArray(Float.self)[index] > 0.5
            }
        }

        return s
    }

    /// One world's row out of a `[B, slots]` array, as host values.
    private func row(_ a: MLXArray, _ index: Int, _ slots: Int) -> [Float] {
        Array(a.asArray(Float.self)[(index * slots)..<((index + 1) * slots)])
    }

    private func row(_ a: MLXArray, _ index: Int, _ slots: Int) -> [Bool] {
        Array(a.asArray(Bool.self)[(index * slots)..<((index + 1) * slots)])
    }
}

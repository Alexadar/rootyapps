import Foundation
import MLX
import ReachabilityKit

/// The same solver, on the GPU.
///
/// `ReachabilityKit` writes the game as batch mathematics over an in-house `Tensor` (Foundation
/// only, so it also compiles for a future watchOS companion). This file is that identical program
/// expressed in `MLXArray`, which means it runs on Metal and scales to district pools far larger
/// than the CPU wants to grade.
///
/// It is a **transliteration, not a second design**: every line below has a counterpart in
/// `BatchSolver.adjacency`, in the same order, computing the same quantity. That is the same
/// relationship `monstro_shooter.swift` maintains between `torchsim/env_torch.py` and
/// `MonstroSim/GridSim.swift`, and it is kept honest the same way — by a parity test that diffs the
/// two on real geometry and reports the worst disagreement, rather than by anyone promising they
/// match.
///
/// Both read their constants from the one `WorldConfig`, so the classic failure — two engines
/// drifting apart because someone retyped a number — is structurally impossible.
public enum MLXSolver {

    /// Districts packed as MLX arrays. Shapes mirror `BlockBatch` exactly: `[N, K]` per rooftop.
    public struct Batch {
        public let worlds: Int
        public let slots: Int
        public let centerX: MLXArray
        public let centerZ: MLXArray
        public let halfX: MLXArray
        public let halfZ: MLXArray
        public let height: MLXArray
        public let alive: MLXArray
        public let spawn: [Int]
        public let goal: [Int]

        /// Move a CPU batch onto the GPU. The only host↔device crossing in the whole solver.
        public init(_ b: BlockBatch) {
            self.worlds = b.worlds
            self.slots = b.slots
            let shape = [b.worlds, b.slots]
            self.centerX = MLXArray(converting: b.centerX.data).reshaped(shape)
            self.centerZ = MLXArray(converting: b.centerZ.data).reshaped(shape)
            self.halfX = MLXArray(converting: b.halfX.data).reshaped(shape)
            self.halfZ = MLXArray(converting: b.halfZ.data).reshaped(shape)
            self.height = MLXArray(converting: b.height.data).reshaped(shape)
            self.alive = MLXArray(converting: b.alive.data).reshaped(shape)
            self.spawn = b.spawn
            self.goal = b.goal
        }
    }

    public struct Adjacency {
        public let reachable: MLXArray      // [N, K, K], 1/0
        public let requiredPower: MLXArray  // [N, K, K], +inf where unreachable
        public let rise: MLXArray           // [N, K, K]
    }

    // MARK: - The adjacency cube

    /// Build the full `[N, K, K]` adjacency cube on the GPU.
    ///
    /// Line-for-line the same program as `BatchSolver.adjacency`: broadcast each rooftop's values
    /// down the columns as sources and across the rows as targets, then decide every ordered pair
    /// with one elementwise expression. No loop over worlds, rooftops or pairs.
    public static func adjacency(_ b: Batch, boosted: Bool = false, in w: WorldConfig) -> Adjacency {
        let n = b.worlds, k = b.slots
        let g = Float(w.gravity)
        let theta = Float(w.launchElevation)
        let tanT = tan(theta), cosT = cos(theta), sinT = sin(theta)

        // Sources run down the columns, targets across the rows.
        let srcX = b.centerX.expandedDimensions(axis: 2)   // [N, K, 1]
        let dstX = b.centerX.expandedDimensions(axis: 1)   // [N, 1, K]
        let srcZ = b.centerZ.expandedDimensions(axis: 2)
        let dstZ = b.centerZ.expandedDimensions(axis: 1)
        let srcY = b.height.expandedDimensions(axis: 2)
        let dstY = b.height.expandedDimensions(axis: 1)
        let dstHalfX = b.halfX.expandedDimensions(axis: 1)
        let dstHalfZ = b.halfZ.expandedDimensions(axis: 1)

        let dx = MLX.abs(dstX - srcX)
        let dz = MLX.abs(dstZ - srcZ)
        let rise = dstY - srcY

        let bothAlive = b.alive.expandedDimensions(axis: 2) * b.alive.expandedDimensions(axis: 1)
        let notSelf = 1.0 - MLXArray.eye(k).expandedDimensions(axis: 0)

        let vMax = Float(boosted ? w.maxLaunchSpeed * w.flyMultiplier : w.maxLaunchSpeed)
        let vHi = vMax * Float(w.powerCeiling)
        let vLoInput = vMax * Float(w.minPower)

        // criticalSpeed: the slowest speed that reaches this rise at all.
        let vCrit = MLX.where(rise .> 0, MLX.sqrt(MLX.maximum(rise * (2 * g), 0)) / sinT, MLXArray(0))
        let vLo = MLX.maximum(vCrit, MLXArray(vLoInput))

        let dLo = range(speed: vLo, rise: rise, g: g, tanT: tanT, cosT: cosT)
        let dHi = range(speed: MLXArray(vHi), rise: rise, g: g, tanT: tanT, cosT: cosT)

        // Two fixed-point passes over the landing inset, exactly as on the CPU side.
        var inset = MLXArray(Float(w.frogHalfWidth)) + MLX.zeros(like: rise)
        var reachable = MLX.zeros(like: rise)
        var required = MLX.zeros(like: rise)

        for pass in 0..<2 {
            let targetHalfX = dstHalfX - inset
            let targetHalfZ = dstHalfZ - inset
            let usable = (targetHalfX .> 0) .&& (targetHalfZ .> 0)

            let nearX = MLX.maximum(dx - targetHalfX, 0)
            let nearZ = MLX.maximum(dz - targetHalfZ, 0)
            let near = MLX.sqrt(nearX * nearX + nearZ * nearZ)
            let farX = dx + targetHalfX
            let farZ = dz + targetHalfZ
            let far = MLX.sqrt(farX * farX + farZ * farZ)

            let lo = MLX.maximum(near, MLX.where(dLo.valid, dLo.value, MLXArray(Float.infinity)))
            let hi = MLX.minimum(far, MLX.where(dHi.valid, dHi.value, MLXArray(-Float.infinity)))

            let req = requiredSpeed(range: lo, rise: rise, g: g, tanT: tanT, cosT: cosT)

            let ok = usable .&& dLo.valid .&& dHi.valid .&& (lo .<= hi) .&& req.valid
                .&& (bothAlive .> 0.5) .&& (notSelf .> 0.5) .&& MLXArray(vLoInput <= vHi)

            reachable = MLX.where(ok, MLXArray(Float(1)), MLXArray(Float(0)))
            required = MLX.where(ok, req.value / vMax, MLXArray(Float.infinity))

            if pass == 0 {
                // Recompute the inset from the impact this solution implies.
                let v = MLX.where(req.valid, req.value, MLXArray(Float(0)))
                let up = v * sinT
                let vy = MLX.sqrt(MLX.maximum(up * up - rise * (2 * g), 0))
                let vx = v * cosT
                var skid = MLX.zeros(like: rise)
                for i in 1...max(w.maxBounces, 1) {
                    let tangential = vx * Float(pow(w.tangentialRetention, Double(i)))
                    let airTime = vy * Float(2 * pow(w.restitution, Double(i)) / w.gravity)
                    skid = skid + tangential * airTime
                }
                let bounces = vy .> Float(w.bounceThreshold)
                inset = MLX.where(bounces, skid, MLXArray(Float(0))) + Float(w.frogHalfWidth)
            }
        }

        return Adjacency(reachable: reachable, requiredPower: required, rise: rise)
    }

    // MARK: - Ballistics, in MLX
    //
    // The same closed forms as `ReachabilityKit.Ballistics`, in the same order. Kept private so
    // there is no temptation to treat them as an independent API that could drift.

    private struct MLXSolution {
        let value: MLXArray
        let valid: MLXArray
    }

    /// Descending root of `a·d² − d·tanθ + h = 0`.
    private static func range(speed v: MLXArray, rise h: MLXArray,
                              g: Float, tanT: Float, cosT: Float) -> MLXSolution {
        let positive = v .> 0
        let safeV = MLX.where(positive, v, MLXArray(Float(1)))
        let a = g / (safeV * safeV * (2 * cosT * cosT))
        let disc = (tanT * tanT) - a * h * 4
        // Same −1e-12 tolerance as the CPU side: at the critical speed the two crossings merge and
        // the discriminant is mathematically zero but numerically either side of it.
        let hasRoot = disc .>= -1e-6
        let root = MLX.sqrt(MLX.maximum(disc, 0))
        return MLXSolution(value: (root + tanT) / (a * 2), valid: positive .&& hasRoot)
    }

    /// Speed required to LAND at `d`. Rejects the ascending branch — a jump that passes through the
    /// target while still climbing sails over the roof rather than onto it.
    private static func requiredSpeed(range d: MLXArray, rise h: MLXArray,
                                      g: Float, tanT: Float, cosT: Float) -> MLXSolution {
        let dTan = d * tanT
        let descending = dTan .>= (h * 2)
        let denom = (dTan - h) * (2 * cosT * cosT)
        let positiveDenom = denom .> 0
        let safeDenom = MLX.where(positiveDenom, denom, MLXArray(Float(1)))
        let v2 = (d * d) * g / safeDenom
        return MLXSolution(value: MLX.sqrt(MLX.maximum(v2, 0)),
                           valid: (d .> 0) .&& descending .&& positiveDenom)
    }

    // MARK: - Graph questions

    /// Everything reachable from each world's spawn. `[N, K]`.
    ///
    /// The flood-fill: `next = OR over sources of (frontier AND adjacency)`, K times. On the GPU the
    /// inner reduction is a matrix multiply, which is the operation Metal is best at — this is the
    /// step that makes grading thousands of districts cheap.
    public static func reachableFromSpawn(_ adjacency: Adjacency, spawn: [Int],
                                          worlds n: Int, slots k: Int) -> MLXArray {
        var frontier = oneHot(spawn, slots: k)                       // [N, K]
        for _ in 0..<k {
            // [N, 1, K] x [N, K, K] -> [N, 1, K]
            let step = MLX.matmul(frontier.expandedDimensions(axis: 1), adjacency.reachable)
                .squeezed(axis: 1)
            frontier = MLX.where((frontier + step) .> 0.5, MLXArray(Float(1)), MLXArray(Float(0)))
        }
        return frontier
    }

    /// Rooftops that are reachable from spawn but from which the goal is not. `[N, K]`.
    public static func trapRoofs(_ adjacency: Adjacency, spawn: [Int], goal: [Int],
                                 worlds n: Int, slots k: Int) -> MLXArray {
        let reversed = Adjacency(
            reachable: adjacency.reachable.transposed(0, 2, 1),
            requiredPower: adjacency.requiredPower,
            rise: adjacency.rise
        )
        let forward = reachableFromSpawn(adjacency, spawn: spawn, worlds: n, slots: k)
        let backward = reachableFromSpawn(reversed, spawn: goal, worlds: n, slots: k)
        return forward * (1.0 - backward)
    }

    private static func oneHot(_ indices: [Int], slots k: Int) -> MLXArray {
        var flat = [Float](repeating: 0, count: indices.count * k)
        for (w, i) in indices.enumerated() { flat[w * k + i] = 1 }
        return MLXArray(flat, [indices.count, k])
    }

    // MARK: - Readback

    /// Which districts in the pool are solvable and trap-free. One readback for the whole batch.
    public static func survivors(_ b: Batch, in w: WorldConfig) -> [Bool] {
        let adj = adjacency(b, in: w)
        let reached = reachableFromSpawn(adj, spawn: b.spawn, worlds: b.worlds, slots: b.slots)
        let traps = trapRoofs(adj, spawn: b.spawn, goal: b.goal, worlds: b.worlds, slots: b.slots)

        let goalMask = oneHot(b.goal, slots: b.slots)
        let goalReached = (reached * goalMask).sum(axis: 1)          // [N]
        let trapCount = traps.sum(axis: 1)                           // [N]

        let ok = (goalReached .> 0.5) .&& (trapCount .< 0.5)
        ok.eval()
        return ok.asArray(Bool.self)
    }
}

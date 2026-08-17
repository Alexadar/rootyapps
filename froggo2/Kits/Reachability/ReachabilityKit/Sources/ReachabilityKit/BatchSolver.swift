import Foundation

/// N districts, laid out as tensors. Fixed slot capacity `K`; absent rooftops are carried and
/// masked, never removed.
///
/// This is the shape the whole game is written against. A single playable district is `N = 1`, the
/// generator's candidate pool is `N = 4096`, and neither knows the difference — which is the entire
/// point of building the mathematics this way rather than looping over `[Rooftop]`.
public struct BlockBatch: Sendable {
    public let worlds: Int
    public let slots: Int

    public var centerX: Tensor   // [N, K]
    public var centerZ: Tensor   // [N, K]
    public var halfX: Tensor     // [N, K]
    public var halfZ: Tensor     // [N, K]
    public var height: Tensor    // [N, K]
    /// 1 where the slot holds a real rooftop.
    public var alive: Tensor     // [N, K]

    public var spawn: [Int]      // slot index per world
    public var goal: [Int]

    public init(worlds: Int, slots: Int, centerX: Tensor, centerZ: Tensor,
                halfX: Tensor, halfZ: Tensor, height: Tensor, alive: Tensor,
                spawn: [Int], goal: [Int]) {
        self.worlds = worlds
        self.slots = slots
        self.centerX = centerX
        self.centerZ = centerZ
        self.halfX = halfX
        self.halfZ = halfZ
        self.height = height
        self.alive = alive
        self.spawn = spawn
        self.goal = goal
    }

    /// Pack scalar `CityBlock`s into one batch. Slot capacity is the widest district; the rest are
    /// padded with dead slots.
    public static func pack(_ blocks: [CityBlock], slots: Int? = nil) -> BlockBatch {
        let n = blocks.count
        let k = slots ?? (blocks.map(\.count).max() ?? 1)

        var cx = [Double](repeating: 0, count: n * k)
        var cz = [Double](repeating: 0, count: n * k)
        var hx = [Double](repeating: 1, count: n * k)
        var hz = [Double](repeating: 1, count: n * k)
        var hy = [Double](repeating: 0, count: n * k)
        var al = [Double](repeating: 0, count: n * k)
        var spawn = [Int](repeating: 0, count: n)
        var goal = [Int](repeating: 0, count: n)

        for (wi, block) in blocks.enumerated() {
            for (si, roof) in block.rooftops.enumerated() where si < k {
                let o = wi * k + si
                cx[o] = roof.footprint.center.x
                cz[o] = roof.footprint.center.z
                hx[o] = roof.footprint.halfX
                hz[o] = roof.footprint.halfZ
                hy[o] = roof.height
                al[o] = 1
                if roof.id == block.spawn { spawn[wi] = si }
                if roof.id == block.goal { goal[wi] = si }
            }
        }

        return BlockBatch(
            worlds: n, slots: k,
            centerX: Tensor(shape: [n, k], data: cx),
            centerZ: Tensor(shape: [n, k], data: cz),
            halfX: Tensor(shape: [n, k], data: hx),
            halfZ: Tensor(shape: [n, k], data: hz),
            height: Tensor(shape: [n, k], data: hy),
            alive: Tensor(shape: [n, k], data: al),
            spawn: spawn, goal: goal
        )
    }
}

/// The adjacency cube and everything read off it, for a whole batch at once.
public struct AdjacencyBatch: Sendable {
    public let worlds: Int
    public let slots: Int
    /// `[N, K, K]` — 1 where the jump from source `i` to target `j` is possible.
    public let reachable: Tensor
    /// `[N, K, K]` — least power that lands on the target. Infinite where unreachable, which makes
    /// it safe to feed straight into `min`/`max` reductions without masking first.
    public let requiredPower: Tensor
    /// `[N, K, K]` — greatest power that still lands on it. Overshooting is a way to miss too.
    public let maxUsablePower: Tensor
    public let horizontalDistance: Tensor
    public let rise: Tensor
}

public enum BatchSolver {

    /// Build the full adjacency cube. **No loop over worlds, rooftops, or pairs.**
    ///
    /// The double loop `for a in roofs { for b in roofs { ... } }` becomes two broadcasts: each
    /// roof's values repeated down the columns (as sources) and across the rows (as targets). Every
    /// ordered pair is then one lane of the same elementwise expression.
    ///
    /// Reachability itself is an **interval overlap**, not a search. Yaw is continuous over 360° and
    /// range is continuous and strictly increasing in power, so the set of landing points is an
    /// annulus about the launch; a convex target spans `[nearest, farthest]` and by the intermediate
    /// value theorem attains every distance between. So:
    ///
    ///     reachable ⟺ [nearest, farthest] ∩ [minRange, maxRange] ≠ ∅
    ///
    /// which is exact, not conservative, and costs one comparison per pair.
    public static func adjacency(_ b: BlockBatch, boosted: Bool = false,
                                 in w: WorldConfig) -> AdjacencyBatch {
        let n = b.worlds, k = b.slots

        // Pairwise geometry. Source values run down columns, target values across rows.
        let srcX = b.centerX.expandedAsRows(),  dstX = b.centerX.expandedAsColumns()
        let srcZ = b.centerZ.expandedAsRows(),  dstZ = b.centerZ.expandedAsColumns()
        let srcY = b.height.expandedAsRows(),   dstY = b.height.expandedAsColumns()
        let dstHalfX = b.halfX.expandedAsColumns()
        let dstHalfZ = b.halfZ.expandedAsColumns()
        let bothAlive = b.alive.expandedAsRows() .&& b.alive.expandedAsColumns()

        let dx = (dstX - srcX).absolute
        let dz = (dstZ - srcZ).absolute
        let rise = dstY - srcY
        let centreDistance = (dx * dx + dz * dz).squareRoot

        // A pair is never its own source and target. Built as a mask rather than skipped.
        let notSelf = Tensor.offDiagonal(worlds: n, slots: k)

        let vMax = boosted ? w.maxLaunchSpeed * w.flyMultiplier : w.maxLaunchSpeed
        let vHi = Tensor(repeating: vMax * w.powerCeiling, shape: [n, k, k])
        let vLoInput = Tensor(repeating: vMax * w.minPower, shape: [n, k, k])
        let vCrit = Ballistics.criticalSpeed(rise: rise, in: w)
        let vLo = Tensor.maximum(vLoInput, vCrit)

        let dLo = Ballistics.range(speed: vLo, rise: rise, in: w)
        let dHi = Ballistics.range(speed: vHi, rise: rise, in: w)

        // Two passes over the landing inset. The usable part of a roof depends on how hard the frog
        // arrives, which depends on how far it had to jump, which depends on the usable part of the
        // roof. Pass one assumes the frog just fits; pass two recomputes from the impact pass one
        // implies. The second pass can only shrink the target, so it is conservative — it never
        // turns an unreachable jump into a reachable one. Two passes, not a loop to convergence:
        // the correction is small and monotone, and a fixed count keeps the program branchless.
        var inset = Tensor(repeating: w.frogHalfWidth, shape: [n, k, k])
        var result: AdjacencyBatch!

        for pass in 0..<2 {
            let targetHalfX = dstHalfX - inset
            let targetHalfZ = dstHalfZ - inset
            let targetUsable = (targetHalfX .> 0) .&& (targetHalfZ .> 0)

            // Distance from the launch point to the nearest and farthest points of the inset roof.
            let nearX = (dx - targetHalfX).maximum(0)
            let nearZ = (dz - targetHalfZ).maximum(0)
            let near = (nearX * nearX + nearZ * nearZ).squareRoot
            let farX = dx + targetHalfX
            let farZ = dz + targetHalfZ
            let far = (farX * farX + farZ * farZ).squareRoot

            let lo = Tensor.maximum(near, dLo.filled(.infinity))
            let hi = Tensor.minimum(far, dHi.filled(-.infinity))

            let overlaps = lo .<= hi
            let reachable = bothAlive .&& notSelf .&& targetUsable
                .&& dLo.valid .&& dHi.valid .&& overlaps .&& (vLo .<= vHi)

            let reqAtNear = Ballistics.requiredPower(range: lo, rise: rise, boosted: boosted, in: w)
            let reqAtFar = Ballistics.requiredPower(range: hi, rise: rise, boosted: boosted, in: w)

            let finalReachable = reachable .&& reqAtNear.valid
            let required = Tensor.which(finalReachable, reqAtNear.value, .infinity)
            let maxUsable = Tensor.which(finalReachable .&& reqAtFar.valid,
                                         reqAtFar.value.minimum(w.powerCeiling), 0.0)

            result = AdjacencyBatch(
                worlds: n, slots: k,
                reachable: finalReachable,
                requiredPower: required,
                maxUsablePower: maxUsable,
                horizontalDistance: centreDistance,
                rise: rise
            )

            if pass == 0 {
                let vReq = Ballistics.requiredSpeed(range: lo, rise: rise, in: w)
                let impact = Ballistics.impactSpeed(speed: vReq.filled(0), rise: rise, in: w)
                inset = Ballistics.landingInset(horizontal: impact.horizontal,
                                                vertical: impact.vertical.filled(0), in: w)
            }
        }

        return result
    }

    // MARK: - Graph questions, as tensor algebra

    /// Everything reachable from each world's spawn. `[N, K]` mask.
    ///
    /// A breadth-first search with no queue and no per-node loop: `next = OR over sources of
    /// (frontier AND adjacency)`, applied K times. K relaxations is enough because no shortest path
    /// can be longer than the number of rooftops, and running the full K every time keeps every
    /// world on the same code path instead of terminating early per world.
    public static func reachableFromSpawn(_ adjacency: AdjacencyBatch, spawn: [Int]) -> Tensor {
        let k = adjacency.slots
        var frontier = Tensor.oneHot(indices: spawn, slots: k)

        for _ in 0..<k {
            let step = (frontier.expandedAsRows() .&& adjacency.reachable).anyOverSources()
            frontier = frontier .|| step
        }
        return frontier
    }

    /// Fewest jumps from spawn to every rooftop. `[N, K]`, infinite where unreachable.
    ///
    /// Same flood as above, but recording the relaxation at which each rooftop is first touched —
    /// which is exactly its distance in jumps. The goal's entry is the district's par.
    public static func jumpDistances(_ adjacency: AdjacencyBatch, spawn: [Int]) -> Tensor {
        let n = adjacency.worlds, k = adjacency.slots
        var frontier = Tensor.oneHot(indices: spawn, slots: k)
        var distance = Tensor.which(frontier, 0.0, Tensor(repeating: .infinity, shape: [n, k]))

        for step in 1...k {
            let next = (frontier.expandedAsRows() .&& adjacency.reachable).anyOverSources()
            let newlyReached = next .&& (distance.map { $0.isFinite ? 0 : 1 })
            distance = Tensor.which(newlyReached, Double(step), distance)
            frontier = frontier .|| next
        }
        return distance
    }

    /// Rooftops a player can reach but from which the goal cannot be reached. `[N, K]` mask.
    ///
    /// The property that actually matters, and the reason this Kit exists. Landing on one of these
    /// is a dead run with no feedback explaining why — the worst failure a generated level can have.
    ///
    /// Computed by flooding *backwards* from the goal: a rooftop is a trap when it is forward-
    /// reachable from spawn but not backward-reachable from the goal. Reversing the adjacency is a
    /// transpose of the last two axes, so the same flood serves both directions.
    public static func trapRoofs(_ adjacency: AdjacencyBatch, spawn: [Int], goal: [Int]) -> Tensor {
        let n = adjacency.worlds, k = adjacency.slots
        let reversed = AdjacencyBatch(
            worlds: n, slots: k,
            reachable: adjacency.reachable.transposedLastTwo(),
            requiredPower: adjacency.requiredPower,
            maxUsablePower: adjacency.maxUsablePower,
            horizontalDistance: adjacency.horizontalDistance,
            rise: adjacency.rise
        )

        let forward = reachableFromSpawn(adjacency, spawn: spawn)
        let backward = reachableFromSpawn(reversed, spawn: goal)
        return forward .&& backward.not
    }

    /// Whether each world's goal is reachable at all. `[N]` mask.
    public static func goalReachable(_ adjacency: AdjacencyBatch, spawn: [Int], goal: [Int]) -> Tensor {
        reachableFromSpawn(adjacency, spawn: spawn).gatherPerWorld(goal)
    }

    /// Par for each world — the shortest route length. `[N]`, infinite where there is no route.
    public static func par(_ adjacency: AdjacencyBatch, spawn: [Int], goal: [Int]) -> Tensor {
        jumpDistances(adjacency, spawn: spawn).gatherPerWorld(goal)
    }

    /// Mean number of onward moves that make *progress toward the goal*. `[N]`.
    ///
    /// The "is this actually a block, or a corridor with extra steps" measure — and it has to count
    /// forward options specifically, not neighbours. A straight line of rooftops has a mean degree
    /// of about two, because every roof can jump both onward and back the way it came; by raw degree
    /// a corridor looks as rich as a field. What distinguishes them is *choice*: on a corridor there
    /// is exactly one neighbour that gets you closer to the goal, and the player is walking rather
    /// than routing.
    ///
    /// So: for each reachable rooftop, count the neighbours whose remaining distance to the goal is
    /// one less than its own. Distance-to-goal comes from flooding the reversed adjacency out of the
    /// goal, which is the same vectorized search run backwards.
    public static func meanForwardBranching(_ adjacency: AdjacencyBatch,
                                            spawn: [Int], goal: [Int]) -> Tensor {
        let k = adjacency.slots
        let reversed = AdjacencyBatch(
            worlds: adjacency.worlds, slots: k,
            reachable: adjacency.reachable.transposedLastTwo(),
            requiredPower: adjacency.requiredPower,
            maxUsablePower: adjacency.maxUsablePower,
            horizontalDistance: adjacency.horizontalDistance,
            rise: adjacency.rise
        )
        let toGoal = jumpDistances(reversed, spawn: goal)                  // [N, K]
        let reached = reachableFromSpawn(adjacency, spawn: spawn)          // [N, K]

        // A neighbour counts as forward progress when its distance-to-goal is exactly one less.
        let sourceDistance = toGoal.expandedAsRows()                       // [N, K, K]
        let targetDistance = toGoal.expandedAsColumns()
        let isProgress = (targetDistance + 1) .<= sourceDistance .&& ((targetDistance + 1) .>= sourceDistance)
        let forward = (adjacency.reachable .&& isProgress).sumLast()       // [N, K]

        // Only roofs that are on the way count: reachable, and not the goal itself.
        let onTheWay = reached .&& (toGoal .> 0.5) .&& toGoal.isFiniteMask
        let total = (forward * onTheWay).sumLast()                         // [N]
        let population = onTheWay.sumLast().maximum(1)
        return total / population
    }
}

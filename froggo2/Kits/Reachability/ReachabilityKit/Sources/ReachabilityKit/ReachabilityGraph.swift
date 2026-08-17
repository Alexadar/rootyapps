import Foundation

/// One jump, reported for a human or for the UI.
///
/// This is a *view* onto lanes of the adjacency cube, not a thing the solver computes one at a
/// time. Nothing in the solver ever builds a list of these.
public struct JumpAssessment: Hashable, Codable, Sendable {
    public let from: RooftopID
    public let to: RooftopID
    public let isReachable: Bool
    /// Least power that lands on the target, or `nil` when nothing does.
    public let requiredPower: Double?
    /// Greatest power that still lands on it — overshooting is a way to miss too.
    public let maxUsablePower: Double?
    public let powerWindow: Double
    public let yaw: Double
    /// Angular width of the target from here: a difficulty signal, not part of the verdict.
    public let angularWidth: Double
    public let horizontalDistance: Double
    /// `to.height − from.height`. Negative is a down-jump, which reaches further.
    public let rise: Double

    /// Fraction of the envelope left unused. 0 means the jump needs everything the frog has.
    public var margin: Double { isReachable ? 1.0 - (requiredPower ?? 1.0) : 0 }
}

/// A route through a district, as the sequence of jumps that makes it.
public struct Route: Hashable, Codable, Sendable {
    public let steps: [JumpAssessment]
    public var jumpCount: Int { steps.count }
    /// The step with the least margin — the one that will actually kill the player.
    public var hardestStep: JumpAssessment? { steps.min { $0.margin < $1.margin } }
    public var tightestMargin: Double { hardestStep?.margin ?? 1.0 }
    public var tightestAngularWidth: Double { steps.map(\.angularWidth).min() ?? .pi }
}

/// The reachability relation over one district.
///
/// **This type owns no mathematics.** It packs a single `CityBlock` into a one-world batch, hands it
/// to `BatchSolver`, and reads answers out of the resulting tensors. The playable game is `N = 1` of
/// exactly the program that grades four thousand candidate districts at once — the same discipline
/// `monstro_shooter.swift/MonstroSim` follows, where the live game is its batched sim at `N = 1` and
/// there is no separate single-game engine to drift away from it.
///
/// The previous version of this file built every ordered pair with a nested `map` and flooded the
/// graph with a queue and a `Set`. Both are gone: they were a second implementation of things the
/// batch solver already does, and a second implementation is a second thing to be wrong.
public struct ReachabilityGraph: Sendable {
    public let block: CityBlock
    public let config: WorldConfig
    public let boosted: Bool

    private let batch: BlockBatch
    private let adjacency: AdjacencyBatch
    private let slotOf: [RooftopID: Int]
    private let idOf: [Int: RooftopID]
    private let k: Int

    public init(block: CityBlock, config: WorldConfig, boosted: Bool = false) {
        self.block = block
        self.config = config
        self.boosted = boosted

        self.batch = BlockBatch.pack([block])
        self.adjacency = BatchSolver.adjacency(batch, boosted: boosted, in: config)
        self.k = batch.slots

        var slots: [RooftopID: Int] = [:]
        var ids: [Int: RooftopID] = [:]
        for (i, r) in block.rooftops.enumerated() {
            slots[r.id] = i
            ids[i] = r.id
        }
        self.slotOf = slots
        self.idOf = ids
    }

    // MARK: - Reading lanes out of the cube

    private func pairIndex(_ from: Int, _ to: Int) -> Int { from * k + to }

    public func assessment(from: RooftopID, to: RooftopID) -> JumpAssessment {
        let i = slotOf[from]!, j = slotOf[to]!
        let p = pairIndex(i, j)
        let reachable = adjacency.reachable[p] > 0.5
        let required = adjacency.requiredPower[p]
        let maxUsable = adjacency.maxUsablePower[p]

        let a = block[from], b = block[to]
        return JumpAssessment(
            from: from, to: to,
            isReachable: reachable,
            requiredPower: reachable ? required : nil,
            maxUsablePower: reachable ? maxUsable : nil,
            powerWindow: reachable ? Swift.max(0, maxUsable - required) : 0,
            yaw: (b.footprint.center - a.footprint.center).heading,
            angularWidth: b.footprint.angularWidth(from: a.footprint.center),
            horizontalDistance: adjacency.horizontalDistance[p],
            rise: adjacency.rise[p]
        )
    }

    public func neighbours(of id: RooftopID) -> [RooftopID] {
        let i = slotOf[id]!
        let row = Tensor(shape: [1, k],
                         data: Array(adjacency.reachable.data[(i * k)..<((i + 1) * k)]))
        return row.setSlots(world: 0).compactMap { idOf[$0] }
    }

    /// Every roof the player can actually get to, starting from spawn.
    public var reachableFromSpawn: Set<RooftopID> {
        let mask = BatchSolver.reachableFromSpawn(adjacency, spawn: batch.spawn)
        return Set(mask.setSlots(world: 0).compactMap { idOf[$0] })
    }

    /// Roofs with nowhere to jump at all.
    ///
    /// This is the property PROMPT.md §4 states, and it is deliberately kept alongside `trapRoofs`
    /// rather than replaced by it — because on its own it is **not sufficient**, and the test suite
    /// proves that with a two-roof cycle that satisfies this and still strands the player. Keeping
    /// the weaker property visible is what stops someone "simplifying" the stronger one away.
    public var roofsWithNoExit: [RooftopID] {
        let reached = BatchSolver.reachableFromSpawn(adjacency, spawn: batch.spawn)
        let hasExit = adjacency.reachable.sumLast() .> 0.5          // [1, K]
        return (reached .&& hasExit.not).setSlots(world: 0).compactMap { idOf[$0] }.sorted()
    }

    /// The property that actually matters: roofs you can reach but from which the goal is gone.
    public var trapRoofs: [RooftopID] {
        BatchSolver.trapRoofs(adjacency, spawn: batch.spawn, goal: batch.goal)
            .setSlots(world: 0).compactMap { idOf[$0] }.sorted()
    }

    /// Mean number of onward moves that make progress toward the goal. 1.0 is a corridor.
    public var meanBranchingFactor: Double {
        BatchSolver.meanForwardBranching(adjacency, spawn: batch.spawn, goal: batch.goal)[0]
    }

    /// Fewest jumps from `from` to `to`, reconstructed from the batch flood.
    ///
    /// The distances come from the vectorized search; only the walk *back* along one already-known
    /// shortest path is sequential, and it is bounded by the route's own length (typically four to
    /// eight steps). That is output marshalling, not search.
    public func route(from: RooftopID, to: RooftopID) -> Route? {
        guard let start = slotOf[from], let end = slotOf[to] else { return nil }
        if start == end { return Route(steps: []) }

        let distances = BatchSolver.jumpDistances(adjacency, spawn: [start])
        guard distances[end].isFinite else { return nil }

        var steps: [JumpAssessment] = []
        var node = end
        while distances[node] > 0 {
            let target = distances[node] - 1
            // Candidate predecessors: one step closer to the start, and adjacent to this node.
            let atPreviousDepth = distances .<= target .&& (distances .>= target)
            let column = Tensor(shape: [1, k],
                                data: (0..<k).map { adjacency.reachable[pairIndex($0, node)] })
            guard let previous = (atPreviousDepth .&& column).setSlots(world: 0).first else {
                return nil
            }
            steps.append(assessment(from: idOf[previous]!, to: idOf[node]!))
            node = previous
        }
        return Route(steps: steps.reversed())
    }
}

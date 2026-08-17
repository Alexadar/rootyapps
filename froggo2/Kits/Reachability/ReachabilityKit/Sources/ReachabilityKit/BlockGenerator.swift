import Foundation

/// The shape of a district before the solver has had its say.
public struct BlockRecipe: Hashable, Codable, Sendable {
    public var rows: Int
    public var cols: Int
    /// Lattice spacing between roof centres.
    public var cellSize: Double
    /// How far a roof may wander from its lattice point, as a fraction of `cellSize`.
    public var jitter: Double
    /// Probability a lattice cell is left empty. Holes are what make routing a choice rather than
    /// a walk — a full grid has no decisions in it.
    public var omissionChance: Double
    public var targetBand: DifficultyGrade.Band

    public init(rows: Int, cols: Int, cellSize: Double, jitter: Double,
                omissionChance: Double, targetBand: DifficultyGrade.Band) {
        self.rows = rows
        self.cols = cols
        self.cellSize = cellSize
        self.jitter = jitter
        self.omissionChance = omissionChance
        self.targetBand = targetBand
    }

    /// The district-by-district difficulty ramp.
    ///
    /// Spacing tightens toward the envelope and holes multiply as districts go by. The floor on
    /// spacing is deliberate: past a certain point a jump requires power a thumb cannot place
    /// accurately, and difficulty stops being skill and becomes a dice roll.
    public static func forDistrict(_ k: Int, in w: WorldConfig) -> BlockRecipe {
        let reach = w.flatMaxRange
        // Lattice spacing as a fraction of the envelope: start comfortable, tighten with depth,
        // and stop well short of the boundary. The ceiling is not decoration — past roughly 0.72
        // the required power stops being a skill the player can express and becomes a coin flip,
        // and `ConfigConsistencyTests` holds the low end above the point where roofs would overlap.
        let fraction = min(0.72, 0.58 + 0.02 * Double(k))
        let band: DifficultyGrade.Band = k < 2 ? .gentle : (k < 5 ? .steady : .tight)
        return BlockRecipe(
            rows: 6,
            cols: 6,
            cellSize: reach * fraction,
            // Jitter is kept small for a geometric reason: two neighbours can each wander this far
            // in opposite directions, so it doubles into the worst-case span the envelope has to
            // cover.
            jitter: 0.10,
            omissionChance: min(0.28, 0.10 + 0.02 * Double(k)),
            targetBand: band
        )
    }
}

public struct RepairStep: Hashable, Codable, Sendable {
    public enum Operation: String, Codable, Sendable {
        case lowerRoof, growRoof, slideRoof, removeRoof
    }
    public let operation: Operation
    public let roof: RooftopID
    public let delta: Double
}

public struct GeneratedBlock: Sendable {
    public let block: CityBlock
    public let grade: DifficultyGrade
    /// How many fresh seeds were burned before one worked.
    public let attempts: Int
    public let repairs: [RepairStep]
}

public enum BlockGenerator {

    /// Generate a district that the solver has cleared. There is no other way out of this function.
    ///
    /// **Perturb-and-repair, with resampling as the outer net.** Plain generate-and-reject would
    /// work at gentle spacings, where a jittered lattice is almost always connected. It stops
    /// working exactly where the game gets interesting: difficulty here *is* spacing pushed toward
    /// the envelope, and near the envelope connectivity turns fragile and the rejection rate climbs.
    ///
    /// Repair is cheap because it is directed rather than searched. When the solver reports a trap
    /// roof it also reports, for each of that roof's neighbours, the power the jump would need — so
    /// the deficit is a known number and the fix is a closed-form nudge, not a guess. (This is the
    /// difference from the perturb-and-repair in `docs/CANDIDATE_minesweeper_2026-08-08.md`, where
    /// the generator has to guess which mine to move.)
    ///
    /// `verify` runs last, on the final geometry, every time. A district that has been repaired is
    /// not assumed to be fixed; it is re-proved.
    /// How many candidate districts are graded in a single batched pass before falling back to
    /// repairing them one at a time.
    ///
    /// This is where the vector architecture actually pays. Grading one district and grading a
    /// hundred cost almost the same wall-clock time up front — the adjacency cube is one elementwise
    /// expression either way — so rejection stops being expensive and the generator can afford to be
    /// picky. Generate-and-verify becomes cheaper than being clever.
    public static let candidatePoolSize = 64

    /// Sample a pool of candidate districts and grade **all of them in one pass**.
    ///
    /// Returns the survivors in seed order, so the caller can take the first and still get a
    /// deterministic answer. No district leaves here that the solver has not cleared.
    public static func generatePool(recipe: BlockRecipe, seed: UInt64, districtIndex: Int,
                                    count: Int = candidatePoolSize,
                                    in w: WorldConfig) -> [CityBlock] {
        let candidates = (0..<count).map { i in
            sample(recipe: recipe,
                   seed: seed &+ UInt64(i) &* 0x9E3779B97F4A7C15,
                   districtIndex: districtIndex, in: w)
        }
        guard !candidates.isEmpty else { return [] }

        // ONE adjacency cube for the whole pool: [count, K, K].
        let batch = BlockBatch.pack(candidates)
        let adjacency = BatchSolver.adjacency(batch, in: w)

        // Every gate, evaluated for every candidate at once.
        let goalOK = BatchSolver.goalReachable(adjacency, spawn: batch.spawn, goal: batch.goal)
        let traps = BatchSolver.trapRoofs(adjacency, spawn: batch.spawn, goal: batch.goal)
            .sumLast()                                          // [count] — trap roofs per district
        let branching = BatchSolver.meanForwardBranching(adjacency,
                                                         spawn: batch.spawn, goal: batch.goal)
        let passes = goalOK .&& (traps .<= 0.5) .&& (branching .> 1.0)

        return (0..<count).filter { passes[$0] > 0.5 }.map { candidates[$0] }
    }

    public static func generate(recipe: BlockRecipe, seed: UInt64, districtIndex: Int,
                                in w: WorldConfig,
                                maxAttempts: Int = 12, maxRepairs: Int = 48) -> GeneratedBlock? {
        // Fast path: grade a whole pool at once and take the first survivor. Most seeds are answered
        // here, and the ones that are not fall through to the per-district repair loop below.
        for candidate in generatePool(recipe: recipe, seed: seed, districtIndex: districtIndex, in: w) {
            let withFlies = placeFlies(in: candidate, seed: seed, config: w)
            if case .cleared(let grade) = Reachability.verify(withFlies, in: w) {
                return GeneratedBlock(block: withFlies, grade: grade, attempts: 1, repairs: [])
            }
        }

        for attempt in 0..<maxAttempts {
            let attemptSeed = seed &+ UInt64(attempt) &* 0x9E3779B97F4A7C15
            var candidate = sample(recipe: recipe, seed: attemptSeed, districtIndex: districtIndex, in: w)
            var repairs: [RepairStep] = []

            repairLoop: while true {
                switch Reachability.verify(candidate, in: w) {
                case .cleared(let grade):
                    let withFlies = placeFlies(in: candidate, seed: attemptSeed, config: w)
                    // Placing a fly cannot disconnect a district (it adds no geometry), but the
                    // gate is re-run anyway rather than reasoned about. "Never ship a block the
                    // solver has not cleared" means the block that ships, not an ancestor of it.
                    guard case .cleared(let finalGrade) = Reachability.verify(withFlies, in: w) else {
                        break repairLoop
                    }
                    _ = grade
                    return GeneratedBlock(block: withFlies, grade: finalGrade,
                                          attempts: attempt + 1, repairs: repairs)

                case .goalUnreachable, .trapRoofs:
                    guard repairs.count < maxRepairs,
                          let (repaired, step) = repairConnectivity(candidate, in: w)
                    else { break repairLoop }
                    candidate = repaired
                    repairs.append(step)

                case .corridor, .aimTooTight, .degenerate:
                    // Not locally repairable: the district is the wrong shape, not slightly wrong.
                    // Burn the seed rather than nudging geometry that was never going to work.
                    break repairLoop
                }
            }
        }
        return nil
    }

    /// Put flies on roofs that are reachable *without* one.
    ///
    /// A pickup you cannot reach is not a pickup, and a fly that is only obtainable after eating a
    /// fly is a joke at the player's expense. Spawn and goal are excluded: a fly on the spawn is
    /// free, and one on the goal is never collected.
    /// Public entry point for the GPU-backed factory, which does its own pool filtering and then
    /// needs to place flies on the one district it kept.
    public static func placeFliesPublic(in block: CityBlock, seed: UInt64,
                                        config w: WorldConfig) -> CityBlock {
        placeFlies(in: block, seed: seed, config: w)
    }

    static func placeFlies(in block: CityBlock, seed: UInt64, config w: WorldConfig) -> CityBlock {
        let graph = ReachabilityGraph(block: block, config: w)
        let candidates = graph.reachableFromSpawn
            .subtracting([block.spawn, block.goal])
            .sorted()                                  // sorted: Set order must never be load-bearing
        guard !candidates.isEmpty else { return block }

        var rng = SplitMix64(seed: seed ^ 0xF10F10F10F10F101)
        let count = min(2, candidates.count)
        let chosen = Array(rng.shuffled(candidates).prefix(count))

        return CityBlock(seed: block.seed, districtIndex: block.districtIndex,
                         rooftops: block.rooftops, spawn: block.spawn, goal: block.goal,
                         flyRoofs: chosen, killPlaneY: block.killPlaneY)
    }

    // MARK: - Sampling

    /// Sample one candidate district. Public so the GPU parity gate can build the same
    /// geometry both solvers are asked to grade.
    public static func sample(recipe: BlockRecipe, seed: UInt64, districtIndex: Int,
                              in w: WorldConfig) -> CityBlock {
        var rng = SplitMix64(seed: seed)
        let field = HeightField(seed: seed)

        let halfLo = w.roofHalfExtentRange.lowerBound
        let halfHi = w.roofHalfExtentRange.upperBound
        let heightLo = w.heightRange.lowerBound
        let heightHi = w.heightRange.upperBound

        // The whole lattice is sampled as tensors — one draw per quantity for every cell at once,
        // then pure elementwise arithmetic. There is no loop over cells here; the only sequential
        // work is inside `uniforms`, where a counter-based PRNG is sequential by construction, and
        // in the final marshalling of surviving cells into `[Rooftop]` for the renderer.
        let cells = recipe.rows * recipe.cols
        let colIndex = Tensor(shape: [cells], data: (0..<cells).map { Double($0 % recipe.cols) })
        let rowIndex = Tensor(shape: [cells], data: (0..<cells).map { Double($0 / recipe.cols) })

        let omissionRoll = rng.uniforms(cells)
        let jitterXRoll = rng.uniforms(cells)
        let jitterZRoll = rng.uniforms(cells)
        let halfXRoll = rng.uniforms(cells)
        let halfZRoll = rng.uniforms(cells)

        let jitterScale = 2 * recipe.jitter * recipe.cellSize
        let centerX = colIndex * recipe.cellSize + (jitterXRoll - 0.5) * jitterScale
        let centerZ = rowIndex * recipe.cellSize + (jitterZRoll - 0.5) * jitterScale
        let halfXs = halfXRoll * (halfHi - halfLo) + halfLo
        let halfZs = halfZRoll * (halfHi - halfLo) + halfLo

        // Height from the smooth field, so neighbours stay climbable. The sampling frequency is the
        // knob that matters: at a low rate the district still gains and loses real height across its
        // width, while any two adjacent roofs stay within one hop of each other.
        // `ConfigConsistencyTests` measures the worst neighbour step over thousands of districts
        // rather than trusting this comment.
        let noise = field.values(x: colIndex * 0.20, z: rowIndex * 0.20)
        let heights = noise * (heightHi - heightLo) + heightLo

        // Spawn and goal rows are never punched out — the district needs both ends. Everything else
        // survives or not by a threshold, expressed as a mask rather than a `continue`.
        let isEdgeRow = (rowIndex .<= 0.5) .|| (rowIndex .>= Double(recipe.rows - 1) - 0.5)
        let kept = isEdgeRow .|| (omissionRoll .>= recipe.omissionChance)

        let survivors: [Int] = (0..<cells).filter { kept[$0] > 0.5 }
        let roofs: [Rooftop] = survivors.enumerated().map { index, i in
            Rooftop(
                id: RooftopID(index),
                footprint: Rect2(center: Vec2(centerX[i], centerZ[i]),
                                 halfX: halfXs[i], halfZ: halfZs[i]),
                height: heights[i]
            )
        }

        guard roofs.count >= 2 else {
            return CityBlock(seed: seed, districtIndex: districtIndex, rooftops: roofs,
                             spawn: RooftopID(0), goal: RooftopID(max(0, roofs.count - 1)),
                             flyRoofs: [], killPlaneY: 0)
        }

        // Spawn on the near edge, goal on the far edge: the route crosses the district, so there
        // are many paths of differing risk rather than one line to walk.
        let spawn = roofs.min { $0.footprint.center.z < $1.footprint.center.z }!.id
        let goal = roofs.max { $0.footprint.center.z < $1.footprint.center.z }!.id

        let lowest = roofs.map(\.height).min() ?? 0

        return CityBlock(
            seed: seed,
            districtIndex: districtIndex,
            rooftops: roofs,
            spawn: spawn,
            goal: goal,
            flyRoofs: [],
            killPlaneY: lowest - w.deathDrop
        )
    }

    // MARK: - Repair

    /// One directed nudge toward connectivity, or `nil` if nothing local helps.
    ///
    /// Operators are tried cheapest-looking-damage first. Lowering a roof is nearly invisible and
    /// often enough on its own, because a down-jump reaches further than a level one — the height
    /// asymmetry that makes the envelope interesting is also the cheapest repair available.
    static func repairConnectivity(_ block: CityBlock, in w: WorldConfig) -> (CityBlock, RepairStep)? {
        let graph = ReachabilityGraph(block: block, config: w)
        let stranded = graph.trapRoofs.first
            ?? (graph.route(from: block.spawn, to: block.goal) == nil ? block.spawn : nil)
        guard let source = stranded else { return nil }

        // Which roof is nearest to being reachable from here, and by how much?
        //
        // Vectorized: one row of the adjacency cube already holds the required power to every other
        // rooftop, so the "which near miss is cheapest to fix" question is an argmin over that row —
        // not a scan calling the solver once per candidate. The deficit it returns is a number, which
        // is what makes the repair a closed-form nudge instead of a search.
        let sourceRoof = block[source]
        let batch = BlockBatch.pack([block])
        let adjacency = BatchSolver.adjacency(batch, in: w)
        let k = batch.slots
        guard let sourceSlot = block.rooftops.firstIndex(where: { $0.id == source }) else { return nil }

        let row = Tensor(shape: [1, k],
                         data: Array(adjacency.requiredPower.data[(sourceSlot * k)..<((sourceSlot + 1) * k)]))
        let reachableRow = Tensor(shape: [1, k],
                                  data: Array(adjacency.reachable.data[(sourceSlot * k)..<((sourceSlot + 1) * k)]))
        // Only unreachable, live, non-self slots are candidates; everything else is pushed to
        // infinity so the argmin ignores it without a branch.
        let live = Tensor(shape: [1, k], data: Array(batch.alive.data[0..<k]))
        let selfMask = Tensor.oneHot(indices: [sourceSlot], slots: k)
        let eligible = live .&& reachableRow.not .&& selfMask.not
        let costs = Tensor.which(eligible, row, .infinity)

        let cheapest = costs.minLastFinite()[0]
        guard cheapest.isFinite else { return nil }
        guard let targetSlot = (costs .<= cheapest).setSlots(world: 0).first,
              targetSlot < block.rooftops.count else { return nil }

        let target = block.rooftops[targetSlot]
        let deficit = cheapest - w.powerCeiling
        guard deficit > 0 else { return nil }
        _ = sourceRoof

        var roofs = block.rooftops

        // Operator 1: lower the target. Solved directly from the height that would bring the jump
        // inside the envelope, then applied with a little slack.
        let drop = min(1.5, max(0.4, deficit * 8))
        if target.height - drop > w.heightRange.lowerBound - 4 {
            roofs = roofs.map { r in
                r.id == target.id
                    ? Rooftop(id: r.id, footprint: r.footprint, height: r.height - drop)
                    : r
            }
            return (rebuilt(block, roofs: roofs, in: w),
                    RepairStep(operation: .lowerRoof, roof: target.id, delta: -drop))
        }

        // Operator 2: grow the target, bringing its near edge closer and widening the aim window.
        let grow = 0.5
        roofs = roofs.map { r in
            r.id == target.id
                ? Rooftop(id: r.id,
                          footprint: Rect2(center: r.footprint.center,
                                           halfX: r.footprint.halfX + grow,
                                           halfZ: r.footprint.halfZ + grow),
                          height: r.height)
                : r
        }
        return (rebuilt(block, roofs: roofs, in: w),
                RepairStep(operation: .growRoof, roof: target.id, delta: grow))
    }

    private static func rebuilt(_ block: CityBlock, roofs: [Rooftop], in w: WorldConfig) -> CityBlock {
        let lowest = roofs.map(\.height).min() ?? 0
        return CityBlock(seed: block.seed, districtIndex: block.districtIndex, rooftops: roofs,
                         spawn: block.spawn, goal: block.goal, flyRoofs: block.flyRoofs,
                         killPlaneY: lowest - w.deathDrop)
    }
}

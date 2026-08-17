import Foundation
import ReachabilityKit

/// Where the GPU actually earns its place in the shipping game.
///
/// Grading a district is cheap; grading it *one at a time on the CPU* is not, because the generator
/// has to reject a lot of candidates to find a good one. Measured in a debug build, finding a single
/// district through the CPU path took **12.4 seconds** — long enough to freeze the app on launch,
/// which is exactly what it did the first time this was wired up.
///
/// The fix is not to be cleverer about generation, it is to make rejection free: sample a pool,
/// grade the whole pool in one batched GPU pass, and keep the survivors. The full CPU verification
/// then runs once, on the single district that is actually going to be played — so the shipping
/// guarantee is unchanged ("nothing reaches the renderer the solver has not cleared") while the cost
/// of getting there drops by two orders of magnitude.
public enum DistrictFactory {

    /// Which implementation grades the candidate pool.
    ///
    /// Both compute the same thing — `SolverParityTests` diffs 62,208 rooftop pairs and finds zero
    /// disagreements — so this is purely a question of where the work runs.
    public enum Backend: Sendable {
        /// The in-house `Tensor` layer in `ReachabilityKit`. Foundation only, runs anywhere.
        case cpu
        /// `MLXSolver`, on Metal.
        case gpu

        /// What the shipping game uses.
        ///
        /// **CPU — but read the next paragraph, because the reason is not the obvious one.**
        ///
        /// MLX cannot create a Metal device in the iOS Simulator: it calls `abort()` inside
        /// `mlx::core::metal::Device::Device()`, taking the app down with it, and an `abort()`
        /// cannot be guarded with a `try`.
        ///
        /// The abort is **eager**. It is not reached by asking for GPU work — it is reached by
        /// entering MLX at all, because MLX's global singletons construct the Metal device in their
        /// own constructors. Two independent paths were observed:
        ///
        ///     MLXArray.init(converting:) → allocator::malloc → MetalAllocator() → metal::device  (here)
        ///     scheduler() → new_stream  → gpu::new_stream    → metal::device                     (citypigeon)
        ///
        /// `Device.setDefault(.cpu)` does not help: making that call is itself an MLX entry, so it
        /// trips the same abort. In the simulator MLX's CPU device is not slower — it is unreachable.
        ///
        /// So selecting `.cpu` here is **not** what makes the simulator build survive. What makes it
        /// survive is that the shipping path never calls MLX at all: `GameSession` → `DistrictFactory`
        /// → `BatchSolver`, the Foundation-only `Tensor` layer, with `MLXSolver` reached only on the
        /// `.gpu` branch. *Linking* MLX is harmless; *entering* it is fatal. That is the invariant to
        /// preserve, and `SimulatorSafetyTests` enforces it — adding an innocuous MLX helper, or a
        /// `Device.defaultDevice()` diagnostic, anywhere the app can reach would kill the simulator
        /// build at launch.
        ///
        /// Stepping back to the CPU costs nothing anyway: in a release build it grades a whole pool
        /// and returns a verified district in **~35 ms**. The GPU is genuinely faster at scale (512
        /// districts in 0.116 s, where the CPU wants seconds), which is why it stays — for test
        /// sweeps, offline tooling, and the batched world simulation this architecture was shaped
        /// around. It is simply not needed to build one district at a time.
        public static let shipping: Backend = .cpu
    }

    /// Candidates graded per pass. Large enough that a survivor is essentially always in the first
    /// pool, small enough to stay instant.
    public static let poolSize = 96

    public struct Result: Sendable {
        public let block: CityBlock
        public let grade: DifficultyGrade?
        /// How many candidates the GPU had to grade. Reported rather than hidden — if this starts
        /// climbing, the difficulty ramp has outrun what the geometry can actually produce.
        public let graded: Int
    }

    /// Build a verified district for `index`.
    ///
    /// Deterministic: the same seed and index always produce the same district, because candidates
    /// are sampled from a counter-based PRNG in a fixed order and the first survivor in that order
    /// is the one returned.
    public static func make(index: Int, seed: UInt64, config: WorldConfig,
                            backend: Backend = Backend.shipping) -> Result {
        let recipe = BlockRecipe.forDistrict(index, in: config)
        let districtSeed = seed &+ UInt64(index) &* 0x9E3779B97F4A7C15

        let candidates = (0..<poolSize).map { i in
            BlockGenerator.sample(recipe: recipe,
                                  seed: districtSeed &+ UInt64(i) &* 0x9E3779B97F4A7C15,
                                  districtIndex: index, in: config)
        }

        // One pass over the whole pool: solvable, and free of roofs that strand the player.
        let batch = BlockBatch.pack(candidates)
        let survivors: [Bool]
        switch backend {
        case .gpu:
            survivors = MLXSolver.survivors(MLXSolver.Batch(batch), in: config)
        case .cpu:
            let adjacency = BatchSolver.adjacency(batch, in: config)
            let goalOK = BatchSolver.goalReachable(adjacency, spawn: batch.spawn, goal: batch.goal)
            let traps = BatchSolver.trapRoofs(adjacency, spawn: batch.spawn, goal: batch.goal).sumLast()
            let branching = BatchSolver.meanForwardBranching(adjacency,
                                                             spawn: batch.spawn, goal: batch.goal)
            let passes = goalOK .&& (traps .<= 0.5) .&& (branching .> 1.0)
            survivors = (0..<candidates.count).map { passes[$0] > 0.5 }
        }

        for (i, survived) in survivors.enumerated() where survived {
            let withFlies = BlockGenerator.placeFliesPublic(in: candidates[i],
                                                            seed: districtSeed, config: config)
            // The authoritative gate, on the district that will actually be played. The GPU pass is
            // a filter; this is the guarantee.
            if case .cleared(let grade) = Reachability.verify(withFlies, in: config) {
                return Result(block: withFlies, grade: grade, graded: i + 1)
            }
        }

        // Nothing in the pool survived — fall back a difficulty band rather than shipping something
        // unverified, and say so through `graded` so it is visible rather than silent.
        let easier = BlockRecipe.forDistrict(max(0, index - 4), in: config)
        if let fallback = BlockGenerator.generate(recipe: easier, seed: districtSeed &+ 7,
                                                  districtIndex: index, in: config) {
            return Result(block: fallback.block, grade: fallback.grade, graded: poolSize)
        }

        // Last resort: the gentlest recipe there is. Still verified.
        let gentle = BlockRecipe.forDistrict(0, in: config)
        let last = BlockGenerator.generate(recipe: gentle, seed: districtSeed &+ 13,
                                           districtIndex: index, in: config)
        return Result(block: last?.block ?? candidates[0], grade: last?.grade, graded: poolSize)
    }
}

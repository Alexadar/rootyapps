import XCTest
import FroggoSim
import ReachabilityKit

/// Where the CPU tensor layer wins and where MLX does.
///
/// This is a measurement, not an assertion about performance — the thresholds are deliberately loose
/// so it documents a shape rather than failing on a quiet machine. It exists because the choice
/// "which backend runs the live world" was being made on intuition in two apps at once, and the
/// citypigeon session measured something that reframed it: at batch size 1, MLX's GPU and CPU
/// devices cost the *same* (6.24 ms vs 6.17 ms there). So the cost at B=1 is not GPU dispatch —
/// it is MLX's own per-operation overhead, graph construction and Swift↔C++ bridging, paid roughly
/// 200 times regardless of where the arithmetic lands. On arrays of a few dozen elements the
/// arithmetic itself is free.
///
/// The prediction that follows is that a thin Foundation elementwise layer, which builds no graph,
/// should beat MLX badly at N = 1 and lose badly at large N. Both halves are measured here rather
/// than assumed.
final class SolverCrossoverTests: XCTestCase {

    let w = WorldConfig.shipping

    private func districts(_ count: Int) -> [CityBlock] {
        (0..<count).map { i in
            BlockGenerator.sample(recipe: BlockRecipe.forDistrict(i % 12, in: w),
                                  seed: UInt64(i + 1) &* 0x9E3779B97F4A7C15,
                                  districtIndex: i % 12, in: w)
        }
    }

    /// Report min / median / max and the spread, never a lone mean.
    ///
    /// A single number invites being quoted to a precision it does not have — which is exactly what
    /// happened twice in this file's history, once on each side of a two-session exchange. Printing
    /// the spread beside the value makes over-quoting visible at the point of reading.
    ///
    /// The spread is also the *evidence that the measurement worked*, and a better one than any
    /// machine-load heuristic: 2% across repeats means the figure is real, 45% means it is not a
    /// figure at all. That distinction is what says MLX and `Tensor` here are not measured to
    /// comparable confidence, so a ratio between them is directional rather than exact.
    @discardableResult
    private func time(_ label: String, repeats: Int = 5, _ body: () -> Void) -> Double {
        var samples: [Double] = []
        for _ in 0..<repeats {
            let start = Date()
            body()
            samples.append(Date().timeIntervalSince(start))
        }
        samples.sort()
        let lo = samples.first!, hi = samples.last!, median = samples[samples.count / 2]
        let spread = lo > 0 ? (hi - lo) / lo * 100 : 0
        print(String(format: "  %-26s %7.3f  med %7.3f  %7.3f ms   spread %3.0f%%",
                     (label as NSString).utf8String!, lo * 1000, median * 1000, hi * 1000, spread))
        return median
    }

    func testCrossoverBetweenTensorAndMLX() {
        let sizes = [1, 16, 128, 512]

        // GLOBAL warm-up across every size before any timing.
        //
        // Per-case warm-up is not enough: MLX compiles kernels and grows its memory pool lazily and
        // *per shape*, so whichever case runs first pays for the ones after it and everything later
        // reads artificially fast. The citypigeon session hit this and nearly published a table in
        // which strictly more work measured strictly faster — an artefact only catchable because it
        // was self-contradictory. An ordering bug that merely inflated the first case by 30% would
        // have looked entirely plausible.
        //
        // Here the exposure runs the other way: `Tensor` at N=1 leads the table, so any unpaid
        // warm-up would make the Foundation layer look *worse* than it is. That is the comfortable
        // direction, which is exactly why it is worth removing rather than reasoning about.
        for n in sizes {
            let b = BlockBatch.pack(districts(n))
            _ = BatchSolver.adjacency(b, in: w)
            MLXSolver.adjacency(MLXSolver.Batch(b), in: w).reachable.eval()
        }

        print("\n=== adjacency cost per call ===")

        for n in sizes {
            let blocks = districts(n)
            let cpuBatch = BlockBatch.pack(blocks)
            let gpuBatch = MLXSolver.Batch(cpuBatch)
            let repeats = 5

            print("N = \(n)")
            let cpu = time("Tensor (Foundation, CPU)", repeats: repeats) {
                _ = BatchSolver.adjacency(cpuBatch, in: w)
            }
            let gpu = time("MLXSolver (Metal)", repeats: repeats) {
                let a = MLXSolver.adjacency(gpuBatch, in: w)
                a.reachable.eval()               // force evaluation; MLX is lazy
            }
            print(String(format: "  ratio  cpu/gpu = %.1fx (directional — see spreads)\n", cpu / gpu))
        }

        // Reverse the order at N=1. If warm-up were still leaking, running MLX first would move
        // both numbers; agreement between the two orderings is what says the figures are real.
        print("=== N=1, reversed order (MLX measured first) ===")
        let one0 = BlockBatch.pack(districts(1))
        let oneGPU0 = MLXSolver.Batch(one0)
        _ = time("MLXSolver first") {
            MLXSolver.adjacency(oneGPU0, in: w).reachable.eval()
        }
        _ = time("Tensor second") { _ = BatchSolver.adjacency(one0, in: w) }
        print("")

        // Only a shape claim, loose enough not to flake: at a single world the Foundation layer
        // must not be dramatically worse, because that is the case the shipping game runs.
        let one = BlockBatch.pack(districts(1))
        let oneGPU = MLXSolver.Batch(one)
        let cpu1 = time("N=1 cpu (assert)") { _ = BatchSolver.adjacency(one, in: w) }
        let gpu1 = time("N=1 gpu (assert)") {
            MLXSolver.adjacency(oneGPU, in: w).reachable.eval()
        }
        XCTAssertLessThan(cpu1, gpu1 * 3,
                          "the Foundation layer is unexpectedly far behind MLX at a single world")
    }
}

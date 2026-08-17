import XCTest
import MLX
import FroggoSim
import ReachabilityKit

/// The parity gate: the CPU solver and the GPU solver must agree.
///
/// `ReachabilityKit` grades districts on the CPU in `Double`; `FroggoSim` grades them on the GPU in
/// `Float`. Two implementations of one ruleset is exactly the arrangement that rots quietly — so it
/// is diffed rather than trusted, the same way `monstro_shooter.swift/torchsim/parity_diff.py` diffs
/// its torch reference against the Metal port and prints the worst disagreement.
///
/// This lives in the app's test target rather than the package's because MLX's Metal kernels are
/// only compiled by Xcode's build system; under `swift test` MLX has no metallib and aborts on its
/// first evaluation.
///
/// **On tolerance.** Reachability is a boolean, and `Float` versus `Double` can land either side of
/// the envelope boundary. So agreement is required *exactly* except where the required power sits
/// within τ of the ceiling — and the number of such boundary cases is itself reported, because if it
/// ever stops being a handful, the two solvers have drifted rather than merely rounded.
final class SolverParityTests: XCTestCase {

    let w = WorldConfig.shipping

    /// Districts the generator actually produces, not hand-made fixtures.
    private func realDistricts(count: Int) -> [CityBlock] {
        (0..<count).map { i in
            BlockGenerator.sample(
                recipe: BlockRecipe.forDistrict(i % 12, in: w),
                seed: UInt64(i + 1) &* 0x9E3779B97F4A7C15,
                districtIndex: i % 12,
                in: w
            )
        }
    }

    func testAdjacencyMatchesBetweenCPUAndGPU() {
        let blocks = realDistricts(count: 48)
        let cpuBatch = BlockBatch.pack(blocks)
        let cpu = BatchSolver.adjacency(cpuBatch, in: w)

        let gpuBatch = MLXSolver.Batch(cpuBatch)
        let gpu = MLXSolver.adjacency(gpuBatch, in: w)
        gpu.reachable.eval()
        let gpuReachable = gpu.reachable.asArray(Float.self)
        gpu.requiredPower.eval()
        let gpuPower = gpu.requiredPower.asArray(Float.self)

        XCTAssertEqual(gpuReachable.count, cpu.reachable.count)

        let tau = 0.01                     // boundary band, as a fraction of the envelope
        var disagreements = 0
        var boundaryCases = 0
        var worstPowerDelta = 0.0

        for i in 0..<cpu.reachable.count {
            let cpuOn = cpu.reachable[i] > 0.5
            let gpuOn = gpuReachable[i] > 0.5

            if cpuOn && gpuOn {
                let d = abs(cpu.requiredPower[i] - Double(gpuPower[i]))
                if d.isFinite { worstPowerDelta = max(worstPowerDelta, d) }
            }

            guard cpuOn != gpuOn else { continue }

            // Is this a genuine boundary case? Then a Float/Double split is expected, not drift.
            let power = cpuOn ? cpu.requiredPower[i] : Double(gpuPower[i])
            if abs(power - w.powerCeiling) < tau || !power.isFinite {
                boundaryCases += 1
            } else {
                disagreements += 1
            }
        }

        print("""
            parity: \(cpu.reachable.count) pairs across \(blocks.count) districts
              hard disagreements : \(disagreements)
              boundary cases     : \(boundaryCases)
              worst |Δ power|    : \(worstPowerDelta)
            """)

        XCTAssertEqual(disagreements, 0, "CPU and GPU solvers disagree away from the boundary")
        XCTAssertLessThan(worstPowerDelta, 1e-3,
                          "required power drifted by \(worstPowerDelta) between implementations")
        XCTAssertLessThan(Double(boundaryCases) / Double(cpu.reachable.count), 0.001,
                          "too many boundary flips — that is drift, not rounding")
    }

    func testSolvabilityVerdictsMatch() {
        // The verdict that actually gates shipping: is this district crossable and trap-free?
        let blocks = realDistricts(count: 48)
        let cpuBatch = BlockBatch.pack(blocks)
        let cpu = BatchSolver.adjacency(cpuBatch, in: w)

        let goalOK = BatchSolver.goalReachable(cpu, spawn: cpuBatch.spawn, goal: cpuBatch.goal)
        let traps = BatchSolver.trapRoofs(cpu, spawn: cpuBatch.spawn, goal: cpuBatch.goal).sumLast()
        let cpuVerdict = (0..<blocks.count).map { goalOK[$0] > 0.5 && traps[$0] < 0.5 }

        let gpuVerdict = MLXSolver.survivors(MLXSolver.Batch(cpuBatch), in: w)

        XCTAssertEqual(cpuVerdict.count, gpuVerdict.count)
        let mismatches = zip(cpuVerdict, gpuVerdict).enumerated().filter { $0.element.0 != $0.element.1 }
        XCTAssertTrue(mismatches.isEmpty,
                      "districts \(mismatches.map(\.offset)) got different verdicts on CPU vs GPU")
    }

    func testGPUGradesALargePoolQuickly() {
        // The reason the GPU path exists: rejection has to be cheap enough that the generator can
        // afford to be picky. 512 districts is well past what the game needs between levels.
        let blocks = realDistricts(count: 512)
        let batch = MLXSolver.Batch(BlockBatch.pack(blocks))

        let start = Date()
        let survivors = MLXSolver.survivors(batch, in: w)
        let elapsed = Date().timeIntervalSince(start)

        print("GPU graded \(blocks.count) districts in \(String(format: "%.3f", elapsed))s — \(survivors.filter { $0 }.count) survived")
        XCTAssertEqual(survivors.count, blocks.count)
        XCTAssertLessThan(elapsed, 3.0, "grading a 512-district pool took \(elapsed)s")
    }
}

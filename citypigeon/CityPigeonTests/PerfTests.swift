import XCTest
import MLX
@testable import CityPigeon

/// Where the frame budget goes — **in DEBUG. These are not shipping numbers.**
///
/// ⚠️ Every figure this file prints is measured against an unoptimised build, and it cannot be
/// otherwise: `@testable import` requires `ENABLE_TESTABILITY`, which is Debug-only, so the app
/// module *and* MLX's template-heavy C++ compile at `-Onone`. That is not a constant factor —
/// measured on the same machine, the same step costs **22.0 ms in Debug and 2.28 ms in Release**,
/// a 10× difference that silently turned "14% of a frame" into "132% of a frame".
///
/// I reported the Debug figures as shipping performance for most of this build before noticing.
/// For a real number run the benchmark inside the Release app, which is what `Engine/Benchmark.swift`
/// exists for:
///
///     xcodebuild build -configuration Release -destination 'platform=macOS' …
///     CITYPIGEON_BENCH=1 'build/…/Release/City Pigeon.app/Contents/MacOS/City Pigeon'
///
/// The same binary runs on a phone, which is the measurement that actually decides the budget.
///
/// What this file is still good for: catching a **regression** in operation count. The ratios
/// between its numbers are meaningful even when their magnitudes are not, which is why the
/// thresholds below are deliberately generous and framed as "has something got dramatically worse".
final class PerfTests: XCTestCase {

    private func timeSteps(_ label: String, batch: Int, iterations: Int,
                           body: (inout World) -> Void) -> Double {
        var world = World(batch: batch, config: .shipping, seed: 1)
        for _ in 0..<40 { body(&world) }                 // warm up device and kernels
        let t0 = Date()
        for _ in 0..<iterations { body(&world) }
        let ms = Date().timeIntervalSince(t0) / Double(iterations) * 1000
        print(String(format: "PERF %-28s B=%-5d %6.3f ms", (label as NSString).utf8String!, batch, ms))
        return ms
    }

    func testWhereTheFrameGoes() throws {
        try MachineLoad.skipIfBusy()
        let idle = Intent.idle(batch: 1)
        let stepOnly = timeSteps("step, idle intent", batch: 1, iterations: 200) {
            Step.advance(&$0, intent: idle)
        }
        let withPolicy = timeSteps("step + autopilot", batch: 1, iterations: 200) {
            Step.advance(&$0, intent: Policy.autopilot($0))
        }
        let policyOnly = withPolicy - stepOnly

        print(String(format: "PERF policy overhead %.3f ms · total %.3f of a 16.67 ms frame (%.0f%%)",
                     policyOnly, withPolicy, withPolicy / 16.67 * 100))

        // Debug thresholds, and generous on purpose: this is an operation-count regression guard,
        // not a playability check. Release is ~10x faster — see the file comment.
        XCTAssertLessThan(stepOnly, 30.0,
                          "the Debug step cost has roughly doubled — the op count has grown")
        XCTAssertLessThan(withPolicy, 45.0,
                          "the Debug autopilot step cost has roughly doubled")
    }

    /// The batch payoff must survive the real step, not just the synthetic one.
    func testBatchingStillAmortisesOnTheRealStep() throws {
        try MachineLoad.skipIfBusy()
        let idle1 = Intent.idle(batch: 1)
        let one = timeSteps("real step", batch: 1, iterations: 100) {
            Step.advance(&$0, intent: idle1)
        }
        let idleN = Intent.idle(batch: 4096)
        let many = timeSteps("real step", batch: 4096, iterations: 20) {
            Step.advance(&$0, intent: idleN)
        }
        let speedup = one * 4096 / many
        print(String(format: "PERF 4096 worlds cost %.1fx one world → %.0fx effective speedup",
                     many / one, speedup))
        XCTAssertGreaterThan(speedup, 200,
                             "batching no longer amortises on the real step, which is the entire "
                             + "reason the engine is written this way")
    }
}

extension PerfTests {

    /// **The optimisation that matters.**
    ///
    /// The step is launch-bound: B=1 and B=4096 cost nearly the same, so the ~7 ms is almost entirely
    /// per-operation GPU dispatch, not arithmetic. For a single world the arrays are 8 to 24 elements
    /// — dispatching those to the GPU costs far more than computing them. MLX's CPU device runs the
    /// identical graph with no dispatch, which is exactly why froggo2 shipped `Backend.shipping = .cpu`.
    func testCPUDeviceIsFasterForASingleWorld() throws {
        try MachineLoad.skipIfBusy()
        let idle = Intent.idle(batch: 1)

        Device.setDefault(device: Device(.gpu))
        var g = World(batch: 1, config: .shipping, seed: 1)
        for _ in 0..<40 { Step.advance(&g, intent: idle) }
        var t0 = Date()
        for _ in 0..<200 { Step.advance(&g, intent: idle) }
        let gpuMs = Date().timeIntervalSince(t0) / 200 * 1000

        Device.setDefault(device: Device(.cpu))
        var c = World(batch: 1, config: .shipping, seed: 1)
        for _ in 0..<40 { Step.advance(&c, intent: idle) }
        t0 = Date()
        for _ in 0..<200 { Step.advance(&c, intent: idle) }
        let cpuMs = Date().timeIntervalSince(t0) / 200 * 1000

        Device.setDefault(device: Device(.gpu))
        print(String(format: "PERF B=1 gpu %.3f ms · cpu %.3f ms · %.1fx", gpuMs, cpuMs, gpuMs / cpuMs))
    }

    /// And the two devices must agree, or "same code path" is a slogan.
    func testCPUAndGPUAgreeExactly() {
        Device.setDefault(device: Device(.gpu))
        var g = World(batch: 4, config: .shipping, seed: 31)
        for _ in 0..<600 { Step.advance(&g, intent: Policy.autopilot(g)) }
        g.evaluate()
        let gScore = g.score.asArray(Float.self), gX = g.pigeonX.asArray(Float.self)

        Device.setDefault(device: Device(.cpu))
        var c = World(batch: 4, config: .shipping, seed: 31)
        for _ in 0..<600 { Step.advance(&c, intent: Policy.autopilot(c)) }
        c.evaluate()
        let cScore = c.score.asArray(Float.self), cX = c.pigeonX.asArray(Float.self)

        Device.setDefault(device: Device(.gpu))
        print("PERF parity: gpu scores \(gScore.map { Int($0) }) · cpu \(cScore.map { Int($0) })")
        XCTAssertEqual(gScore, cScore, "CPU and GPU disagree on the score")
        for i in 0..<4 { XCTAssertEqual(gX[i], cX[i], accuracy: 1e-2, "pigeon x diverged in world \(i)") }
    }
}

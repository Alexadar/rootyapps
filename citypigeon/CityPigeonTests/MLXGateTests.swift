import XCTest
import MLX
@testable import CityPigeon

/// The decisive day-1 gate, and the reason it is XCTest in the app's test bundle rather than
/// swift-testing in a package.
///
/// MLX compiles everywhere, but its Metal kernels are built by **Xcode's** build system. Under
/// `swift test` there is no metallib and MLX aborts on its first evaluation; in the iOS Simulator
/// there is no supported `MTLGPUFamily` and `Device::Device()` calls `abort()` outright — a C++
/// exception across a C ABI, so it cannot be guarded with `try`. `xcodebuild test` on macOS is the
/// only place these can run, which is why the test target is macOS-only.
final class MLXGateTests: XCTestCase {

    /// The whole planned vocabulary compiles and evaluates.
    func testBatchedVocabularyEvaluates() {
        let v = Gate.smoke(batch: 1)
        XCTAssertTrue(v.isFinite, "MLX produced a non-finite result from the vocabulary probe")
    }

    /// The engine must be batch-shaped, not batch-*capable*: solving one world and solving many is
    /// the same code path distinguished only by a leading dimension. If this ever needs a special
    /// case for B == 1, the architecture has already failed.
    func testTheSameCodePathRunsAtEveryBatchSize() {
        for b in [1, 8, 256, 1024] {
            let out = Gate.syntheticStep(batch: b)
            XCTAssertEqual(out.shape, [b], "step at B=\(b) did not return one row per world")
            XCTAssertTrue(out.asArray(Float.self).allSatisfy { $0.isFinite },
                          "step at B=\(b) produced a non-finite lane")
        }
    }

    /// **The gate that decides the architecture.**
    ///
    /// A 120 Hz frame is 8.33 ms for engine *and* renderer together. The engine's share has to be a
    /// small fraction of that. This is where MLX is least comfortable — it amortises per-op dispatch
    /// across large batches, and a game step is dozens of tiny ops on arrays of length 8 to 16.
    ///
    /// Not asserted tightly on the first run: the number is printed, because what matters right now
    /// is knowing it. The threshold below is deliberately generous (half a frame) so that this fails
    /// only when the approach is genuinely unviable rather than merely slower than ideal.
    func testSingleWorldStepFitsInAFrame() throws {
        try MachineLoad.skipIfBusy()
        // Warm up: the first evaluation pays for device creation and kernel loading.
        for _ in 0..<20 { _ = Gate.syntheticStep(batch: 1) }

        let iterations = 300
        let t0 = Date()
        for _ in 0..<iterations { _ = Gate.syntheticStep(batch: 1) }
        let perStepMs = Date().timeIntervalSince(t0) / Double(iterations) * 1000

        print("GATE: B=1 step = \(String(format: "%.3f", perStepMs)) ms  (frame budget 8.33 ms)")
        XCTAssertLessThan(perStepMs, 4.0,
                          "one B=1 step costs \(perStepMs) ms — over half a 120 Hz frame before any "
                          + "rendering. The SoA layout stays; a scalar backend goes behind the same "
                          + "interface with a parity test.")
    }

    /// The payoff the architecture is being bought for: many worlds must cost far less than many
    /// times one world, or there is no reason to accept the simulator loss.
    func testBatchingIsActuallyAmortised() throws {
        try MachineLoad.skipIfBusy()
        for _ in 0..<20 { _ = Gate.syntheticStep(batch: 1024) }

        let iterations = 30
        var t0 = Date()
        for _ in 0..<iterations { _ = Gate.syntheticStep(batch: 1) }
        let oneMs = Date().timeIntervalSince(t0) / Double(iterations) * 1000

        t0 = Date()
        for _ in 0..<iterations { _ = Gate.syntheticStep(batch: 1024) }
        let manyMs = Date().timeIntervalSince(t0) / Double(iterations) * 1000

        let speedup = (oneMs * 1024) / manyMs
        print("GATE: B=1 \(String(format: "%.3f", oneMs)) ms · B=1024 \(String(format: "%.3f", manyMs)) ms "
              + "· effective speedup \(String(format: "%.0f", speedup))×")
        XCTAssertGreaterThan(speedup, 50,
                             "1024 worlds cost \(manyMs) ms against \(oneMs) ms for one — batching is "
                             + "not amortising, which is the entire justification for MLX here.")
    }

    /// MLX must be on the GPU. If it silently fell back, every number above is measuring something
    /// other than what will ship.
    func testRunningOnTheGPU() {
        let device = "\(Device.defaultDevice())".lowercased()
        print("GATE: MLX device = \(device)")
        XCTAssertTrue(device.contains("gpu"), "MLX is not on the GPU: \(device)")
    }
}

import Testing
import Foundation
import MLX
@testable import FroggoSim
import ReachabilityKit

/// Day-1 viability gate. Not a game test — a "does the chosen architecture actually run here" test.
@Suite("MLX viability gate")
struct GateTests {

    @Test("the batched vocabulary evaluates on the default device")
    func smokeRuns() {
        let out = Gate.smoke()
        #expect(out.count == 4 * 6)
        #expect(out.allSatisfy { $0.isFinite })
    }

    @Test("the default device is the GPU")
    func deviceIsGPU() {
        // The whole architecture rests on the solver running on the GPU. If this ever reports CPU
        // on an Apple-silicon machine, the batched generate-and-verify has quietly become a loop.
        let device = Device.defaultDevice()
        #expect("\(device)".lowercased().contains("gpu"), "MLX default device was \(device)")
    }

    @Test("both Kits link and share one config")
    func constantsComeFromOnePlace() {
        #expect(Gate.config.gravity == WorldConfig.shipping.gravity)
    }

    @Test("a district-sized batch is fast enough to generate during play")
    func batchThroughput() {
        // 4096 candidate districts is the generate-and-verify batch. It has to fit comfortably
        // inside the time between one district being cleared and the next being needed.
        let start = Date()
        for _ in 0..<8 { _ = Gate.smoke() }
        let elapsed = Date().timeIntervalSince(start)
        #expect(elapsed < 5.0, "8 batched passes took \(elapsed)s")
    }
}

import XCTest
import MLX
import FroggoSim
import ReachabilityKit

/// The decisive day-1 gate: MLX compiles everywhere, but its Metal kernels are built by Xcode's
/// build system, not by `swift build` from the command line. This test exists to prove the shipping
/// path works — an Xcode-built product that actually evaluates a batched expression on the GPU.
final class MLXRuntimeGateTests: XCTestCase {

    func testBatchedProgramEvaluatesOnGPU() {
        let out = Gate.smoke()
        XCTAssertEqual(out.count, 24)
        XCTAssertTrue(out.allSatisfy { $0.isFinite })
    }

    func testDefaultDeviceIsGPU() {
        let device = "\(Device.defaultDevice())".lowercased()
        XCTAssertTrue(device.contains("gpu"), "MLX default device was \(device)")
    }

    func testConstantsComeFromOnePlace() {
        XCTAssertEqual(Gate.config.gravity, WorldConfig.shipping.gravity)
    }
}

import XCTest
import FroggoSim
import ReachabilityKit

/// The invariant that keeps the app launchable in the iOS Simulator.
///
/// MLX aborts — not throws — when it cannot create a Metal device, which is the case in the
/// simulator. The abort is **eager**: MLX's global singletons build the Metal device inside their
/// own constructors, so it is triggered by entering MLX at all rather than by requesting GPU work.
/// Two separate routes were observed in practice:
///
///     MLXArray.init(converting:) → allocator::malloc → MetalAllocator() → metal::device  (here)
///     scheduler() → new_stream  → gpu::new_stream    → metal::device                     (citypigeon)
///
/// `Device.setDefault(.cpu)` is itself an MLX entry and trips the same abort, so there is no
/// ordering that makes MLX safe there.
///
/// The consequence is subtle enough to be worth a test rather than a comment: choosing the `.cpu`
/// backend is *not* the protection. Not calling MLX is. A future change that adds a small MLX helper
/// to the app, or a `Device.defaultDevice()` diagnostic, or lets a shared code path flip to `.gpu`,
/// would compile, pass every other test on macOS, and then kill the app at launch on every
/// simulator — the one place the game gets checked before shipping.
///
/// So this file asserts the shape of the dependency, not its behaviour.
final class SimulatorSafetyTests: XCTestCase {

    private var appSources: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()      // Froggo2Tests
            .deletingLastPathComponent()      // froggo2
            .appendingPathComponent("Froggo2")
    }

    private func swiftFiles(under root: URL) throws -> [URL] {
        guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
            return []
        }
        return e.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }

    /// Strip comments so documentation may discuss MLX freely — this file and `DistrictFactory`
    /// both have to be able to name the thing they are guarding against.
    private func code(of file: URL) throws -> String {
        try String(contentsOf: file, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.hasPrefix("//") && !$0.hasPrefix("///") && !$0.hasPrefix("*") }
            .joined(separator: "\n")
    }

    func testTheShippingBackendIsCPU() {
        XCTAssertEqual(DistrictFactory.Backend.shipping, .cpu,
                       "the shipping backend moved off the CPU — see this file's notes before doing that")
    }

    func testTheAppTargetNeverEntersMLX() throws {
        let files = try swiftFiles(under: appSources)
        XCTAssertFalse(files.isEmpty, "found no app sources to audit at \(appSources.path)")

        for file in files {
            let source = try code(of: file)
            let name = file.lastPathComponent

            XCTAssertFalse(source.contains("import MLX"),
                           "\(name) imports MLX. The app target must never enter MLX — it aborts in the "
                           + "iOS Simulator. Route the work through DistrictFactory/BatchSolver instead.")
            XCTAssertFalse(source.contains("MLXSolver"),
                           "\(name) references MLXSolver. Only DistrictFactory's .gpu branch may, and "
                           + "the app never selects it.")
            XCTAssertFalse(source.contains("MLXArray"),
                           "\(name) constructs an MLXArray. That alone creates the Metal device and "
                           + "aborts in the simulator.")
            XCTAssertFalse(source.contains("Device.setDefault") || source.contains("Device.defaultDevice"),
                           "\(name) touches MLX's Device API. That is itself an MLX entry and aborts "
                           + "in the simulator — it does not avoid the problem, it causes it.")
        }
    }

    /// The default path really does resolve to the CPU solver, whatever the enum says.
    func testDefaultDistrictGenerationProducesAVerifiedDistrict() {
        let w = WorldConfig.shipping
        let result = DistrictFactory.make(index: 0, seed: 0xF206_0811, config: w)
        XCTAssertTrue(Reachability.verify(result.block, in: w).isCleared,
                      "the default backend emitted a district the solver has not cleared")
        XCTAssertNotNil(result.grade)
    }
}

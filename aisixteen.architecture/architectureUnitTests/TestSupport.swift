import Foundation
import RedesignKit
import XCTest
@testable import Architecture

/// A generator the test advances one step at a time.
///
/// The reason it exists rather than a fast timing mock: "cancel at step 17" against a generator
/// that sleeps is a race, and a race in a test suite is a suite that goes red once a fortnight for
/// no reason anyone can reproduce. Here the test IS the clock.
final class SteppedRedesignGenerator: RedesignGenerator, @unchecked Sendable {

    let checkpointKind = "stepped.v1"
    private let plan: RedesignPlan
    private let lock = NSLock()
    private var onStep: (@Sendable (GenerationStep) -> Void)?
    private var continuation: CheckedContinuation<RedesignOutput, Error>?
    private var request: RedesignRequest?
    private var current = 0
    private var latest: GenerationCheckpoint?
    private var cancelled = false
    /// Set to make the next `advance()` throw instead.
    var failure: RedesignError?

    init(plan: RedesignPlan = .standard) {
        self.plan = plan
    }

    func cancel() {
        lock.lock(); cancelled = true; let continuation = self.continuation; self.continuation = nil; lock.unlock()
        continuation?.resume(throwing: RedesignError.cancelled)
    }

    func captureCheckpoint() async -> GenerationCheckpoint? {
        lock.lock(); defer { lock.unlock() }
        return latest
    }

    func generate(_ request: RedesignRequest,
                  resuming checkpoint: GenerationCheckpoint?,
                  onStep: @escaping @Sendable (GenerationStep) -> Void) async throws -> RedesignOutput {
        if let checkpoint,
           let rejection = checkpoint.rejection(forKind: checkpointKind,
                                                digest: request.digest,
                                                deviceID: "mock-device") {
            throw RedesignError.checkpointRejected(rejection)
        }
        lock.lock()
        self.request = request
        self.onStep = onStep
        self.current = checkpoint?.step ?? 0
        self.cancelled = false
        lock.unlock()

        return try await withCheckedThrowingContinuation { continuation in
            lock.lock(); self.continuation = continuation; lock.unlock()
        }
    }

    /// Report one more step, exactly when the test says so.
    func advance() {
        lock.lock()
        guard let request, let onStep, !cancelled else { lock.unlock(); return }
        if let failure {
            let continuation = self.continuation
            self.continuation = nil
            lock.unlock()
            continuation?.resume(throwing: failure)
            return
        }
        current += 1
        let step = current
        let stage = plan.stage(atStep: step)
        let checkpoint = plan.offersCheckpoint(atStep: step)
            ? GenerationCheckpoint(kind: checkpointKind,
                                   requestDigest: request.digest,
                                   step: step,
                                   totalSteps: plan.totalSteps,
                                   deviceID: "mock-device",
                                   state: Data([UInt8(step % 256)]),
                                   createdAt: Date())
            : nil
        if let checkpoint { latest = checkpoint }
        let finished = step >= plan.totalSteps
        let continuation = finished ? self.continuation : nil
        if finished { self.continuation = nil }
        lock.unlock()

        onStep(GenerationStep(step: step,
                              totalSteps: plan.totalSteps,
                              stage: stage,
                              preview: plan.emitsPreview(atStep: step)
                                  ? PreviewImage(pixels: Data(repeating: 200, count: 8 * 8 * 4),
                                                 size: PixelSize(width: 8, height: 8))
                                  : nil,
                              checkpoint: checkpoint))

        if finished {
            continuation?.resume(returning: RedesignOutput(
                image: PreviewImage(pixels: Data(repeating: 210, count: 8 * 8 * 4),
                                    size: PixelSize(width: 8, height: 8)),
                seed: request.seed,
                stepsRun: plan.totalSteps,
                resumedFromStep: nil,
                createdAt: Date()))
        }
    }

    func advance(to step: Int) {
        while current < step { advance() }
    }
}

enum Fixtures {

    static func request(project: String = "living-room",
                        variation: Int = 1,
                        of count: Int = 1,
                        seed: UInt32 = 4242) -> RedesignRequest {
        RedesignRequest(id: "\(project)-\(variation)",
                        projectID: project,
                        variationIndex: variation,
                        variationCount: count,
                        source: ImageHandle(url: URL(fileURLWithPath: "/tmp/source.heic"),
                                            size: PixelSize(width: 100, height: 100)),
                        controls: [],
                        mode: .interior,
                        prompt: "Bright Scandinavian living room",
                        presetID: "scandi",
                        seed: seed,
                        spaceName: "Living room",
                        styleName: "Scandinavian")
    }

    static func shot(mode: DirectionMode = .interior,
                     provenance: RedesignKit.DepthProvenance = .lidar,
                     withDepth: Bool = true) -> SourceShot {
        let size = PixelSize(width: 64, height: 64)
        return SourceShot(mode: mode,
                          imageData: Data(repeating: 7, count: 128),
                          pixelSize: size,
                          depthValues: withDepth ? DepthSource.synthetic(size: size) : [],
                          depthSize: withDepth ? size : PixelSize(width: 0, height: 0),
                          provenance: provenance)
    }

    /// A temporary directory that cleans itself up.
    static func temporaryDirectory(_ name: String = "arch") -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// The repository's `Architecture/` source directory, for the guards that scan source.
    ///
    /// Derived from `#filePath` rather than from the bundle: a test bundle has no idea where the
    /// project is, and hardcoding an absolute path breaks the moment the repo moves.
    static var sourceDirectory: URL {
        URL(fileURLWithPath: #filePath)          // …/architectureUnitTests/TestSupport.swift
            .deletingLastPathComponent()          // …/architectureUnitTests
            .deletingLastPathComponent()          // …/aisixteen.architecture
            .appendingPathComponent("Architecture", isDirectory: true)
    }

    static func swiftFiles(in directory: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: directory,
                                                              includingPropertiesForKeys: nil) else {
            return []
        }
        return enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }
}

extension XCTestCase {
    /// Let queued main-actor work run, without sleeping.
    ///
    /// A `Task.sleep` in a test is a guess about how long something takes, and it is either too
    /// short (flaky) or too long (slow). Yielding drains the queue and returns as soon as it is
    /// empty.
    @MainActor
    func settle(_ turns: Int = 30) async {
        for _ in 0..<turns { await Task.yield() }
    }

    /// Wait until `condition` holds, or fail with `message`.
    ///
    /// ⚠️ USE THIS, NOT `settle()`, FOR ANYTHING THAT CROSSES AN ASYNC BOUNDARY.
    ///
    /// A fixed number of `Task.yield()`s is not a barrier — it is a guess about how many
    /// scheduling turns some other work needs, and the number that happens to be enough today is
    /// not the number that is enough tomorrow. Two engine tests here passed on `settle()` twice
    /// and then went red with the source unchanged: the generator's error path runs
    /// `withCheckedThrowingContinuation` → `Task` → main-actor hop, and thirty yields stopped
    /// covering it. A test that flickers between green and red without the code moving is worse
    /// than a failing one, because it teaches you to re-run instead of to look.
    ///
    /// Waiting on the actual post-condition is both faster in the common case and honest about
    /// what is being asserted.
    @MainActor
    func settle(until condition: () -> Bool,
                timeout: TimeInterval = 5,
                _ message: @autoclosure () -> String = "condition never became true",
                file: StaticString = #filePath,
                line: UInt = #line) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            await Task.yield()
        }
        XCTFail(message(), file: file, line: line)
    }
}

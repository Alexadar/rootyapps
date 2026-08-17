import Foundation
import Synchronization

/// A generator that behaves like the real one will, minus the model.
///
/// The `.device` speed is deliberately slow — three to eight seconds a step, thirty-two steps, so
/// one and a half to four minutes. That is the real window, and it is on purpose: a UI judgement
/// made against an instant generator is a judgement about a different app. The whole design of
/// this product is about making a multi-minute wait bearable, and you cannot evaluate that in
/// half a second.
///
/// The preview it emits is a deterministic function of (seed, step), so a run resumed from a
/// checkpoint is visually continuous — which is how resume can be checked by eye rather than only
/// by assertion.
public final class MockRedesignGenerator: RedesignGenerator, @unchecked Sendable {

    public enum Speed: Sendable, Equatable {
        /// 3–8 s per step, randomised once per run. The real window.
        case device
        /// 50 ms per step. For iterating on the UI.
        case fast
        /// No delay at all. For tests that do not care about time.
        case instant
        case fixed(Duration)
    }

    public let checkpointKind: String
    private let speed: Speed
    private let deviceID: String
    private let previewEdge: Int

    /// Guarded state. `cancel()` is called from wherever the user tapped, while the run loop reads
    /// it between steps. `Mutex`, not `NSLock`: NSLock's lock/unlock are unavailable from async
    /// contexts and are a hard error under Swift 6.
    private let control = Mutex(Control())

    private struct Control {
        var cancelled = false
        var latest: GenerationCheckpoint?
    }

    public init(speed: Speed = .device,
                deviceID: String = "mock-device",
                checkpointKind: String = "mock.v1",
                previewEdge: Int = 64) {
        self.speed = speed
        self.deviceID = deviceID
        self.checkpointKind = checkpointKind
        self.previewEdge = previewEdge
    }

    public func cancel() {
        control.withLock { $0.cancelled = true }
    }

    public func captureCheckpoint() async -> GenerationCheckpoint? {
        control.withLock { $0.latest }
    }

    public func generate(_ request: RedesignRequest,
                         resuming checkpoint: GenerationCheckpoint?,
                         onStep: @escaping @Sendable (GenerationStep) -> Void) async throws -> RedesignOutput {
        control.withLock { $0.cancelled = false; $0.latest = nil }

        let plan = request.plan
        var startStep = 1
        var resumedFrom: Int?

        if let checkpoint {
            // Validate here, not in the engine: only the generator knows whether it can read its
            // own blob. Throwing rather than silently restarting is what lets the engine record
            // the provenance and delete the dead file.
            if let rejection = checkpoint.rejection(forKind: checkpointKind,
                                                    digest: request.digest,
                                                    deviceID: deviceID) {
                throw RedesignError.checkpointRejected(rejection)
            }
            startStep = checkpoint.resumesAtStep
            resumedFrom = checkpoint.step
        }

        // Randomised once per run, not per step: a real device's per-step time is fairly stable
        // within a run and varies between runs, and an estimator that converges is only worth
        // testing against a signal that behaves the same way.
        let runSpeed = Self.resolve(speed)

        for step in startStep...plan.totalSteps {
            try Task.checkCancellation()
            if control.withLock({ $0.cancelled }) { throw RedesignError.cancelled }

            let stage = plan.stage(atStep: step)
            // Weighted, so full resolution really is the long step the estimator has to cope with
            // rather than a uniform tick.
            try await Self.sleep(seconds: runSpeed, weight: plan.weight(of: stage))

            let preview = plan.emitsPreview(atStep: step)
                ? Self.previewImage(seed: request.seed, step: step, edge: previewEdge)
                : nil

            var offered: GenerationCheckpoint?
            if plan.offersCheckpoint(atStep: step) {
                offered = GenerationCheckpoint(kind: checkpointKind,
                                               requestDigest: request.digest,
                                               step: step,
                                               totalSteps: plan.totalSteps,
                                               deviceID: deviceID,
                                               state: Self.stateBlob(seed: request.seed, step: step),
                                               createdAt: Date())
            }
            // Kept regardless of cadence, so `captureCheckpoint()` on a background transition
            // returns state as of the step just finished rather than up to four steps stale.
            let newest = GenerationCheckpoint(kind: checkpointKind,
                                              requestDigest: request.digest,
                                              step: step,
                                              totalSteps: plan.totalSteps,
                                              deviceID: deviceID,
                                              state: Self.stateBlob(seed: request.seed, step: step),
                                              createdAt: Date())
            control.withLock { $0.latest = step < plan.totalSteps ? newest : nil }

            onStep(GenerationStep(step: step,
                                  totalSteps: plan.totalSteps,
                                  stage: stage,
                                  preview: preview,
                                  checkpoint: offered))
        }

        control.withLock { $0.latest = nil }

        return RedesignOutput(image: Self.previewImage(seed: request.seed,
                                                       step: plan.totalSteps,
                                                       edge: max(previewEdge, 256)),
                              seed: request.seed,
                              stepsRun: plan.totalSteps - startStep + 1,
                              resumedFromStep: resumedFrom,
                              createdAt: Date())
    }

    // ── pacing ───────────────────────────────────────────────────────────────────────────────

    /// Seconds per unit-weight step, fixed once per run.
    static func resolve(_ speed: Speed) -> Double {
        switch speed {
        case .device: return Double.random(in: 3.0...8.0)
        case .fast: return 0.05
        case .instant: return 0
        case .fixed(let duration):
            return Double(duration.components.seconds)
                + Double(duration.components.attoseconds) / 1e18
        }
    }

    static func sleep(seconds: Double, weight: Double) async throws {
        guard seconds > 0 else { return }
        try await Task.sleep(nanoseconds: UInt64(seconds * weight * 1_000_000_000))
    }

    static func sleep(speed: Speed, weight: Double) async throws {
        try await sleep(seconds: resolve(speed), weight: weight)
    }

    // ── the picture ──────────────────────────────────────────────────────────────────────────

    /// A deterministic procedural field. Never model output, and it should not be mistakable for
    /// one — it is a smooth two-tone gradient with a moving band, not a photograph.
    static func previewImage(seed: UInt32, step: Int, edge: Int) -> PreviewImage {
        var pixels = [UInt8](repeating: 0, count: edge * edge * 4)
        let phase = Double(step) * 0.17 + Double(seed % 360) * 0.01
        for y in 0..<edge {
            for x in 0..<edge {
                let u = Double(x) / Double(edge)
                let v = Double(y) / Double(edge)
                let band = (sin((u * 3 + phase)) * cos(v * 2 + phase) + 1) / 2
                let warm = 0.55 + 0.35 * band
                let offset = (y * edge + x) * 4
                pixels[offset] = UInt8(min(max(warm * 235, 0), 255))
                pixels[offset + 1] = UInt8(min(max(warm * 215, 0), 255))
                pixels[offset + 2] = UInt8(min(max(warm * 190, 0), 255))
                pixels[offset + 3] = 255
            }
        }
        return PreviewImage(pixels: Data(pixels), size: PixelSize(width: edge, height: edge))
    }

    static func stateBlob(seed: UInt32, step: Int) -> Data {
        var data = Data()
        withUnsafeBytes(of: seed.littleEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: Int32(step).littleEndian) { data.append(contentsOf: $0) }
        return data
    }
}

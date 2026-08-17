import Foundation
import Synchronization

/// Fails partway through a run.
///
/// The default is step 11, not step 0, and that is the whole point. Failing immediately never
/// exercises the interesting path: by step 11 the UI has already morphed into a picture frame, a
/// preview is on screen, a checkpoint exists on disk, and the queue has siblings waiting.
/// Unwinding *that* is what the failure card and the queue's "one failure does not kill the queue"
/// rule are for.
public final class FailingRedesignGenerator: RedesignGenerator, @unchecked Sendable {

    public let checkpointKind: String
    private let failAtStep: Int
    private let error: RedesignError
    private let speed: MockRedesignGenerator.Speed
    private let deviceID: String

    private let control = Mutex(Control())

    private struct Control {
        var cancelled = false
        var latest: GenerationCheckpoint?
    }

    public init(failAtStep: Int = 11,
                error: RedesignError = .outOfMemory,
                speed: MockRedesignGenerator.Speed = .fast,
                deviceID: String = "mock-device",
                checkpointKind: String = "mock.v1") {
        self.failAtStep = failAtStep
        self.error = error
        self.speed = speed
        self.deviceID = deviceID
        self.checkpointKind = checkpointKind
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
            if let rejection = checkpoint.rejection(forKind: checkpointKind,
                                                    digest: request.digest,
                                                    deviceID: deviceID) {
                throw RedesignError.checkpointRejected(rejection)
            }
            startStep = checkpoint.resumesAtStep
            resumedFrom = checkpoint.step
        }

        for step in startStep...plan.totalSteps {
            try Task.checkCancellation()
            // Cancellation is checked BEFORE the scheduled failure, so a user who taps cancel on
            // the step that was about to fail gets "cancelled" and no failure card. The user
            // pressed a button; the machine's opinion about what was going to go wrong next is
            // not the story to tell.
            if control.withLock({ $0.cancelled }) { throw RedesignError.cancelled }

            if step >= failAtStep { throw error }

            let stage = plan.stage(atStep: step)
            try await MockRedesignGenerator.sleep(speed: speed, weight: plan.weight(of: stage))

            let newest = GenerationCheckpoint(kind: checkpointKind,
                                              requestDigest: request.digest,
                                              step: step,
                                              totalSteps: plan.totalSteps,
                                              deviceID: deviceID,
                                              state: MockRedesignGenerator.stateBlob(seed: request.seed, step: step),
                                              createdAt: Date())
            control.withLock { $0.latest = step < plan.totalSteps ? newest : nil }

            onStep(GenerationStep(step: step,
                                  totalSteps: plan.totalSteps,
                                  stage: stage,
                                  preview: plan.emitsPreview(atStep: step)
                                      ? MockRedesignGenerator.previewImage(seed: request.seed, step: step, edge: 64)
                                      : nil,
                                  checkpoint: plan.offersCheckpoint(atStep: step) ? newest : nil))
        }

        // Only reachable when `failAtStep` is past the end — the configuration tests use to mean
        // "behave normally".
        return RedesignOutput(image: MockRedesignGenerator.previewImage(seed: request.seed,
                                                                        step: plan.totalSteps,
                                                                        edge: 256),
                              seed: request.seed,
                              stepsRun: plan.totalSteps - startStep + 1,
                              resumedFromStep: resumedFrom,
                              createdAt: Date())
    }
}

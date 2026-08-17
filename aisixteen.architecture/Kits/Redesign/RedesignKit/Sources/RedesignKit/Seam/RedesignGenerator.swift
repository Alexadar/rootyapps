import Foundation

/// One step of progress, reported by the generator as it happens.
///
/// Deliberately narrower than the design handoff's `GenerationProgress`, which conflated three
/// different owners: the generator (step, stage, preview), the engine (was it paused, and why)
/// and the estimator (time left). A generator has no business reporting `.backgroundSuspended` —
/// it cannot know. The app assembles the wider view-facing struct from all three.
public struct GenerationStep: Sendable, Equatable {
    /// 1-based, and reported AFTER the step completed.
    public let step: Int
    public let totalSteps: Int
    public let stage: GenerationStage
    /// The forming image: the decoded latent, at latent scale. Nil on steps that decode nothing.
    public let preview: PreviewImage?
    /// Non-nil on the plan's checkpoint cadence.
    ///
    /// Carried ON the step message rather than fetched separately, which makes "the checkpoint's
    /// step index equals the step just reported" true by construction instead of by convention.
    public let checkpoint: GenerationCheckpoint?

    public init(step: Int,
                totalSteps: Int,
                stage: GenerationStage,
                preview: PreviewImage? = nil,
                checkpoint: GenerationCheckpoint? = nil) {
        self.step = step
        self.totalSteps = totalSteps
        self.stage = stage
        self.preview = preview
        self.checkpoint = checkpoint
    }

    public var isFinalStep: Bool { step >= totalSteps }
}

/// A finished redesign.
public struct RedesignOutput: Sendable, Equatable {
    public let image: PreviewImage
    public let seed: UInt32
    public let stepsRun: Int
    /// Provenance, recorded in the variation's sidecar. Nil for a run that never paused.
    public let resumedFromStep: Int?
    public let createdAt: Date

    public init(image: PreviewImage,
                seed: UInt32,
                stepsRun: Int,
                resumedFromStep: Int?,
                createdAt: Date) {
        self.image = image
        self.seed = seed
        self.stepsRun = stepsRun
        self.resumedFromStep = resumedFromStep
        self.createdAt = createdAt
    }
}

public enum RedesignError: Error, Sendable, Equatable {
    case modelUnavailable
    case outOfMemory
    /// The user cancelled, or the engine stopped the run. Never a failure card.
    case cancelled
    /// The saved state could not be resumed. Never a failure card either — the engine restarts
    /// from step 0 with the same seed and the UI honestly shows "step 1 of 32" again.
    case checkpointRejected(GenerationCheckpoint.Rejection)
    case sourceUnreadable
    case depthUnavailable
    case failed(reason: String)

    /// What the user is told. No error codes, no "an error occurred", no blame.
    public var plainReason: String {
        switch self {
        case .modelUnavailable:
            return "The redesign model isn't ready yet."
        case .outOfMemory:
            return "This device ran out of memory partway through. A smaller photo usually works."
        case .cancelled:
            return "Cancelled."
        case .checkpointRejected:
            return "Saved progress didn't match this redesign, so it started again."
        case .sourceUnreadable:
            return "That photo couldn't be read."
        case .depthUnavailable:
            return "The depth of this space couldn't be read."
        case .failed(let reason):
            return reason
        }
    }

    /// Whether this deserves the failure card. Cancellation and a rejected checkpoint are normal
    /// events dressed as errors by the type system; showing either as a failure would tell the
    /// user something broke when nothing did.
    public var isUserFacingFailure: Bool {
        switch self {
        case .cancelled, .checkpointRejected: return false
        default: return true
        }
    }
}

/// THE SEAM. Everything in this app talks to this protocol, never to a model.
///
/// Progress is STEP-BASED — never a 0–1 float. A fraction cannot say "step 18 of 32", cannot be
/// resumed from, and invites a progress bar that moves smoothly while nothing is happening.
///
/// `Sendable` and `@Sendable` throughout because the real implementation will run its denoising
/// loop off the main actor while SwiftUI observes on it.
///
/// Why an escaping callback rather than an `AsyncStream`:
///   1. Backpressure. A stream buffering the newest value silently drops previews; an unbounded
///      one grows. The step loop must not be slowed by the consumer, and must not be decoupled
///      from it in a way that lets "step 32" arrive after the return value.
///   2. The real pipeline's shape. Core ML's `StableDiffusionPipeline` takes a synchronous
///      progress closure. Adapting that to a callback is a field rename; adapting it to a stream
///      needs a continuation anyway.
///   3. One completion signal. `async throws -> RedesignOutput` already is it. A stream would
///      need a terminal event, and error handling would live in two places.
///   4. Testability. A callback can be asserted synchronously.
public protocol RedesignGenerator: Sendable {
    /// Identifies the shape of this generator's checkpoints. A blob with a different kind is
    /// rejected before `generate` is ever called.
    var checkpointKind: String { get }

    /// False while the model is still loading or absent. The UI must be able to tell "loading"
    /// from "running" — see `prepare`.
    var isReady: Bool { get }

    /// Load the model. Separate from `generate` because model load time is invisible to a step
    /// counter: without it the UI has no way to distinguish loading from running and shows a
    /// frozen "step 0 of 32" for the whole load. Progress here IS a fraction, legitimately —
    /// it is bytes and layers, not work the user is waiting on a picture for.
    func prepare(progress: @escaping @Sendable (Double) -> Void) async throws

    /// Best-effort warm-up. Free to do nothing.
    func prewarm() async

    /// Run the redesign. `resuming` non-nil continues from `checkpoint.resumesAtStep`; the
    /// implementation must validate it against its own `checkpointKind` and throw
    /// `.checkpointRejected` rather than silently starting over — the engine needs to know.
    func generate(_ request: RedesignRequest,
                  resuming checkpoint: GenerationCheckpoint?,
                  onStep: @escaping @Sendable (GenerationStep) -> Void) async throws -> RedesignOutput

    /// Resumable state as of the last completed step — newer than the last cadence checkpoint.
    /// Called when the scene backgrounds. Returns nil before step 1, or if this generator cannot
    /// resume at all.
    func captureCheckpoint() async -> GenerationCheckpoint?

    /// Stop as soon as the current step ends.
    ///
    /// Exists ALONGSIDE task cancellation, not instead of it: a real pipeline spends its time
    /// inside `MLModel.prediction`, which is not cancellable, so only a flag read between
    /// predictions can stop it. Both doors, same result.
    func cancel()
}

public extension RedesignGenerator {
    func prepare(progress: @escaping @Sendable (Double) -> Void) async throws {}
    func prewarm() async {}
    var isReady: Bool { true }
    func captureCheckpoint() async -> GenerationCheckpoint? { nil }
}

/// THE SECOND SEAM: monocular depth estimation.
///
/// Separate from `RedesignGenerator` because it is a separate model with a separate lifecycle —
/// it runs once at import time, in a second or two, not for minutes, and it is only needed for
/// photos that arrive without camera-measured depth. Real depth from LiDAR, dual cameras or a
/// Portrait-mode HEIC's auxiliary data comes from Apple frameworks and does not pass through here.
public protocol DepthEstimator: Sendable {
    var isReady: Bool { get }
    /// Estimate depth for a flat photo. The returned signal's provenance must be `.estimated`
    /// (or `.synthetic` for a mock that is not pretending).
    func estimate(_ image: ImageHandle, writingTo destination: URL) async throws -> ControlSignal
}

public extension DepthEstimator {
    var isReady: Bool { true }
}

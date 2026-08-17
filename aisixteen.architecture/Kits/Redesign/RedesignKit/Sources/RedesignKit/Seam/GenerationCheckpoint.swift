import Foundation

/// Enough state to pick a render back up where it stopped.
///
/// `state` is OPAQUE above the generator. For a real diffusion pipeline it is the latent tensor,
/// the scheduler's internal state and the RNG counter; for the mock it is a few bytes. Nothing in
/// the engine, the queue or the UI ever looks inside it.
///
/// The split of responsibility is the whole design:
///
///   • The GENERATOR owns the meaning. Only it knows what a latent is, which scheduler wrote it,
///     and how to resume from it. Modelling that in the engine would drag Core ML into a
///     Foundation-only package and make every model swap an engine migration with a data format
///     to upgrade.
///
///   • The ENGINE owns durability, lifecycle, and exactly one decision — is this blob usable:
///         kind == generator.checkpointKind && requestDigest == request.digest && step < totalSteps
///     Anything else is discarded and the render restarts from step 0 with the same seed. A
///     generator that cannot resume at all returns nil forever, and that degradation is a tested
///     path rather than a crash.
///
/// Leaving persistence to the generator instead would mean resume-after-kill depends on a
/// generator having been alive to write it, the engine cannot enumerate resumable jobs at launch,
/// the blob's lifetime is untied from the project's (delete a project, orphan megabytes), and
/// "checkpoint written by a model version we no longer ship" has no owner.
public struct GenerationCheckpoint: Sendable, Equatable, Codable, Hashable {
    /// Who wrote it: pipeline identity plus format version. "mock.v1", "coreml.depth-sd15.v1".
    /// A generator refuses any blob whose kind is not its own — that is what makes shipping a new
    /// model safe without a migration.
    public let kind: String
    /// `RedesignRequest.digest` of the render this state belongs to.
    public let requestDigest: String
    /// The step this state is valid AS OF. The only field the engine reads for logic: resuming
    /// means the next step to run is `step + 1`.
    public let step: Int
    public let totalSteps: Int
    /// The device that produced it. A latent computed on one device's Neural Engine cannot be
    /// meaningfully continued on another — different silicon, possibly a different asset pack, and
    /// ANE numerics are not bit-reproducible across devices anyway.
    public let deviceID: String
    public let state: Data
    public let createdAt: Date

    public init(kind: String,
                requestDigest: String,
                step: Int,
                totalSteps: Int,
                deviceID: String,
                state: Data,
                createdAt: Date) {
        self.kind = kind
        self.requestDigest = requestDigest
        self.step = step
        self.totalSteps = totalSteps
        self.deviceID = deviceID
        self.state = state
        self.createdAt = createdAt
    }

    /// Why a checkpoint was refused. Distinct cases because they are genuinely different events:
    /// a stale kind means the app updated, a digest mismatch means the user edited the prompt, and
    /// a foreign device means the folder synced from somewhere it should not have.
    public enum Rejection: String, Sendable, Equatable {
        case kindMismatch
        case digestMismatch
        case foreignDevice
        case alreadyComplete
        case empty
    }

    /// The engine's one decision, as a pure function.
    ///
    /// - Returns: nil when the checkpoint is usable, otherwise why it is not.
    public func rejection(forKind expectedKind: String,
                          digest expectedDigest: String,
                          deviceID expectedDevice: String) -> Rejection? {
        if state.isEmpty { return .empty }
        if kind != expectedKind { return .kindMismatch }
        if requestDigest != expectedDigest { return .digestMismatch }
        if deviceID != expectedDevice { return .foreignDevice }
        if step >= totalSteps || step < 1 { return .alreadyComplete }
        return nil
    }

    public func isUsable(forKind expectedKind: String,
                         digest expectedDigest: String,
                         deviceID expectedDevice: String) -> Bool {
        rejection(forKind: expectedKind, digest: expectedDigest, deviceID: expectedDevice) == nil
    }

    /// The step a resumed run starts on.
    public var resumesAtStep: Int { step + 1 }
}

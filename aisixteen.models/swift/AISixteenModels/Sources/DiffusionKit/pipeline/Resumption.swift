import Foundation
import CoreML

/// Restarting a de-noising loop where it stopped.
///
/// **This file is an addition to the vendored package, not an edit of it.** Everything else needed
/// was a visibility widening — `lowerOrderStepped` and `modelOutputs` became `internal(set)`, a
/// resume point was added to `Configuration`, and the loop gained two lines. Upstream fixes can
/// still be re-applied by re-copying the originals and re-widening, which is the same discipline
/// used for `predictNoise` and `prewarmResources`.
///
/// ### What actually has to be saved
///
/// A de-noising loop looks stateless from outside and is not. Three things carry between steps:
///
/// * `latents` — the picture as it currently stands, in latent space.
/// * `modelOutputs` — DPM-Solver++ is a *multistep* method: each step is computed from the current
///   noise prediction **and the previous one**. Drop them and the resumed run silently takes a
///   different path from the same seed.
/// * `lowerOrderStepped` — how many steps have run, which is what decides whether the solver is
///   still warming up on a lower-order rule.
///
/// Everything else in the scheduler is `let`, derived from the step count. Measured at ~800 KB for a
/// 512² generation, which is why a checkpoint every few steps is affordable and a checkpoint every
/// step is not.
///
/// ### Why this is worth the care
///
/// A wrong restore does not crash. It produces a *slightly different picture from the same seed* —
/// invisible to a smoke test, and indistinguishable from the model being flaky. The gate for
/// shipping it is a split-run equality check: the same prompt and seed, run straight through and run
/// with an interruption, must produce byte-identical images.
@available(iOS 16.2, macOS 13.1, *)
public final class ResumePoint: Hashable, @unchecked Sendable {

    /// How many steps have already been taken. The loop skips exactly this many.
    public let step: Int
    public let latents: [MLShapedArray<Float32>]
    public let modelOutputs: [MLShapedArray<Float32>]
    public let lowerOrderStepped: Int

    public init(step: Int,
                latents: [MLShapedArray<Float32>],
                modelOutputs: [MLShapedArray<Float32>],
                lowerOrderStepped: Int) {
        self.step = step
        self.latents = latents
        self.modelOutputs = modelOutputs
        self.lowerOrderStepped = lowerOrderStepped
    }

    // A reference type with identity equality, because `PipelineConfiguration` is `Hashable` and
    // `MLShapedArray` is not. Hashing several hundred thousand floats to compare two configurations
    // would also be absurd.
    public static func == (lhs: ResumePoint, rhs: ResumePoint) -> Bool { lhs === rhs }
    public func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
}

/// The loop's resumable state as of the step that just finished. Handed to the progress callback so
/// a caller can write a checkpoint without reaching inside the pipeline.
@available(iOS 16.2, macOS 13.1, *)
public struct ResumeState {
    /// Steps completed, not the index of the last one — this is the number the loop skips on resume.
    public let completedSteps: Int
    public let latents: [MLShapedArray<Float32>]
    public let modelOutputs: [MLShapedArray<Float32>]
    public let lowerOrderStepped: Int

    public init(completedSteps: Int,
                latents: [MLShapedArray<Float32>],
                modelOutputs: [MLShapedArray<Float32>],
                lowerOrderStepped: Int) {
        self.completedSteps = completedSteps
        self.latents = latents
        self.modelOutputs = modelOutputs
        self.lowerOrderStepped = lowerOrderStepped
    }
}

@available(iOS 16.2, macOS 13.1, *)
extension DPMSolverMultistepScheduler {

    /// Puts back the two pieces of solver state that a fresh scheduler does not have.
    ///
    /// There is nothing else to restore: every other stored property is `let`, computed from the
    /// step count that the scheduler was constructed with.
    public func restore(modelOutputs: [MLShapedArray<Float32>], lowerOrderStepped: Int) {
        self.modelOutputs = modelOutputs
        self.lowerOrderStepped = lowerOrderStepped
    }

    /// The state a checkpoint needs, as of now.
    public func resumeState(completedSteps: Int,
                            latents: [MLShapedArray<Float32>]) -> ResumeState {
        ResumeState(completedSteps: completedSteps,
                    latents: latents,
                    modelOutputs: modelOutputs,
                    lowerOrderStepped: lowerOrderStepped)
    }
}

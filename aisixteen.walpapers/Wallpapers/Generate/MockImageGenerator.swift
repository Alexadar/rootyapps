import Foundation
import Synchronization
import GenerationKit

/// The mock that stands in for on-device diffusion until the model arrives.
///
/// It exists to make one thing judgeable now: **the wait**. On-device diffusion takes 10–30 seconds,
/// which is the single biggest risk to how this app feels, so the mock takes 10–30 seconds too. A
/// mock that returned instantly would let a waiting-state design ship untested against the only
/// condition it was drawn for.
///
/// Everything it emits has the shape the real pipeline emits: a step count, latents decoded every
/// two or three steps, and cancellation that lands between steps rather than mid-decode.
final class MockImageGenerator: ImageGenerator {

    /// How fast a run goes. The default matches real hardware; the others exist so tests and the
    /// screenshot pass do not spend half a minute per image.
    enum Speed {
        /// 10–30 s, the window the design brief describes. The exact value is rolled per run so the
        /// UI is never tuned to one convenient duration.
        case device
        /// ~1.5 s. DEBUG only, for iterating on the flow.
        case fast
        /// No waiting at all. For unit tests.
        case instant
        /// An exact per-step cost, for tests that assert on timing.
        case fixed(Duration)

        func stepDuration(totalSteps: Int) -> Duration {
            switch self {
            case .device:
                // 400–1000 ms per step over 28 steps ⇒ 11.2–28 s.
                return .milliseconds(Int.random(in: 400...1000))
            case .fast:     return .milliseconds(50)
            case .instant:  return .zero
            case .fixed(let d): return d
            }
        }
    }

    let plan: GenerationPlan
    private let speed: Speed
    /// Read between steps. See `ImageGenerator.cancel()` for why a flag exists alongside `Task`
    /// cancellation — a real pipeline sits inside a non-cancellable prediction call and this is the
    /// only thing that can stop it.
    private let cancelled = Mutex<Bool>(false)

    init(plan: GenerationPlan = .standard, speed: Speed = .device) {
        self.plan = plan
        self.speed = speed
    }

    func cancel() { cancelled.withLock { $0 = true } }

    private var isCancelled: Bool { cancelled.withLock { $0 } }

    func generate(_ request: GenerationRequest,
                  progress: @escaping @Sendable (GenerationProgress) -> Void) async throws -> GeneratedImage {
        let prompt = request.prompt
        let aspect = request.aspect
        let seed = request.seed

        cancelled.withLock { $0 = false }
        let chosenSeed = seed ?? UInt32.randomSeed()
        let schedule = GenerationSchedule(plan: plan)
        let perStep = speed.stepDuration(totalSteps: plan.totalSteps)

        // Latents are decoded at the model's internal scale, not the output scale — an eighth in
        // each dimension for a Stable-Diffusion-family VAE. Rendering previews at that size is both
        // faster and more truthful than shrinking a full-resolution frame.
        let previewSize = AspectRatio(width: max(AspectRatio.minimumEdge, aspect.width / 8),
                                      height: max(AspectRatio.minimumEdge, aspect.height / 8))

        for step in schedule.steps {
            if perStep > .zero { try await Task.sleep(for: perStep) }

            // Both doors, checked in the same place: an explicit cancel() and a cancelled Task
            // produce the same error, so callers can use either.
            if isCancelled { throw GenerationError.cancelled }
            if Task.isCancelled { throw GenerationError.cancelled }

            var preview: PreviewImage?
            if step.emitsPreview {
                let fraction = Double(step.index) / Double(plan.totalSteps)
                if let pixels = ProceduralRenderer.render(prompt: prompt,
                                                          seed: chosenSeed,
                                                          size: previewSize,
                                                          progress: fraction) {
                    preview = PreviewImage(pixels: pixels, size: previewSize)
                }
            }

            progress(GenerationProgress(step: step.index, totalSteps: plan.totalSteps, preview: preview))
        }

        // Stage 2, reported but not performed.
        //
        // The mock exists so the interface can be driven — UI tests, and the App Store screen
        // recordings — without a 1.1 GB model. That only works if it *reports* the same shape of job
        // the real generator does. Skipping the enlargement stage left the progress bar at 82 % for
        // the whole of the mock's finish, which is a bug the recording would have shipped.
        if request.upscale {
            let tiles = Upscaler.grid(width: aspect.width, height: aspect.height).count
            for tile in 1...max(tiles, 1) {
                if isCancelled || Task.isCancelled { throw GenerationError.cancelled }
                // No pacing of its own: whatever the run's per-step cost is, an enlargement tile
                // takes a fraction of it. `instant` stays instant, which is what the unit tests need.
                if case .instant = speed {} else { try? await Task.sleep(for: .milliseconds(90)) }
                progress(GenerationProgress(step: tile, totalSteps: max(tiles, 1),
                                            preview: nil, stage: .enlarging))
            }
        }

        // One last check before the expensive full-resolution render, so a cancel on the final step
        // does not still cost the user a full decode.
        if isCancelled || Task.isCancelled { throw GenerationError.cancelled }

        guard let pixels = ProceduralRenderer.render(prompt: prompt,
                                                     seed: chosenSeed,
                                                     size: aspect,
                                                     progress: 1) else {
            throw GenerationError.failed(reason: "The image couldn't be assembled at that size.")
        }

        return GeneratedImage(pixels: pixels,
                              size: aspect,
                              prompt: prompt,
                              seed: chosenSeed,
                              createdAt: Date())
    }
}

/// Fails part-way through, so the failure card is built against a real mid-generation failure.
///
/// Failing immediately would be the easy mock and the useless one: the interesting case is a job
/// that has already morphed into a picture frame and has to unwind from there — which is exactly the
/// transition the bundle specifies ("the capsule stops widening, drains its tint, and morphs into
/// the card") and exactly the one that never gets exercised by a generator that fails at step zero.
final class FailingImageGenerator: ImageGenerator {

    let plan: GenerationPlan
    private let failAtStep: Int
    private let error: GenerationError
    private let speed: MockImageGenerator.Speed
    private let cancelled = Mutex<Bool>(false)

    init(plan: GenerationPlan = .standard,
         failAtStep: Int = 11,
         error: GenerationError = .outOfMemory,
         speed: MockImageGenerator.Speed = .device) {
        self.plan = plan
        self.failAtStep = failAtStep
        self.error = error
        self.speed = speed
    }

    func cancel() { cancelled.withLock { $0 = true } }

    func generate(_ request: GenerationRequest,
                  progress: @escaping @Sendable (GenerationProgress) -> Void) async throws -> GeneratedImage {
        let prompt = request.prompt
        let aspect = request.aspect
        let seed = request.seed

        cancelled.withLock { $0 = false }
        let chosenSeed = seed ?? UInt32.randomSeed()
        let schedule = GenerationSchedule(plan: plan)
        let perStep = speed.stepDuration(totalSteps: plan.totalSteps)
        let previewSize = AspectRatio(width: max(AspectRatio.minimumEdge, aspect.width / 8),
                                      height: max(AspectRatio.minimumEdge, aspect.height / 8))

        for step in schedule.steps {
            if perStep > .zero { try await Task.sleep(for: perStep) }
            if cancelled.withLock({ $0 }) || Task.isCancelled { throw GenerationError.cancelled }
            // Cancellation wins over the scheduled failure: a user who stopped it was not shown an
            // error, and must not be.
            if step.index >= failAtStep { throw error }

            var preview: PreviewImage?
            if step.emitsPreview {
                let fraction = Double(step.index) / Double(plan.totalSteps)
                if let pixels = ProceduralRenderer.render(prompt: prompt, seed: chosenSeed,
                                                          size: previewSize, progress: fraction) {
                    preview = PreviewImage(pixels: pixels, size: previewSize)
                }
            }
            progress(GenerationProgress(step: step.index, totalSteps: plan.totalSteps, preview: preview))
        }

        throw error
    }
}

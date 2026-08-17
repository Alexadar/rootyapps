import Foundation
import CoreGraphics

/// A boolean behind a lock.
///
/// `Synchronization.Mutex` would be tidier but is macOS 15 / iOS 18, and this package deliberately
/// supports further back so it can be linked from anywhere. `NSLock` is Foundation and enough for
/// one flag read between steps.
final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isSet: Bool {
        lock.lock(); defer { lock.unlock() }
        return value
    }

    func set() {
        lock.lock(); defer { lock.unlock() }
        value = true
    }

    func reset() {
        lock.lock(); defer { lock.unlock() }
        value = false
    }
}

/// Waits out a step, translating the one error `Task.sleep` can throw.
///
/// ⚠️ Without this, the two cancellation doors produce **different** errors: an explicit `cancel()`
/// lands on the flag check and throws `EnhanceError.cancelled`, while `Task.cancel()` almost always
/// lands inside the sleep and throws `CancellationError` straight past it. Callers matching on
/// `EnhanceError` then treat a perfectly ordinary cancel as an unknown failure and show the failure
/// card to a user who pressed Stop.
func sleepBetweenSteps(_ duration: Duration) async throws {
    guard duration > .zero else { return }
    do {
        try await Task.sleep(for: duration)
    } catch {
        // `Task.sleep` throws for exactly one reason.
        throw EnhanceError.cancelled
    }
}

/// The mock that stands in for on-device diffusion until the model arrives.
///
/// It exists to make one thing judgeable now: **the wait**. A pass takes tens of seconds, which is
/// the single biggest risk to how this app feels, so the mock takes tens of seconds too. Everything
/// it emits has the shape the real pipeline emits — a step count, a preview decoded every two
/// steps, and cancellation that lands between steps rather than mid-decode.
public final class MockPhotoEnhancer: PhotoEnhancer {

    public let plan: EnhancePlan
    private let speed: EnhanceSpeed
    private let cancelled = CancelFlag()

    /// Previews are rendered at an eighth in each dimension. That is not only cheaper — it is
    /// truthful: a diffusion model decodes latents at its internal scale, so a preview genuinely is
    /// a small image being upscaled for display, not a shrunk full-resolution frame.
    static let previewScale = 1.0 / 8.0

    public init(plan: EnhancePlan = .standard, speed: EnhanceSpeed = .device) {
        self.plan = plan
        self.speed = speed
    }

    public func cancel() { cancelled.set() }

    public func enhance(photo: CGImage,
                        strength: Double,
                        mask: CGImage?,
                        seed: UInt32?,
                        progress: @escaping (EnhanceProgress) -> Void) async throws -> EnhancedPhoto {
        cancelled.reset()
        let chosenSeed = seed ?? UInt32.randomSeed()

        guard let full = PixelImage(photo) else { throw EnhanceError.unsupportedImage }
        // `nil` only if the photo is smaller than 8 px on a side, which no camera produces; falling
        // back to the full image keeps a pathological input working rather than failing the pass.
        let preview = PixelImage(photo, scaledTo: Self.previewScale) ?? full

        let schedule = EnhanceSchedule(plan: plan)
        let perStep = speed.stepDuration()

        for step in schedule.steps {
            try await sleepBetweenSteps(perStep)

            // Both doors, checked in the same place, so a caller can use either.
            if cancelled.isSet || Task.isCancelled { throw EnhanceError.cancelled }

            var intermediate: CGImage?
            if step.emitsPreview {
                let fraction = Double(step.index) / Double(plan.totalSteps)
                intermediate = ProceduralEnhancement
                    .render(preview, strength: strength, progress: fraction)
                    .cgImage()
            }
            progress(EnhanceProgress(step: step.index,
                                     totalSteps: plan.totalSteps,
                                     intermediate: intermediate))
        }

        // One last check before the expensive full-resolution render, so cancelling on the final
        // step does not still cost the user a full pass over every pixel.
        if cancelled.isSet || Task.isCancelled { throw EnhanceError.cancelled }

        guard let image = ProceduralEnhancement
            .render(full, strength: strength, progress: 1)
            .cgImage() else {
            throw EnhanceError.failed(reason: "The enhanced copy couldn't be assembled.")
        }

        return EnhancedPhoto(image: image,
                             renderedStrength: strength,
                             seed: chosenSeed,
                             steps: plan.totalSteps)
    }
}

/// Fails part-way through, so the failure card is built against a real mid-pass failure.
///
/// Failing immediately would be the easy mock and the useless one. The interesting case is a pass
/// that has already put a resolving picture on screen and has to unwind from there — the capsule
/// stopping, draining its tint and becoming the card — which a generator that fails at step zero
/// never exercises. Both shapes are reachable: `failAtStep: 2` fails before the first preview,
/// `failAtStep: 11` fails after the picture is already forming.
public final class FailingPhotoEnhancer: PhotoEnhancer {

    public let plan: EnhancePlan
    private let failAtStep: Int
    private let error: EnhanceError
    private let speed: EnhanceSpeed
    private let cancelled = CancelFlag()

    public init(plan: EnhancePlan = .standard,
                failAtStep: Int = 11,
                error: EnhanceError = .outOfMemory,
                speed: EnhanceSpeed = .device) {
        self.plan = plan
        self.failAtStep = failAtStep
        self.error = error
        self.speed = speed
    }

    public func cancel() { cancelled.set() }

    public func enhance(photo: CGImage,
                        strength: Double,
                        mask: CGImage?,
                        seed: UInt32?,
                        progress: @escaping (EnhanceProgress) -> Void) async throws -> EnhancedPhoto {
        cancelled.reset()
        guard let preview = PixelImage(photo, scaledTo: MockPhotoEnhancer.previewScale)
                ?? PixelImage(photo) else { throw EnhanceError.unsupportedImage }

        let schedule = EnhanceSchedule(plan: plan)
        let perStep = speed.stepDuration()

        for step in schedule.steps {
            try await sleepBetweenSteps(perStep)

            // ⚠️ Cancellation wins over the scheduled failure. A user who stopped the pass was not
            // shown an error and must not be — even if the run was going to fail anyway.
            if cancelled.isSet || Task.isCancelled { throw EnhanceError.cancelled }
            if step.index >= failAtStep { throw error }

            var intermediate: CGImage?
            if step.emitsPreview {
                let fraction = Double(step.index) / Double(plan.totalSteps)
                intermediate = ProceduralEnhancement
                    .render(preview, strength: strength, progress: fraction)
                    .cgImage()
            }
            progress(EnhanceProgress(step: step.index,
                                     totalSteps: plan.totalSteps,
                                     intermediate: intermediate))
        }

        throw error
    }
}

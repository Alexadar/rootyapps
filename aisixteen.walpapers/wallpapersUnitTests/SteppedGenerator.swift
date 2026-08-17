import Foundation
import Synchronization
import GenerationKit

/// A generator the test drives one step at a time.
///
/// Cancellation is the axis most likely to be quietly broken, and "cancel at step 17" is not
/// something a timing-based mock can express without becoming flaky. This one advances only when the
/// test says so, which makes every step of the run a place a test can stand.
final class SteppedGenerator: ImageGenerator {

    private let plan: GenerationPlan
    private let ticks: AsyncStream<Void>
    private let tick: AsyncStream<Void>.Continuation
    private let cancelled = Mutex<Bool>(false)
    private let reachedStep = Mutex<Int>(0)

    init(plan: GenerationPlan = .standard) {
        self.plan = plan
        (ticks, tick) = AsyncStream.makeStream()
    }

    /// Lets the run proceed by one step.
    func advance() { tick.yield() }

    /// How many steps the generator has actually emitted. Used to assert that a cancel stopped it.
    var stepsEmitted: Int { reachedStep.withLock { $0 } }

    func cancel() { cancelled.withLock { $0 = true } }

    func generate(_ request: GenerationRequest,
                  progress: @escaping @Sendable (GenerationProgress) -> Void) async throws -> GeneratedImage {
        let prompt = request.prompt, aspect = request.aspect, seed = request.seed

        var iterator = ticks.makeAsyncIterator()
        let chosenSeed = seed ?? 0xABCDEF
        let schedule = GenerationSchedule(plan: plan)
        // One tiny pixel buffer, reused: these tests are about the state machine, not the picture.
        let previewSize = AspectRatio(width: 256, height: 256)
        let previewPixels = Data(repeating: 0x80, count: previewSize.pixelCount * 4)

        for step in schedule.steps {
            await iterator.next()
            if cancelled.withLock({ $0 }) || Task.isCancelled { throw GenerationError.cancelled }
            reachedStep.withLock { $0 = step.index }
            progress(GenerationProgress(
                step: step.index,
                totalSteps: plan.totalSteps,
                preview: step.emitsPreview ? PreviewImage(pixels: previewPixels, size: previewSize) : nil))
        }

        if cancelled.withLock({ $0 }) || Task.isCancelled { throw GenerationError.cancelled }

        // One more tick before the picture exists.
        //
        // Without it, "the last step" is not a place a test can stand: the twenty-eighth `advance()`
        // both emits step 28 *and* completes the run, so whether a subsequent `cancel()` sees
        // `.running(28, 28)` or `.done` depends on how long a 12 MB image decode takes against a
        // fixed number of yields. That is a race, and it failed intermittently for exactly that
        // reason. Holding here makes the final step observable and the cancel deterministic.
        await iterator.next()
        if cancelled.withLock({ $0 }) || Task.isCancelled { throw GenerationError.cancelled }

        return GeneratedImage(pixels: Data(repeating: 0xFF, count: aspect.pixelCount * 4),
                              size: aspect,
                              prompt: prompt,
                              seed: chosenSeed,
                              createdAt: Date(timeIntervalSince1970: 1_786_000_000))
    }
}

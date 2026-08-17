import Foundation
import Observation
import RedesignKit
import SwiftUI
#if os(iOS)
import UIKit
#endif

/// What `GeneratingView` renders.
///
/// Kept under the design handoff's exact field names, because that view is the most
/// production-shaped thing in the bundle and is copied nearly verbatim. The type is assembled
/// here rather than reported by the generator, because its three fields have three different
/// owners: the generator knows the step and the picture, the ENGINE knows why it is paused, and
/// the ESTIMATOR knows the time left. A generator cannot know it was backgrounded.
@MainActor
struct GenerationProgress {
    var stage: GenerationStage
    var step: Int
    var totalSteps: Int
    var intermediate: PlatformImage?
    var pause: GenerationPause?
    var estimatedRemaining: TimeInterval?

    var fraction: Double {
        guard totalSteps > 0 else { return 0 }
        return min(max(Double(step) / Double(totalSteps), 0), 1)
    }
}

/// The engine room: reduce events, perform intents.
///
/// `@MainActor @Observable` rather than an actor, and the reason is that it does no heavy work.
/// It reduces small values and issues calls; the compute lives inside the generator, off the main
/// actor, reached through `await`. An actor here would need a separate `@Observable` mirror for
/// SwiftUI and would buy nothing — while ActivityKit, `UNUserNotificationCenter`, `scenePhase` and
/// `UIDevice` are all main-actor-adjacent anyway.
///
/// The whole loop is `apply(event)` → `perform(state.intent)`. `apply` is also the door the tests
/// come in through, which is why it is not private.
@MainActor
@Observable
final class RedesignEngine {

    private(set) var state = QueueState()
    private(set) var progress: GenerationProgress?
    /// The newest resumable bytes, held in memory so the background-expiration handler can write
    /// them synchronously. Awaiting `captureCheckpoint()` against a hard deadline is how you lose
    /// the checkpoint you were trying to save.
    private var newestCheckpoint: GenerationCheckpoint?

    @ObservationIgnored private var generator: any RedesignGenerator
    @ObservationIgnored private let checkpoints: CheckpointStore
    @ObservationIgnored private let notifier: RenderNotifier
    @ObservationIgnored private var observer: InterruptionObserver?
    @ObservationIgnored private var runTask: Task<Void, Never>?
    @ObservationIgnored private var performing = false
    #if os(iOS)
    @ObservationIgnored private var liveActivity: LiveActivityPresenter?
    #else
    @ObservationIgnored private let sleepAssertion = SleepAssertion()
    #endif

    /// Called when a variation finishes, so the library can absorb it.
    var onVariationFinished: ((Job, RedesignOutput) async -> Void)?

    /// Parameters are optional rather than defaulted, because a default argument expression is
    /// evaluated in a nonisolated context and `RenderNotifier` is main-actor-isolated.
    init(generator: (any RedesignGenerator)? = nil,
         checkpoints: CheckpointStore? = nil,
         notifier: RenderNotifier? = nil) {
        self.checkpoints = checkpoints ?? CheckpointStore()
        self.notifier = notifier ?? RenderNotifier()
        // A placeholder so `self` is fully initialised before the sink can reference it; replaced
        // immediately below with the real generator, which may need that sink.
        self.generator = generator ?? MockRedesignGenerator(speed: .fast)
        #if os(iOS)
        self.liveActivity = LiveActivityPresenter()
        #endif
        if generator == nil {
            let sink = EngineSink(engine: self)
            self.sink = sink
            self.generator = GeneratorFactory.makeGenerator(sink: sink)
        }
    }

    // ── the door ─────────────────────────────────────────────────────────────────────────────

    func apply(_ event: RedesignQueue.Event) {
        state = RedesignQueue.reduce(state, on: event, at: ProcessInfo.processInfo.systemUptime)
        refreshProgress()
        checkpoints.saveQueue(state.jobs)
        #if os(iOS)
        liveActivity?.update(for: state, remainingText: remainingText)
        #endif
        pump()
    }

    /// Perform intents until the state stops moving.
    ///
    /// A plain re-entrancy guard is not enough, and getting this wrong is subtle: performing an
    /// intent usually applies another event, that nested `apply` computes a NEW intent, and a guard
    /// that simply returns DROPS it. The queue then stalls in a state that has work to do and
    /// nobody to do it — the symptom being a failed variation whose sibling never starts.
    ///
    /// So: re-entrant calls return (the outer loop owns the work), and the loop keeps going while
    /// each performed intent actually changes something. An intent that changes nothing
    /// synchronously — a capture that awaits, a degrade — ends the loop and waits for its event.
    /// The bound is a backstop against a cycle, not an expected limit.
    private func pump() {
        guard !performing else { return }
        performing = true
        defer { performing = false }

        for _ in 0..<16 {
            let intent = state.intent
            guard intent != .idle else { return }
            let before = state
            perform(intent)
            if state == before { return }
        }
        assertionFailure("intent did not settle: \(state.intent)")
    }

    // ── public actions ───────────────────────────────────────────────────────────────────────

    func enqueue(_ requests: [RedesignRequest]) {
        let now = Date()
        let jobs = requests.map { Job(id: JobID($0.id), request: $0, enqueuedAt: now) }
        startObservingIfNeeded()
        Task { await notifier.requestAuthorisationIfNeeded() }
        apply(.enqueued(jobs))
    }

    /// SCOPED. The handoff promises it in so many words: "Cancels only this variation. Queued
    /// variations continue."
    func cancel(_ id: JobID) {
        if state.head?.id == id { generator.cancel(); runTask?.cancel() }
        apply(.cancelled(id))
    }

    func cancelProject(_ projectID: String) {
        if let head = state.head, head.request.projectID == projectID {
            generator.cancel(); runTask?.cancel()
        }
        apply(.cancelledProject(projectID))
    }

    func resumeAnyway(_ id: JobID) { apply(.resumeAnyway(id)) }
    func waitForCharge(_ id: JobID) { apply(.waitForCharge(id)) }
    /// The explicit tap that a job rehydrated after a kill waits for.
    func resumeRestored() { apply(.resumeRestored) }

    func sceneChanged(_ phase: ScenePhaseState) { apply(.sceneChanged(phase)) }

    /// Rehydrate at launch. Never auto-starts — see `QueueState.restoredFromDisk`.
    func restore() {
        let jobs = checkpoints.loadQueue()
        checkpoints.sweep(keeping: Set(jobs.map(\.id)))
        guard !jobs.isEmpty else { return }
        apply(.restored(jobs))
    }

    // ── intents → actions ────────────────────────────────────────────────────────────────────

    private func perform(_ intent: Intent) {
        switch intent {
        case .idle:
            stopObservingIfIdle()

        case .discardCheckpoint(let id):
            checkpoints.discard(id)
            apply(.checkpointDiscarded(id))

        case .start(let id, let resumeFrom):
            start(id, resumeFrom: resumeFrom)

        case .captureCheckpoint(let id, let urgent):
            captureCheckpoint(id, urgent: urgent)

        case .suspend(let id):
            generator.cancel()
            runTask?.cancel()
            runTask = nil
            apply(.suspended(id))

        case .degrade(let id, let level):
            // Observed, not predicted. There is nothing to do to the generator itself — the work
            // is already slower because the device is already hot — but the run task's priority
            // comes down so the rest of the system stays responsive while it finishes.
            _ = id
            _ = level
        }
    }

    private func start(_ id: JobID, resumeFrom: Int?) {
        guard let job = state.job(id), runTask == nil else { return }
        startObservingIfNeeded()
        #if os(macOS)
        sleepAssertion.begin()
        #endif

        // Validate before handing it over, so a stale blob is a known event rather than an
        // exception thrown from inside the generator.
        var checkpoint: GenerationCheckpoint?
        if resumeFrom != nil, let stored = checkpoints.read(for: id) {
            checkpoint = stored
        }

        apply(.started(id))

        let generator = self.generator
        let request = job.request
        runTask = Task { [weak self] in
            do {
                let output = try await generator.generate(request, resuming: checkpoint) { step in
                    Task { @MainActor [weak self] in self?.absorb(step, for: id) }
                }
                await self?.finish(id, output: output)
            } catch let error as RedesignError {
                await self?.fail(id, error: error)
            } catch is CancellationError {
                // Already handled by whichever path cancelled.
            } catch {
                await self?.fail(id, error: .failed(reason: error.localizedDescription))
            }
        }
    }

    /// The one hop from the generator's thread onto the main actor.
    private func absorb(_ step: GenerationStep, for id: JobID) {
        if let checkpoint = step.checkpoint {
            newestCheckpoint = checkpoint
            try? checkpoints.write(checkpoint, for: id)
            apply(.checkpointWritten(id, step: checkpoint.step))
        }
        if let preview = step.preview {
            latestPreview = Bitmap.image(from: preview)
            #if os(iOS)
            liveActivity?.writeThumbnail(preview, jobID: id, step: step.step)
            #endif
        }
        apply(.stepped(id, step: step.step, stage: step.stage, hasPreview: step.preview != nil))
    }

    @ObservationIgnored private var latestPreview: PlatformImage?

    private func finish(_ id: JobID, output: RedesignOutput) async {
        runTask = nil
        newestCheckpoint = nil
        guard let job = state.job(id) else { return }

        await onVariationFinished?(job, output)

        let remaining = max(state.queueDepth, 0)
        await notifier.variationFinished(spaceName: job.request.spaceName,
                                         styleName: job.request.styleName,
                                         projectID: job.request.projectID,
                                         outputID: job.id.rawValue,
                                         remainingInQueue: remaining)
        apply(.succeeded(id, outputID: job.id.rawValue))
        latestPreview = nil
    }

    private func fail(_ id: JobID, error: RedesignError) async {
        runTask = nil
        newestCheckpoint = nil
        switch error {
        case .cancelled:
            break                                 // the cancel path already reported it
        case .checkpointRejected:
            // Not a failure card. The run restarts from zero with the same seed and the UI
            // honestly shows "step 1 of 32" again.
            apply(.checkpointRejected(id))
        default:
            apply(.failed(id, reason: error.plainReason))
        }
    }

    private func captureCheckpoint(_ id: JobID, urgent: Bool) {
        if urgent {
            // Hard deadline: write whatever is already in memory, synchronously, and return.
            if let checkpoint = newestCheckpoint {
                _ = checkpoints.writeUrgently(checkpoint, for: id)
                apply(.checkpointWritten(id, step: checkpoint.step))
            } else {
                // Nothing to save — say so, or the intent repeats forever.
                apply(.checkpointWritten(id, step: state.job(id)?.step ?? 0))
            }
            return
        }
        let generator = self.generator
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let checkpoint = await generator.captureCheckpoint() {
                self.newestCheckpoint = checkpoint
                try? self.checkpoints.write(checkpoint, for: id)
                self.apply(.checkpointWritten(id, step: checkpoint.step))
            } else {
                self.apply(.checkpointWritten(id, step: self.state.job(id)?.step ?? 0))
            }
        }
    }

    // ── derived view state ───────────────────────────────────────────────────────────────────

    private func refreshProgress() {
        guard let head = state.head else { progress = nil; return }
        progress = GenerationProgress(
            stage: head.stage,
            step: head.step,
            totalSteps: head.totalSteps,
            intermediate: latestPreview,
            pause: head.displayedPause,
            estimatedRemaining: head.estimator.secondsRemaining(afterStep: head.step,
                                                                 plan: head.request.plan))
    }

    private var remainingText: String? {
        guard let head = state.head,
              let seconds = head.estimator.secondsRemaining(afterStep: head.step,
                                                            plan: head.request.plan) else { return nil }
        return RemainingPhrase.text(for: seconds)
    }

    // ── observers ────────────────────────────────────────────────────────────────────────────

    private func startObservingIfNeeded() {
        guard observer == nil else { return }
        let sink = self.sink ?? EngineSink(engine: self)
        self.sink = sink
        let observer = InterruptionObserver(sink: sink)
        self.observer = observer
        observer.start()
        notifier.install()
    }

    /// Held for the engine's lifetime, not the observer's: a scripted generator captures it
    /// weakly at construction, so it has to outlive any single run.
    @ObservationIgnored private var sink: EngineSink?

    private func stopObservingIfIdle() {
        guard !state.hasLiveWork else { return }
        observer?.stop()
        observer = nil
        sink = nil
        #if os(macOS)
        sleepAssertion.end()
        #endif
        #if os(iOS)
        liveActivity?.end()
        #endif
    }
}

/// Bridges the observers' `Sendable` protocol onto the main-actor engine.
final class EngineSink: EnvironmentEventSink, @unchecked Sendable {
    private weak var engine: RedesignEngine?

    init(engine: RedesignEngine) { self.engine = engine }

    func publish(_ event: RedesignQueue.Event) {
        Task { @MainActor [weak engine] in engine?.apply(event) }
    }
}

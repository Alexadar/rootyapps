import Foundation
import Observation

/// The single owner of long-running model work.
///
/// ### Why one owner
///
/// Three separate guards accumulated while this app was being debugged — a lock inside the
/// generator, a cancel flag passed into the refiner, and a join on the speculative preload — and all
/// three were patching the same fact: **model work must be serial, because the models do not fit
/// twice.** Two resident pipelines is what crashed Enhance and what rebooted the test phone. A
/// second Create started during an Enhance would do it again.
///
/// So there is one place that says what is running, and everything asks it. "No Create while
/// enhancing" then falls out of the design instead of being a special case somebody has to remember.
///
/// ### Why main-actor-isolated and not an `actor`
///
/// The interface has to read this synchronously — `canStart` decides whether a button is enabled
/// during a view update, and an `actor` can only be reached with `await`. A main-actor class gives
/// the same single-owner guarantee: only one place mutates `current`, and it does so on one thread.
/// The expensive work still runs off the main actor, inside the detached task this hands out.
@MainActor
@Observable
public final class JobRunner {

    /// What kind of work is running. The kinds matter because they need different models resident:
    /// generating wants unet, text encoder and decoder; enhancing additionally wants ControlNet and
    /// the VAE encoder, and cannot afford the generator's copy at the same time.
    public enum Work: Equatable {
        case generate
        case enhance
        /// The one-time Neural Engine compile. Background work by definition — it holds the runner
        /// so nothing else loads a model beside it, and stands down the moment anything does.
        case tune
    }

    public private(set) var current: Work?

    public var isIdle: Bool { current == nil }

    /// Whether `work` may start now. False while anything else is running — deliberately including
    /// work of the same kind, since a second generation would load a second pipeline.
    public func canStart(_ work: Work) -> Bool { current == nil }

    /// Fires on the main actor once `current` has cleared. How a start queued during tuning learns
    /// the tuner is done, without anything polling for it.
    public var didFinish: (@MainActor (Work) -> Void)?

    private let releaseModels: @Sendable () -> Void
    private let cancelWork: @Sendable () -> Void
    private var task: Task<Void, Never>?
    private var token = CancelFlag()

    /// - Parameter releaseModels: called before every `.enhance`, to let go of whatever the previous
    ///   kind of work left resident. Closures rather than a generator, because the runner has no
    ///   business knowing what a generator is — it owns *when* model work happens, not what it is.
    /// - Parameter cancelWork: reaches whatever is running. Long synchronous Core ML calls never
    ///   hit a suspension point, so `Task.cancel()` alone is not enough.
    public init(releaseModels: @escaping @Sendable () -> Void = {},
                cancelWork: @escaping @Sendable () -> Void = {}) {
        self.releaseModels = releaseModels
        self.cancelWork = cancelWork
    }

    /// Starts `body` off the main actor and holds the runner until it finishes.
    ///
    /// Returns `false` — and starts nothing — if the runner is busy. Callers treat that as "the
    /// button should not have been enabled", not as an error to show.
    ///
    /// `body` is handed a flag rather than relying on `Task.isCancelled`, because the work it drives
    /// is long synchronous Core ML calls that never reach a suspension point; the pipeline's own
    /// per-step callback is the only place a stop can be honoured.
    @discardableResult
    public func start(_ work: Work, _ body: @escaping @Sendable (CancelFlag) async -> Void) -> Bool {
        guard current == nil else { return false }

        // Residency, in one place. The refiner loads its own pipeline including a ControlNet, and
        // holding the generator's at the same time is the allocation that crashed Enhance. The
        // reverse is handled by the refiner itself, which unloads on the way out.
        if work == .enhance { releaseModels() }

        current = work
        token = CancelFlag()
        let flag = token

        // Detached, not `Task {}`. This class is main-actor-isolated, so an inheriting task would
        // run the body on the main actor — and the body's inner work is long *synchronous* Core ML
        // calls. Ninety seconds of refinement on the main actor is a frozen interface.
        task = Task.detached(priority: .userInitiated) { [weak self] in
            await body(flag)
            await MainActor.run {
                self?.current = nil
                self?.task = nil
                self?.didFinish?(work)
            }
        }
        return true
    }

    /// Stops whatever is running. Sets the flag *and* cancels the task: the flag is what a
    /// synchronous Core ML loop can see, the cancellation is what an `await` between stages sees.
    public func cancel() {
        token.set()
        cancelWork()
        task?.cancel()
    }
}

/// A cancel flag that can cross into a detached task.
///
/// `Mutex` is non-copyable, so it cannot be captured by a closure that outlives the caller — which
/// is exactly what a long refinement running off the main actor needs. A small reference type does
/// the same job and can be shared.
///
/// It exists at all because the work being cancelled is long **synchronous** Core ML calls that
/// never reach a suspension point: `Task.isCancelled` is never consulted, so the loop has to be
/// handed something it can read between steps.
public final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false

    public init() {}

    public var isSet: Bool { lock.withLock { flag } }
    public func set() { lock.withLock { flag = true } }
    public func reset() { lock.withLock { flag = false } }
}

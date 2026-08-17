import Foundation

/// What the engine should be doing right now, given the state.
///
/// This is the pure bridge to side effects, and it is the single most load-bearing decision in the
/// design. Because `Intent` is DERIVED from `QueueState` and never stored, the question "does a
/// phone call actually stop the generator?" becomes an assertion about a value — provable with no
/// generator, no clock, no simulator and no device.
///
/// The engine's whole loop is: `apply(event)` → `perform(state.intent)`.
public enum Intent: Equatable, Sendable {
    case idle
    /// Run the generator. `resumeFrom` nil means a fresh run from step 0.
    case start(JobID, resumeFrom: Int?)
    /// Ask the generator for its newest resumable state and write it durably.
    /// `urgent` means the app is inside a closing background window: no awaiting, write the
    /// cached bytes synchronously and return.
    case captureCheckpoint(JobID, urgent: Bool)
    /// Stop the generator, keep the checkpoint.
    case suspend(JobID)
    /// Delete a job's checkpoint files.
    case discardCheckpoint(JobID)
    /// Keep running, but at lower QoS. Thermal throttling is observed, never predicted — the
    /// device is already hot, and the honest response is to slow down rather than to stop.
    case degrade(JobID, ThermalLevel)
}

public extension QueueState {

    /// Whether a given cause actually halts work, as opposed to merely slowing it.
    ///
    /// Thermal is the only conditional one, and it matters: the handoff's copy for a warm phone
    /// says "Running slower to keep the phone cool … still progressing". If elevated thermal
    /// stopped the render, that sentence would be false while the user was reading it. Only
    /// `.critical` — where continuing risks a system-level shutdown — actually halts.
    func halts(_ pause: GenerationPause) -> Bool {
        switch pause {
        case .thermal: return thermal == .critical
        case .phoneCall, .lowBattery, .backgroundSuspended: return true
        }
    }

    /// The head's halting causes, if any.
    var haltingPauses: Set<GenerationPause> {
        guard let head else { return [] }
        return head.pauses.filter { halts($0) }
    }

    var isHeadHalted: Bool { !haltingPauses.isEmpty }

    var intent: Intent {
        // Cheap and unblocking: a stale checkpoint on disk costs megabytes and, worse, is a blob
        // that a later launch could try to resume. Clear it before anything else.
        if let discard = pendingCheckpointDiscards.first {
            return .discardCheckpoint(discard)
        }

        guard let head else { return .idle }

        if isHeadHalted {
            // Save first, stop second. The order is the whole point: stopping a generator that
            // still holds unsaved state throws away everything since the last cadence checkpoint.
            if head.generatorRunning && head.hasUnsavedProgress {
                return .captureCheckpoint(head.id, urgent: scene != .active)
            }
            if head.generatorRunning {
                return .suspend(head.id)
            }
            return .idle
        }

        if !head.generatorRunning {
            // A job rehydrated from disk waits for a tap. See QueueState.restoredFromDisk.
            guard !restoredFromDisk else { return .idle }
            // Nothing can start while the app is not on screen: this build claims no background
            // execution mode, so "start" here would be a promise the platform will not keep.
            guard scene == .active else { return .idle }
            return .start(head.id, resumeFrom: head.checkpointStep)
        }

        if thermal >= .elevated {
            return .degrade(head.id, thermal)
        }

        return .idle
    }
}

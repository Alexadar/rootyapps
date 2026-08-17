import Foundation

/// The job queue, as a pure transition function.
///
/// The shape is the house answer to "a state machine wrapped around a framework you cannot test":
/// keep the transition pure, feed it small events, and let the untestable part be a thin layer
/// that translates notifications into events and intents into calls. The wallpaper app's
/// `ModelGate.reduce(_:on:wifiOnly:)` is the same pattern for Background Assets.
///
/// Two rules make it work:
///
///   • **No pixels in `Event`.** A step carries `hasPreview: Bool`, not a `PreviewImage`. That
///     keeps `Event` `Equatable`, keeps this file free of image handling, and is what lets the
///     whole state space run in milliseconds. Actual pixels are routed by the engine, outside.
///
///   • **`uptime` is monotonic**, never `Date`. A wall clock that jumps — a timezone change, an
///     NTP correction, the user setting the clock — corrupts the estimate mid-render. `Date`
///     appears on `Job` for display only.
public enum RedesignQueue {

    public enum Event: Equatable, Sendable {
        // ── the queue ────────────────────────────────────────────────────────────────────────
        /// One project's N variations, in order.
        case enqueued([Job])
        /// SCOPED. Cancels one variation; the queue survives. The handoff promises this in so many
        /// words: "Cancels only this variation. Queued variations continue."
        case cancelled(JobID)
        case cancelledProject(String)
        /// Rehydrated at launch after the app was killed.
        case restored([Job])
        /// The user explicitly asked a restored job to continue.
        case resumeRestored

        // ── the running job ──────────────────────────────────────────────────────────────────
        case started(JobID)
        case stepped(JobID, step: Int, stage: GenerationStage, hasPreview: Bool)
        case checkpointWritten(JobID, step: Int)
        case checkpointRejected(JobID)
        case checkpointDiscarded(JobID)
        /// The generator stopped without finishing, and without failing.
        case suspended(JobID)
        case succeeded(JobID, outputID: String)
        case failed(JobID, reason: String)

        // ── the environment ──────────────────────────────────────────────────────────────────
        case thermalChanged(ThermalLevel)
        case callChanged(active: Bool)
        case powerChanged(BatterySnapshot)
        case sceneChanged(ScenePhaseState)

        // ── the user ─────────────────────────────────────────────────────────────────────────
        case resumeAnyway(JobID)
        case waitForCharge(JobID)
    }

    /// The pure transition. No framework, no clock, no I/O.
    public static func reduce(_ state: QueueState,
                              on event: Event,
                              at uptime: TimeInterval) -> QueueState {
        var next = state

        switch event {

        case .enqueued(let jobs):
            // Appending, not replacing: starting a second project while a first is still rendering
            // must not discard the first.
            next.jobs.append(contentsOf: jobs)
            // New work means the user is here and asking for it, so a restored-from-disk latch no
            // longer applies.
            next.restoredFromDisk = false

        case .restored(let jobs):
            // Normalise what came off disk. Two things are always wrong in a rehydrated job and
            // both are silent if left alone:
            //
            //   • `generatorRunning` was true when the process died. Nothing is running now.
            //   • `step` may be past `checkpointStep`. Steps completed after the last durable
            //     checkpoint did not survive the kill, and leaving the counter where it was would
            //     show the user a step number the render is about to walk backwards from.
            //
            // The phase becomes `.queued` rather than `.paused(.backgroundSuspended)`: `settle`
            // recomputes pauses from the live environment, and at launch the app is in the
            // foreground, so a synthetic pause would be cleared on the next reduction anyway.
            // `restoredFromDisk` is what actually holds these jobs, and the UI reads it to offer
            // the resume.
            next.jobs = jobs.map { job in
                guard job.phase.isLive else { return job }
                var restored = job
                restored.generatorRunning = false
                restored.phase = .queued
                restored.pauses = []
                restored.step = min(job.step, job.checkpointStep ?? 0)
                restored.stage = job.request.plan.stage(atStep: max(restored.step, 1))
                // systemUptime resets across a reboot, so every measurement in the old estimator
                // is anchored to a clock that no longer exists.
                restored.estimator = StepDurationEstimator()
                return restored
            }
            next.restoredFromDisk = next.jobs.contains { $0.phase.isLive }

        case .resumeRestored:
            next.restoredFromDisk = false

        case .cancelled(let id):
            next = finish(next, id: id, phase: .cancelled, uptime: uptime)

        case .cancelledProject(let projectID):
            for job in next.jobs where job.request.projectID == projectID && job.phase.isLive {
                next = finish(next, id: job.id, phase: .cancelled, uptime: uptime)
            }

        case .started(let id):
            next = mutate(next, id: id) { job in
                guard job.phase.isLive else { return }
                job.generatorRunning = true
                job.startedAt = job.startedAt ?? Date()
                job.phase = .running
                job.estimator.runResumed(at: uptime)
            }

        case .stepped(let id, let step, let stage, _):
            next = mutate(next, id: id) { job in
                guard job.phase.isLive else { return }
                // Never rewind. A late callback from a run that was already superseded must not
                // walk the counter backwards under the user's eyes.
                guard step > job.step else { return }
                job.step = step
                job.stage = stage
                job.estimator.record(step: step, plan: job.request.plan, at: uptime)
            }

        case .checkpointWritten(let id, let step):
            next = mutate(next, id: id) { job in
                job.checkpointStep = max(job.checkpointStep ?? 0, step)
            }

        case .checkpointRejected(let id):
            next = mutate(next, id: id) { job in
                // This event only ever arrives because `generate` threw, so the generator has
                // already stopped. Leaving `generatorRunning` set would make the derived intent
                // `.idle` and the job would sit there forever, never restarting.
                job.generatorRunning = false
                // Restart from zero with the same seed. Not a failure — the UI honestly shows
                // "step 1 of 32" again and says nothing alarming.
                job.checkpointRejected = true
                job.checkpointStep = nil
                job.step = 0
                job.stage = .reading
                job.estimator = StepDurationEstimator()
            }
            next.pendingCheckpointDiscards.append(id)

        case .checkpointDiscarded(let id):
            next.pendingCheckpointDiscards.removeAll { $0 == id }

        case .suspended(let id):
            next = mutate(next, id: id) { job in
                job.generatorRunning = false
                job.estimator.runPaused(at: uptime)
            }

        case .succeeded(let id, let outputID):
            next = finish(next, id: id, phase: .complete(outputID: outputID), uptime: uptime)

        case .failed(let id, let reason):
            next = finish(next, id: id, phase: .failed(reason: reason), uptime: uptime)

        case .thermalChanged(let level):
            next.thermal = level

        case .callChanged(let active):
            next.callActive = active

        case .powerChanged(let snapshot):
            next.battery = snapshot
            next.lowBatteryLatched = latchLowBattery(was: next.lowBatteryLatched, snapshot: snapshot)

        case .sceneChanged(let phase):
            next.scene = phase
            if phase == .active {
                // Coming back clears the suspension for everyone. A job the user has returned to
                // is a job the user is watching.
                for index in next.jobs.indices {
                    next.jobs[index].pauses.remove(.backgroundSuspended)
                }
            }

        case .resumeAnyway(let id):
            next = mutate(next, id: id) { job in
                job.lowBatteryOverridden = true
            }

        case .waitForCharge(let id):
            next = mutate(next, id: id) { job in
                job.lowBatteryOverridden = false
            }
        }

        return settle(next, at: uptime)
    }

    // ── environment → pauses ─────────────────────────────────────────────────────────────────

    /// Hysteresis. Without the gap between the two thresholds a battery hovering at exactly 10%
    /// latches and unlatches every few seconds, and the pause card flickers.
    static func latchLowBattery(was latched: Bool, snapshot: BatterySnapshot) -> Bool {
        // A device that does not report a battery — a Mac on mains, a simulator — must never have
        // a render paused on a reading the system said it does not have.
        if snapshot.isUnknown { return false }
        if snapshot.isCharging { return false }
        if latched { return snapshot.level < BatterySnapshot.resumeThreshold }
        return snapshot.level <= BatterySnapshot.pauseThreshold
    }

    /// Recompute the head's pause set and phase from the environment, and promote the queue.
    ///
    /// Called at the end of every reduction, so `phase` and `pauses` can never disagree — the
    /// invariant that a scalar `pause` field could not maintain.
    static func settle(_ state: QueueState, at uptime: TimeInterval) -> QueueState {
        var next = state
        guard let headIndex = next.jobs.firstIndex(where: { $0.phase.isLive }) else { return next }

        var head = next.jobs[headIndex]
        var pauses: Set<GenerationPause> = []

        if next.callActive { pauses.insert(.phoneCall) }
        if next.thermal >= .elevated { pauses.insert(.thermal) }
        if next.lowBatteryLatched && !head.lowBatteryOverridden { pauses.insert(.lowBattery) }
        // Low Power Mode is NOT a pause. The user chose it and may well still want the render; the
        // response is lower QoS, which `Intent.degrade` already carries. Inventing a card for it
        // would mean inventing copy the design handoff never wrote.
        if next.scene == .suspended { pauses.insert(.backgroundSuspended) }

        head.pauses = pauses

        let halting = pauses.filter { next.halts($0) }
        if let worst = halting.max(by: { $0.displayPriority < $1.displayPriority }) {
            if head.phase != .paused(worst) {
                head.phase = .paused(worst)
                head.estimator.runPaused(at: uptime)
            }
        } else if let thermalOnly = pauses.max(by: { $0.displayPriority < $1.displayPriority }),
                  thermalOnly == .thermal {
            // Throttled but still stepping. Phase stays `.running`; the card is driven by
            // `displayedPause`, so the user sees "Running slower to keep the phone cool" over a
            // step counter that is genuinely still moving.
            if case .paused = head.phase {
                head.phase = head.generatorRunning ? .running : .queued
                head.estimator.runResumed(at: uptime)
            }
        } else {
            if case .paused = head.phase {
                head.phase = head.generatorRunning ? .running : .queued
                head.estimator.runResumed(at: uptime)
            }
        }

        next.jobs[headIndex] = head
        return next
    }

    // ── helpers ──────────────────────────────────────────────────────────────────────────────

    static func mutate(_ state: QueueState,
                       id: JobID,
                       _ body: (inout Job) -> Void) -> QueueState {
        var next = state
        guard let index = next.jobs.firstIndex(where: { $0.id == id }) else { return next }
        body(&next.jobs[index])
        return next
    }

    static func finish(_ state: QueueState,
                       id: JobID,
                       phase: JobPhase,
                       uptime: TimeInterval) -> QueueState {
        var next = state
        guard let index = next.jobs.firstIndex(where: { $0.id == id }),
              next.jobs[index].phase.isLive else { return next }
        next.jobs[index].phase = phase
        next.jobs[index].pauses = []
        next.jobs[index].generatorRunning = false
        next.jobs[index].finishedAt = Date()
        // A terminal job's saved state is dead weight, and worse, a blob a later launch could try
        // to resume. Deleting every checkpoint in the app must lose no user data — that is a test.
        //
        // Only for a job that actually ran: cancelling something that never left the queue has no
        // files to delete, and asking the engine to delete them anyway puts a pointless intent in
        // front of starting the next variation.
        let ran = next.jobs[index].checkpointStep != nil || next.jobs[index].step >= 1
        if ran {
            next.pendingCheckpointDiscards.append(id)
        }
        return next
    }
}

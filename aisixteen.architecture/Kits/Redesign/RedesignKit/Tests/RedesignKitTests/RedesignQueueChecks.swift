import Foundation
import Testing
@testable import RedesignKit

/// The queue's state space, driven through the pure reducer: no generator, no clock, no simulator.
///
/// Every toggle is exercised in BOTH directions. The house rule exists because a dead toggle once
/// shipped here after tests only ever saw its default state.
@Suite("Queue — enqueue, promote, cancel")
struct QueueChecks {

    @Test("Enqueueing three variations runs only the first")
    func enqueueRunsOnlyTheHead() {
        var driver = Driver()
        driver.send(.enqueued(Fixture.variations(3)))

        #expect(driver.state.jobs.count == 3)
        #expect(driver.head?.request.variationIndex == 1)
        #expect(driver.state.queueDepth == 2)
        #expect(driver.state.queuedLabels == ["Variation 2", "Variation 3"])
        // Only the head is ever started.
        guard case .start(let id, let resumeFrom) = driver.intent else {
            Issue.record("expected .start, got \(driver.intent)"); return
        }
        #expect(id == driver.head?.id)
        #expect(resumeFrom == nil)
    }

    @Test("Finishing the head promotes the next variation")
    func finishingPromotesTheNext() {
        var driver = Driver.running(Fixture.variations(3), toStep: 32)
        let first = driver.head!.id
        driver.send(.succeeded(first, outputID: "out-1"))

        // The completed job's checkpoint is cleared before the next one starts.
        #expect(driver.intent == .discardCheckpoint(first))
        driver.send(.checkpointDiscarded(first))

        #expect(driver.head?.request.variationIndex == 2)
        #expect(driver.state.queueDepth == 1)
        #expect(driver.job(first)?.phase == .complete(outputID: "out-1"))
    }

    @Test("Cancelling the head leaves its queued siblings alone")
    func cancelIsScoped() {
        var driver = Driver.running(Fixture.variations(3), toStep: 6)
        let first = driver.head!.id
        driver.send(.cancelled(first))

        // The handoff promises this in so many words: "Cancels only this variation. Queued
        // variations continue."
        #expect(driver.job(first)?.phase == .cancelled)
        #expect(driver.state.jobs[1].phase == .queued)
        #expect(driver.state.jobs[2].phase == .queued)
        driver.send(.checkpointDiscarded(first))
        #expect(driver.head?.request.variationIndex == 2)
    }

    @Test("Cancelling a queued job does not disturb the running one")
    func cancellingAQueuedSiblingLeavesTheHeadRunning() {
        var driver = Driver.running(Fixture.variations(3), toStep: 6)
        let head = driver.head!.id
        let third = driver.state.jobs[2].id

        driver.send(.cancelled(third))

        #expect(driver.head?.id == head)
        #expect(driver.headPhase == .running)
        #expect(driver.state.queueDepth == 1)
        // A job that never ran has nothing on disk, so nothing is queued for deletion — otherwise
        // a pointless discard would sit in front of the next start.
        #expect(driver.state.pendingCheckpointDiscards.isEmpty)
    }

    @Test("Cancelling every job leaves the queue idle, not failed")
    func cancellingEverythingIsIdle() {
        var driver = Driver.running(Fixture.variations(2), toStep: 4)
        for job in driver.state.jobs { driver.send(.cancelled(job.id)) }
        while case .discardCheckpoint(let id) = driver.intent { driver.send(.checkpointDiscarded(id)) }

        #expect(driver.head == nil)
        #expect(driver.intent == .idle)
        #expect(driver.state.jobs.allSatisfy { $0.phase == .cancelled })
        #expect(!driver.state.hasLiveWork)
    }

    @Test("Cancelling a project cancels its variations and spares another project's")
    func cancelProjectIsScopedToTheProject() {
        var driver = Driver()
        driver.send(.enqueued(Fixture.variations(2, project: "living-room")))
        driver.send(.enqueued(Fixture.variations(2, project: "facade")))

        driver.send(.cancelledProject("living-room"))

        #expect(driver.state.jobs.filter { $0.request.projectID == "living-room" }
            .allSatisfy { $0.phase == .cancelled })
        #expect(driver.state.jobs.filter { $0.request.projectID == "facade" }
            .allSatisfy { $0.phase == .queued })
        #expect(driver.head?.request.projectID == "facade")
    }

    @Test("A failed variation does not stop the queue")
    func failureDoesNotKillTheQueue() {
        var driver = Driver.running(Fixture.variations(3), toStep: 11)
        let first = driver.head!.id
        driver.send(.failed(first, reason: "This device ran out of memory partway through."))
        driver.send(.checkpointDiscarded(first))

        #expect(driver.job(first)?.phase == .failed(reason: "This device ran out of memory partway through."))
        #expect(driver.head?.request.variationIndex == 2)
        #expect(driver.state.queueDepth == 1)
    }

    @Test("Starting a second project keeps the first project's queue")
    func enqueueAppendsRatherThanReplaces() {
        var driver = Driver.running(Fixture.variations(2, project: "living-room"), toStep: 3)
        driver.send(.enqueued(Fixture.variations(1, project: "facade")))

        #expect(driver.state.jobs.count == 3)
        #expect(driver.head?.request.projectID == "living-room")
        #expect(driver.headPhase == .running)
    }

    @Test("A late step callback never rewinds the counter")
    func stepsNeverRewind() {
        var driver = Driver.running(Fixture.variations(1), toStep: 12)
        let head = driver.head!.id
        driver.send(.stepped(head, step: 5, stage: .composing, hasPreview: false))
        #expect(driver.head?.step == 12)
    }
}

@Suite("Queue — interruptions are pauses, never errors")
struct PauseChecks {

    @Test("A phone call pauses the head and the queue does not advance")
    func callPauses() {
        // Step 9: one past the cadence, so there is genuinely unsaved work.
        var driver = Driver.running(Fixture.variations(2), toStep: 9)
        driver.send(.callChanged(active: true))

        #expect(driver.headPhase == .paused(.phoneCall))
        #expect(driver.head?.displayedPause == .phoneCall)
        #expect(driver.state.queueDepth == 1)
        #expect(driver.state.jobs[1].phase == .queued)
        // Save before stopping — the sequence is the whole point.
        #expect(driver.intent == .captureCheckpoint(driver.head!.id, urgent: false))
    }

    @Test("Pausing on a cadence step suspends without writing a redundant checkpoint")
    func alreadySavedPauseSuspendsDirectly() {
        // Step 8 is exactly on the checkpoint cadence, so everything is already durable. Writing
        // again would cost an atomic file write for nothing at the worst possible moment.
        var driver = Driver.running(Fixture.variations(1), toStep: 8)
        #expect(driver.head?.checkpointStep == 8)
        driver.send(.callChanged(active: true))
        #expect(driver.intent == .suspend(driver.head!.id))
    }

    @Test("Saving then suspending is the order, and only then does the generator stop")
    func pauseCapturesThenSuspends() {
        var driver = Driver.running(Fixture.variations(1), toStep: 10)
        let head = driver.head!.id
        driver.send(.callChanged(active: true))

        #expect(driver.intent == .captureCheckpoint(head, urgent: false))
        driver.send(.checkpointWritten(head, step: 10))
        #expect(driver.intent == .suspend(head))
        driver.send(.suspended(head))
        #expect(driver.intent == .idle)
        #expect(driver.head?.generatorRunning == false)
    }

    @Test("The call ending resumes the same job from its checkpoint")
    func callEndingResumes() {
        var driver = Driver.running(Fixture.variations(1), toStep: 10)
        let head = driver.head!.id
        driver.send(.callChanged(active: true))
        driver.send(.checkpointWritten(head, step: 10))
        driver.send(.suspended(head))

        driver.send(.callChanged(active: false))

        #expect(driver.headPhase == .queued)
        #expect(driver.head?.pauses.isEmpty == true)
        #expect(driver.intent == .start(head, resumeFrom: 10))
    }

    @Test("Elevated thermal keeps running and only degrades")
    func elevatedThermalDoesNotStop() {
        var driver = Driver.running(Fixture.variations(1), toStep: 14)
        driver.send(.thermalChanged(.elevated))

        // The card says "Running slower to keep the phone cool … still progressing". If elevated
        // thermal stopped the render, that sentence would be false while the user read it.
        #expect(driver.headPhase == .running)
        #expect(driver.head?.displayedPause == .thermal)
        #expect(driver.head?.isProgressing == true)
        #expect(driver.intent == .degrade(driver.head!.id, .elevated))
    }

    @Test("Critical thermal captures a checkpoint and then suspends")
    func criticalThermalHalts() {
        var driver = Driver.running(Fixture.variations(1), toStep: 14)
        let head = driver.head!.id
        driver.send(.thermalChanged(.critical))

        #expect(driver.headPhase == .paused(.thermal))
        #expect(driver.intent == .captureCheckpoint(head, urgent: false))
        driver.send(.checkpointWritten(head, step: 14))
        #expect(driver.intent == .suspend(head))
    }

    @Test("Thermal recovery from critical resumes")
    func thermalRecoveryResumes() {
        var driver = Driver.running(Fixture.variations(1), toStep: 14)
        let head = driver.head!.id
        driver.send(.thermalChanged(.critical))
        driver.send(.checkpointWritten(head, step: 12))
        driver.send(.suspended(head))

        driver.send(.thermalChanged(.nominal))

        #expect(driver.headPhase == .queued)
        #expect(driver.head?.pauses.isEmpty == true)
        #expect(driver.intent == .start(head, resumeFrom: 12))
    }

    @Test("Thermal recovery while still on a call does not resume")
    func thermalRecoveryWithACallStillActiveStaysPaused() {
        var driver = Driver.running(Fixture.variations(1), toStep: 14)
        let head = driver.head!.id
        driver.send(.callChanged(active: true))
        driver.send(.thermalChanged(.critical))
        driver.send(.checkpointWritten(head, step: 12))
        driver.send(.suspended(head))

        driver.send(.thermalChanged(.nominal))

        #expect(driver.headPhase == .paused(.phoneCall))
        #expect(driver.intent == .idle)
    }

    @Test("Low battery pauses only when unplugged")
    func lowBatteryNeedsUnplugged() {
        var driver = Driver.running(Fixture.variations(1), toStep: 6)
        driver.send(.powerChanged(Fixture.battery(0.08, charging: true)))
        #expect(driver.headPhase == .running)

        driver.send(.powerChanged(Fixture.battery(0.08, charging: false)))
        #expect(driver.headPhase == .paused(.lowBattery))
    }

    @Test("An unknown battery never pauses a render")
    func unknownBatteryNeverPauses() {
        var driver = Driver.running(Fixture.variations(1), toStep: 6)
        // A Mac on mains, or a simulator. Pausing on a reading the system said it does not have
        // would stop every render on the desktop.
        driver.send(.powerChanged(Fixture.battery(0.0, charging: false, unknown: true)))
        #expect(driver.headPhase == .running)
        #expect(driver.state.lowBatteryLatched == false)
    }

    @Test("Charging clears the low-battery pause")
    func chargingClearsLowBattery() {
        var driver = Driver.running(Fixture.variations(1), toStep: 6)
        let head = driver.head!.id
        driver.send(.powerChanged(Fixture.battery(0.08)))
        driver.send(.checkpointWritten(head, step: 4))
        driver.send(.suspended(head))
        #expect(driver.headPhase == .paused(.lowBattery))

        driver.send(.powerChanged(Fixture.battery(0.08, charging: true)))
        #expect(driver.headPhase == .queued)
        #expect(driver.intent == .start(head, resumeFrom: 4))
    }

    @Test("The low-battery threshold has hysteresis and does not flap")
    func lowBatteryHysteresis() {
        var driver = Driver.running(Fixture.variations(1), toStep: 6)
        driver.send(.powerChanged(Fixture.battery(0.10)))
        #expect(driver.headPhase == .paused(.lowBattery))

        // Still inside the band: without hysteresis this would unlatch and the card would flicker.
        driver.send(.powerChanged(Fixture.battery(0.12)))
        #expect(driver.headPhase == .paused(.lowBattery))
        #expect(driver.state.lowBatteryLatched)

        driver.send(.powerChanged(Fixture.battery(0.16)))
        #expect(driver.state.lowBatteryLatched == false)
        #expect(driver.head?.pauses.isEmpty == true)
        // The engine never actually stopped the generator here — no `.suspended` was sent — so
        // clearing the cause puts it straight back to running rather than to queued.
        #expect(driver.headPhase == .running)
    }

    @Test("Resume anyway overrides low battery for this job only")
    func resumeAnywayIsScopedToOneJob() {
        var driver = Driver.running(Fixture.variations(2), toStep: 6)
        let first = driver.head!.id
        driver.send(.powerChanged(Fixture.battery(0.08)))
        driver.send(.checkpointWritten(first, step: 4))
        driver.send(.suspended(first))

        driver.send(.resumeAnyway(first))
        #expect(driver.headPhase == .queued)
        #expect(driver.intent == .start(first, resumeFrom: 4))

        // Finish it; the NEXT variation must not inherit the override.
        driver.send(.started(first))
        driver.send(.succeeded(first, outputID: "out-1"))
        driver.send(.checkpointDiscarded(first))

        #expect(driver.head?.request.variationIndex == 2)
        #expect(driver.head?.lowBatteryOverridden == false)
        #expect(driver.headPhase == .paused(.lowBattery))
    }

    @Test("Wait for charge keeps the pause")
    func waitForChargeKeepsThePause() {
        var driver = Driver.running(Fixture.variations(1), toStep: 6)
        let head = driver.head!.id
        driver.send(.powerChanged(Fixture.battery(0.08)))
        driver.send(.resumeAnyway(head))
        #expect(driver.head?.pauses.isEmpty == true)

        // Changing your mind puts the pause back.
        driver.send(.waitForCharge(head))
        #expect(driver.headPhase == .paused(.lowBattery))
        #expect(driver.head?.lowBatteryOverridden == false)
    }

    @Test("A low-battery pause survives a thermal recovery")
    func lowBatterySurvivesThermalRecovery() {
        // The axis a single optional `pause` field gets wrong: with a scalar, thermal overwrites
        // low battery, and clearing thermal resumes a render on a dying battery.
        var driver = Driver.running(Fixture.variations(1), toStep: 9)
        driver.send(.powerChanged(Fixture.battery(0.08)))
        driver.send(.thermalChanged(.elevated))

        #expect(driver.head?.pauses == [.lowBattery, .thermal])
        #expect(driver.headPhase == .paused(.lowBattery))

        driver.send(.thermalChanged(.nominal))
        #expect(driver.head?.pauses == [.lowBattery])
        #expect(driver.headPhase == .paused(.lowBattery))
    }

    @Test("Background suspension outranks every other cause")
    func suspensionWinsTheCard() {
        var driver = Driver.running(Fixture.variations(1), toStep: 9)
        driver.send(.callChanged(active: true))
        driver.send(.powerChanged(Fixture.battery(0.08)))
        driver.send(.sceneChanged(.suspended))

        #expect(driver.head?.pauses == [.phoneCall, .lowBattery, .backgroundSuspended])
        #expect(driver.headPhase == .paused(.backgroundSuspended))
        #expect(driver.head?.displayedPause == .backgroundSuspended)
    }

    @Test("The displayed phase always matches the highest-priority cause")
    func phaseAndPauseSetNeverDisagree() {
        var driver = Driver.running(Fixture.variations(1), toStep: 9)
        for event in [RedesignQueue.Event.thermalChanged(.critical),
                      .callChanged(active: true),
                      .powerChanged(Fixture.battery(0.05)),
                      .sceneChanged(.suspended),
                      .sceneChanged(.active),
                      .callChanged(active: false),
                      .thermalChanged(.nominal),
                      .powerChanged(Fixture.battery(0.9, charging: true))] {
            driver.send(event)
            let head = driver.head!
            let halting = head.pauses.filter { driver.state.halts($0) }
            if let worst = halting.max(by: { $0.displayPriority < $1.displayPriority }) {
                #expect(head.phase == .paused(worst), "after \(event)")
            } else {
                #expect(head.phase != .paused(.phoneCall), "after \(event)")
            }
        }
    }

    @Test("Low Power Mode degrades and is never a pause")
    func lowPowerModeIsNotAPause() {
        var driver = Driver.running(Fixture.variations(1), toStep: 6)
        driver.send(.powerChanged(Fixture.battery(0.8, charging: false, lowPower: true)))

        // The user chose Low Power Mode and may well still want the render. There is no handoff
        // copy for it, and inventing a card is worse than being quiet.
        #expect(driver.headPhase == .running)
        #expect(driver.head?.pauses.isEmpty == true)
    }

    @Test("Every pause cause has distinct copy, and only low battery offers a choice")
    func pauseCopyIsDistinct() {
        let titles = Set(GenerationPause.allCases.map(\.title))
        let details = Set(GenerationPause.allCases.map(\.detail))
        #expect(titles.count == GenerationPause.allCases.count)
        #expect(details.count == GenerationPause.allCases.count)

        #expect(GenerationPause.allCases.filter(\.offersResumeChoice) == [.lowBattery])
        #expect(GenerationPause.backgroundSuspended.title == "Waiting for you.")
    }
}

@Suite("Queue — background, checkpoint and resume")
struct CheckpointChecks {

    @Test("Backgrounding captures urgently, then suspends")
    func backgroundingCapturesUrgently() {
        var driver = Driver.running(Fixture.variations(1), toStep: 15)
        let head = driver.head!.id
        driver.send(.sceneChanged(.suspended))

        #expect(driver.headPhase == .paused(.backgroundSuspended))
        // Urgent: the app is inside a closing window and must not await anything.
        #expect(driver.intent == .captureCheckpoint(head, urgent: true))
        driver.send(.checkpointWritten(head, step: 15))
        #expect(driver.intent == .suspend(head))
    }

    @Test("Nothing starts while the app is off screen")
    func nothingStartsWhileSuspended() {
        var driver = Driver()
        driver.send(.sceneChanged(.suspended))
        driver.send(.enqueued(Fixture.variations(1)))

        // This build claims no background execution mode, so starting here would be a promise the
        // platform will not keep.
        #expect(driver.intent == .idle)
    }

    @Test("Returning to the foreground resumes from the checkpoint step")
    func foregroundResumesAtTheCheckpoint() {
        var driver = Driver.running(Fixture.variations(1), toStep: 15)
        let head = driver.head!.id
        driver.send(.sceneChanged(.suspended))
        driver.send(.checkpointWritten(head, step: 15))
        driver.send(.suspended(head))

        driver.send(.sceneChanged(.active))

        #expect(driver.head?.pauses.isEmpty == true)
        #expect(driver.intent == .start(head, resumeFrom: 15))
        #expect(driver.head?.step == 15, "resuming must not rewind the counter")
    }

    @Test("A rejected checkpoint restarts at zero with the same seed and is not a failure")
    func rejectedCheckpointRestartsCleanly() {
        var driver = Driver.running(Fixture.variations(1), toStep: 15)
        let head = driver.head!.id
        let seed = driver.head!.request.seed
        driver.send(.checkpointRejected(head))

        #expect(driver.head?.step == 0)
        #expect(driver.head?.checkpointStep == nil)
        #expect(driver.head?.checkpointRejected == true)
        #expect(driver.head?.request.seed == seed, "the same seed, so the render is reproducible")
        #expect(driver.headPhase != .failed(reason: ""))
        // The dead file is cleared, then the run starts over from scratch.
        #expect(driver.intent == .discardCheckpoint(head))
        driver.send(.checkpointDiscarded(head))
        #expect(driver.intent == .start(head, resumeFrom: nil))
    }

    @Test("Cancelling discards the checkpoint")
    func cancelDiscards() {
        var driver = Driver.running(Fixture.variations(1), toStep: 8)
        let head = driver.head!.id
        driver.send(.cancelled(head))
        #expect(driver.state.pendingCheckpointDiscards == [head])
    }

    @Test("Completing discards the checkpoint")
    func completionDiscards() {
        var driver = Driver.running(Fixture.variations(1), toStep: 32)
        let head = driver.head!.id
        driver.send(.succeeded(head, outputID: "out"))
        #expect(driver.state.pendingCheckpointDiscards == [head])
    }

    @Test("checkpointStep never runs ahead of the reported step")
    func checkpointNeverLeadsTheCounter() {
        var driver = Driver.running(Fixture.variations(1), toStep: 20)
        let head = driver.head!
        #expect((head.checkpointStep ?? 0) <= head.step)
        // Cadence is 4, so at step 20 the last durable checkpoint is step 20.
        #expect(head.checkpointStep == 20)
    }

    @Test("Restoring after a kill never auto-starts")
    func restoreNeverAutoStarts() {
        var live = Fixture.job(Fixture.request())
        live.phase = .running
        live.generatorRunning = true
        live.step = 19
        live.checkpointStep = 16

        var driver = Driver()
        driver.send(.restored([live]))

        #expect(driver.state.restoredFromDisk)
        #expect(driver.headPhase == .queued)
        #expect(driver.head?.generatorRunning == false)
        // Burning minutes of Neural Engine time because somebody opened the app to look at their
        // library is wrong. It waits for a tap.
        #expect(driver.intent == .idle)

        driver.send(.resumeRestored)
        #expect(driver.intent == .start(live.id, resumeFrom: 16))
    }

    @Test("Restoring clamps the step back to the last durable checkpoint")
    func restoreClampsToTheCheckpoint() {
        var live = Fixture.job(Fixture.request())
        live.phase = .running
        live.generatorRunning = true
        live.step = 19          // three steps completed after the last checkpoint …
        live.checkpointStep = 16 // … and lost with the process.

        var driver = Driver()
        driver.send(.restored([live]))

        // Showing 19 and then resuming at 17 walks the counter backwards under the user's eyes.
        #expect(driver.head?.step == 16)
        #expect(driver.head?.stage == RedesignPlan.standard.stage(atStep: 16))
    }

    @Test("Restoring with no checkpoint clamps to zero")
    func restoreWithoutACheckpointStartsOver() {
        var live = Fixture.job(Fixture.request())
        live.phase = .running
        live.step = 3
        live.checkpointStep = nil

        var driver = Driver()
        driver.send(.restored([live]))
        driver.send(.resumeRestored)

        #expect(driver.head?.step == 0)
        #expect(driver.intent == .start(live.id, resumeFrom: nil))
    }

    @Test("New work clears the restored latch")
    func enqueueingClearsTheRestoredLatch() {
        var live = Fixture.job(Fixture.request(project: "old"))
        live.phase = .running
        live.checkpointStep = 8

        var driver = Driver()
        driver.send(.restored([live]))
        #expect(driver.intent == .idle)

        driver.send(.enqueued(Fixture.variations(1, project: "new")))
        #expect(driver.state.restoredFromDisk == false)
        #expect(driver.intent == .start(live.id, resumeFrom: 8))
    }

    @Test("A checkpoint is usable only when kind, digest and device all match")
    func checkpointValidation() {
        let request = Fixture.request()
        let good = Fixture.checkpoint(for: request, step: 12)
        #expect(good.rejection(forKind: "mock.v1", digest: request.digest, deviceID: "mock-device") == nil)
        #expect(good.resumesAtStep == 13)

        #expect(good.rejection(forKind: "coreml.v1", digest: request.digest, deviceID: "mock-device") == .kindMismatch)
        #expect(good.rejection(forKind: "mock.v1", digest: "other", deviceID: "mock-device") == .digestMismatch)
        #expect(good.rejection(forKind: "mock.v1", digest: request.digest, deviceID: "someone-elses") == .foreignDevice)

        let finished = Fixture.checkpoint(for: request, step: 32)
        #expect(finished.rejection(forKind: "mock.v1", digest: request.digest, deviceID: "mock-device") == .alreadyComplete)

        let empty = GenerationCheckpoint(kind: "mock.v1", requestDigest: request.digest, step: 4,
                                         totalSteps: 32, deviceID: "mock-device",
                                         state: Data(), createdAt: Date())
        #expect(empty.rejection(forKind: "mock.v1", digest: request.digest, deviceID: "mock-device") == .empty)
    }

    @Test("Editing the prompt invalidates a checkpoint from the old prompt")
    func digestTracksWhatMatters() {
        let original = Fixture.request(prompt: "Bright Scandinavian living room")
        let edited = Fixture.request(prompt: "Bright Scandinavian living room, darker floor")
        let checkpoint = Fixture.checkpoint(for: original, step: 12)

        #expect(checkpoint.rejection(forKind: "mock.v1", digest: edited.digest, deviceID: "mock-device") == .digestMismatch)
    }

    @Test("Renaming the space does not invalidate a checkpoint")
    func digestIgnoresDisplayNames() {
        // Twenty steps into a three-minute render, renaming "Living room" to "Lounge" must not
        // throw the work away.
        let before = Fixture.request(spaceName: "Living room")
        let after = Fixture.request(spaceName: "Lounge")
        #expect(before.digest == after.digest)
    }
}

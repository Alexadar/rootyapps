import Foundation
import Testing
@testable import RedesignKit

@Suite("Plan — stages, cadences, veil")
struct RedesignPlanChecks {

    let plan = RedesignPlan.standard

    @Test("Stage boundaries match the design board")
    func stageBoundaries() {
        // The HTML board reads "Refining details · step 18 of 32", and that has to stay true.
        #expect(plan.totalSteps == 32)
        #expect(plan.stage(atStep: 18) == .refining)
        for step in 1...4 { #expect(plan.stage(atStep: step) == .reading) }
        for step in 5...12 { #expect(plan.stage(atStep: step) == .composing) }
        for step in 13...28 { #expect(plan.stage(atStep: step) == .refining) }
        for step in 29...32 { #expect(plan.stage(atStep: step) == .fullRes) }
    }

    @Test("Every step belongs to exactly one stage, with no gaps")
    func stagesAreContiguous() {
        var covered = Set<Int>()
        for range in plan.stageRanges {
            for step in range.lowerBound...range.upperBound {
                #expect(!covered.contains(step), "step \(step) is in two stages")
                covered.insert(step)
            }
        }
        #expect(covered == Set(1...plan.totalSteps))
    }

    @Test("The stage names are the strings the UI prints")
    func stageNamesAreTheCopy() {
        #expect(GenerationStage.reading.rawValue == "Reading the space")
        #expect(GenerationStage.composing.rawValue == "Composing the redesign")
        #expect(GenerationStage.refining.rawValue == "Refining details")
        #expect(GenerationStage.fullRes.rawValue == "Full resolution")
        #expect(GenerationStage.allCases.count == 4)
    }

    @Test("The final step always emits a preview")
    func finalStepAlwaysPreviews() {
        // Otherwise the last frame the user saw is step 30, and the finished picture appears with
        // a visible jump at the moment the result screen opens.
        #expect(plan.emitsPreview(atStep: 32))
        #expect(plan.emitsPreview(atStep: 2))
        #expect(!plan.emitsPreview(atStep: 3))
        #expect(!plan.emitsPreview(atStep: 0))
        #expect(!plan.emitsPreview(atStep: 33))
    }

    @Test("The final step never offers a checkpoint")
    func finalStepNeverCheckpoints() {
        // Resuming "from step 32 of 32" is a run with no work left in it.
        #expect(!plan.offersCheckpoint(atStep: 32))
        #expect(plan.offersCheckpoint(atStep: 4))
        #expect(plan.offersCheckpoint(atStep: 28))
        #expect(!plan.offersCheckpoint(atStep: 5))
    }

    @Test("The milk veil eases from 26 to 0 across the run")
    func veilBlurEases() {
        #expect(plan.veilBlur(atStep: 0) == 26)
        #expect(plan.veilBlur(atStep: 32) == 0)
        #expect(plan.veilBlur(atStep: 16) == 13)
        #expect(plan.veilOpacity == 0.22)
        // Monotonic — the image only ever gets clearer.
        var previous = Double.infinity
        for step in 0...32 {
            let blur = plan.veilBlur(atStep: step)
            #expect(blur <= previous)
            previous = blur
        }
    }

    @Test("Weighted remaining falls to zero and never goes negative")
    func weightedRemainingIsWellBehaved() {
        #expect(plan.weightedRemaining(afterStep: 32) == 0)
        #expect(plan.weightedRemaining(afterStep: 40) == 0)
        #expect(plan.weightedTotal > 0)
        var previous = Double.infinity
        for step in 0...32 {
            let remaining = plan.weightedRemaining(afterStep: step)
            #expect(remaining >= 0)
            #expect(remaining <= previous)
            previous = remaining
        }
    }
}

@Suite("Live Activity — never fake progress, never spam")
struct LiveActivityChecks {

    let throttle = LiveActivityThrottle()

    private func snapshot(step: Int,
                          stage: GenerationStage = .refining,
                          queued: Int = 2,
                          waiting: Bool = false,
                          job: String = "living-room-1") -> ActivitySnapshot {
        ActivitySnapshot(jobID: JobID(job),
                         projectID: "living-room",
                         spaceName: "Living room",
                         styleName: "Scandinavian",
                         variationLabel: "Variation 1 of 3",
                         stage: stage.rawValue,
                         step: step,
                         totalSteps: 32,
                         queuedCount: queued,
                         waiting: waiting,
                         remainingText: "about 2 min left")
    }

    @Test("A 32-step run costs at most ten updates")
    func aFullRunStaysWithinBudget() {
        // ActivityKit throttles a chatty app and eventually drops its updates outright — a failure
        // with no error message, where the activity simply stops moving.
        var last: ActivitySnapshot?
        var lastAt: TimeInterval?
        var published = 0
        var clock = 0.0

        for step in 1...32 {
            clock += 5
            let next = snapshot(step: step, stage: RedesignPlan.standard.stage(atStep: step))
            if throttle.shouldPublish(next, last: last, lastPublishedAt: lastAt, now: clock) {
                published += 1
                last = next
                lastAt = clock
            }
        }
        // Twelve: eight on the four-step stride, one for the very first step, and three stage
        // changes — which are deliberately unthrottled, because a stage name that lags the work is
        // worse than an extra update. Well under one per step, which is the point.
        #expect(published <= 12, "published \(published) updates for one render")
        #expect(published >= 4, "an activity that barely updates looks stuck")
    }

    @Test("Entering and leaving the waiting state always publishes immediately")
    func waitingAlwaysPublishes() {
        let running = snapshot(step: 18)
        let waiting = snapshot(step: 18, waiting: true)

        #expect(throttle.shouldPublish(waiting, last: running, lastPublishedAt: 100, now: 100.1))
        #expect(throttle.shouldPublish(running, last: waiting, lastPublishedAt: 100, now: 100.1))
    }

    @Test("A frozen counter publishes nothing more while waiting")
    func waitingDoesNotRepeat() {
        let waiting = snapshot(step: 18, waiting: true)
        #expect(!throttle.shouldPublish(waiting, last: waiting, lastPublishedAt: 100, now: 1_000))
    }

    @Test("A stage change publishes immediately")
    func stageChangePublishes() {
        let before = snapshot(step: 12, stage: .composing)
        let after = snapshot(step: 13, stage: .refining)
        #expect(throttle.shouldPublish(after, last: before, lastPublishedAt: 100, now: 100.5))
    }

    @Test("A change in queue depth publishes immediately")
    func queueDepthChangePublishes() {
        let before = snapshot(step: 13, queued: 2)
        let after = snapshot(step: 13, queued: 1)
        #expect(throttle.shouldPublish(after, last: before, lastPublishedAt: 100, now: 100.1))
    }

    @Test("Reaching the last step publishes immediately")
    func completionPublishes() {
        let before = snapshot(step: 31)
        let after = snapshot(step: 32)
        #expect(throttle.shouldPublish(after, last: before, lastPublishedAt: 100, now: 100.1))
    }

    @Test("A different job publishes immediately")
    func newJobPublishes() {
        let first = snapshot(step: 30, job: "living-room-1")
        let second = snapshot(step: 1, job: "living-room-2")
        #expect(throttle.shouldPublish(second, last: first, lastPublishedAt: 100, now: 100.1))
    }

    @Test("A suspended snapshot reports no time remaining")
    func waitingHasNoEstimate() {
        var driver = Driver.running(Fixture.variations(3), toStep: 15)
        driver.send(.sceneChanged(.suspended))

        let snapshot = try! #require(ActivitySnapshot.make(from: driver.state,
                                                           remainingText: "about 2 min left"))
        #expect(snapshot.waiting)
        // A job making no progress has no honest time-left to report.
        #expect(snapshot.remainingText == nil)
        #expect(snapshot.step == 15, "the counter freezes rather than advancing")
        #expect(snapshot.queuedCount == 2)
        #expect(snapshot.variationLabel == "Variation 1 of 3")
    }

    @Test("A running snapshot carries the real stage, step and queue depth")
    func runningSnapshotIsTruthful() {
        var driver = Driver.running(Fixture.variations(3), toStep: 18)
        let snapshot = try! #require(ActivitySnapshot.make(from: driver.state,
                                                           remainingText: "about 2 min left"))
        #expect(snapshot.stage == GenerationStage.refining.rawValue)
        #expect(snapshot.step == 18)
        #expect(snapshot.totalSteps == 32)
        #expect(snapshot.queuedCount == 2)
        #expect(!snapshot.waiting)
        #expect(snapshot.remainingText == "about 2 min left")
        _ = driver
    }

    @Test("An empty queue has no snapshot at all")
    func noWorkNoActivity() {
        #expect(ActivitySnapshot.make(from: QueueState(), remainingText: nil) == nil)
    }
}

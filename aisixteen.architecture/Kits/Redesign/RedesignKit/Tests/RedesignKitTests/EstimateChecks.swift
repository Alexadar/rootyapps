import Foundation
import Testing
@testable import RedesignKit

@Suite("Estimate — measured, never guessed")
struct EstimateChecks {

    let plan = RedesignPlan.standard

    /// Run `count` steps at a fixed number of seconds per unit weight.
    private func run(_ estimator: inout StepDurationEstimator,
                     from first: Int,
                     through last: Int,
                     secondsPerWeight: Double,
                     startingAt uptime: TimeInterval = 1_000) -> TimeInterval {
        var clock = uptime
        estimator.runResumed(at: clock)
        for step in first...last {
            clock += secondsPerWeight * plan.weight(of: plan.stage(atStep: step))
            estimator.record(step: step, plan: plan, at: clock)
        }
        return clock
    }

    @Test("No estimate before three samples")
    func noEstimateUntilThreeSamples() {
        var estimator = StepDurationEstimator()
        var clock = 1_000.0
        estimator.runResumed(at: clock)

        for step in 1...2 {
            clock += 4
            estimator.record(step: step, plan: plan, at: clock)
            // One sample is noise. `GeneratingView` renders nothing for nil, and that is the
            // honest state — a guess dressed as a measurement is the thing this app avoids.
            #expect(estimator.secondsRemaining(afterStep: step, plan: plan) == nil)
        }

        clock += 4
        estimator.record(step: 3, plan: plan, at: clock)
        #expect(estimator.secondsRemaining(afterStep: 3, plan: plan) != nil)
    }

    @Test("A steady run converges on the true rate")
    func converges() {
        var estimator = StepDurationEstimator()
        _ = run(&estimator, from: 1, through: 12, secondsPerWeight: 4)

        let perStep = try! #require(estimator.secondsPerWeightedStep)
        #expect(abs(perStep - 4) < 0.25)

        // 20 steps left: 16 refining at weight 1 and 4 full-res at weight 6 = 40 weighted steps.
        let remaining = try! #require(estimator.secondsRemaining(afterStep: 12, plan: plan))
        #expect(abs(remaining - 160) < 12)
    }

    @Test("Pause time is excluded from the estimate")
    func pauseTimeExcluded() {
        var estimator = StepDurationEstimator()
        var clock = run(&estimator, from: 1, through: 8, secondsPerWeight: 4)
        let before = try! #require(estimator.secondsPerWeightedStep)

        // A twenty-minute phone call. Folded into the average this becomes "about 300 min left".
        estimator.runPaused(at: clock)
        clock += 20 * 60
        estimator.runResumed(at: clock)

        clock += 4
        estimator.record(step: 9, plan: plan, at: clock)

        let after = try! #require(estimator.secondsPerWeightedStep)
        #expect(abs(after - before) < 0.5)
    }

    @Test("Steps recorded while paused do not poison the average")
    func stepsDuringAPauseAreIgnored() {
        var estimator = StepDurationEstimator()
        var clock = run(&estimator, from: 1, through: 6, secondsPerWeight: 4)
        let before = try! #require(estimator.secondsPerWeightedStep)

        estimator.runPaused(at: clock)
        clock += 900
        estimator.record(step: 7, plan: plan, at: clock)

        #expect(estimator.secondsPerWeightedStep == before)
    }

    @Test("Slowing steps raise the estimate smoothly, never in a jump")
    func throttlingRaisesTheEstimateSmoothly() {
        var estimator = StepDurationEstimator()
        var clock = run(&estimator, from: 1, through: 10, secondsPerWeight: 4)
        var previous = try! #require(estimator.secondsPerWeightedStep)

        // The device gets hot and every step now takes three times as long.
        for step in 11...16 {
            clock += 12 * plan.weight(of: plan.stage(atStep: step))
            estimator.record(step: step, plan: plan, at: clock)
            let current = try! #require(estimator.secondsPerWeightedStep)
            #expect(current >= previous, "the estimate must not fall while the device slows down")
            // Smoothing at 0.25 means no single sample can move it more than a quarter of the gap.
            #expect(current - previous <= (12 - previous) * 0.26 + 0.01)
            previous = current
        }
        // Six samples is enough to have followed most of the way.
        #expect(previous > 7)
    }

    @Test("Full resolution is weighted far heavier than refining")
    func fullResolutionIsWeighted() {
        // Without weighting, the estimate collapses to "1 min left" at step 28 and then hangs
        // there for ninety seconds inside the VAE decode — exactly the lie the design forbids.
        #expect(plan.weight(of: .fullRes) > plan.weight(of: .refining) * 5)

        var estimator = StepDurationEstimator()
        _ = run(&estimator, from: 1, through: 28, secondsPerWeight: 4)

        let remaining = try! #require(estimator.secondsRemaining(afterStep: 28, plan: plan))
        // Four full-res steps at weight 6 = 24 weighted steps × 4 s.
        #expect(abs(remaining - 96) < 8)
        #expect(remaining > 60, "the last four steps are more than a minute of real work")
    }

    @Test("The estimate is zero once the last step is done")
    func finishedMeansZero() {
        var estimator = StepDurationEstimator()
        _ = run(&estimator, from: 1, through: 32, secondsPerWeight: 2)
        #expect(estimator.secondsRemaining(afterStep: 32, plan: plan) == 0)
    }

    @Test("A clock that goes backwards is ignored rather than poisoning the average")
    func backwardsClockIsIgnored() {
        var estimator = StepDurationEstimator()
        let clock = run(&estimator, from: 1, through: 8, secondsPerWeight: 4)
        let before = try! #require(estimator.secondsPerWeightedStep)

        estimator.record(step: 9, plan: plan, at: clock - 100)
        #expect(estimator.secondsPerWeightedStep == before)
    }
}

@Suite("Estimate — the words")
struct RemainingPhraseChecks {

    @Test("Under three quarters of a minute never claims a minute")
    func shortIsHonest() {
        #expect(RemainingPhrase.text(for: 15) == "less than a minute left")
        #expect(RemainingPhrase.text(for: 44) == "less than a minute left")
        #expect(RemainingPhrase.text(for: 60) == "about a minute left")
    }

    @Test("Minutes and hours read as sentences")
    func longerReadsWell() {
        #expect(RemainingPhrase.text(for: 4 * 60) == "about 4 min left")
        #expect(RemainingPhrase.text(for: 59 * 60) == "about 59 min left")
        #expect(RemainingPhrase.text(for: 60 * 60) == "about an hour left")
        #expect(RemainingPhrase.text(for: 2 * 60 * 60) == "about 2 hours left")
        #expect(RemainingPhrase.text(for: 95 * 60) == "about 1 h 35 min left")
    }

    @Test("No measurement means no words, never a number")
    func nilMeansSilence() {
        let state = RemainingPhrase.update(RemainingPhrase.State(), seconds: nil)
        #expect(state.text == nil)
    }

    @Test("Hysteresis stops the minute count flipping back and forth")
    func hysteresisHoldsTheWords() {
        // A rolling estimate genuinely wobbles a few percent every step. A countdown that reads
        // 4 → 5 → 4 → 5 tells the user the app does not know what it is doing.
        var state = RemainingPhrase.update(RemainingPhrase.State(), seconds: 270)
        #expect(state.text == "about 5 min left")

        for wobble in [265.0, 275.0, 268.0, 272.0] {
            state = RemainingPhrase.update(state, seconds: wobble)
            #expect(state.text == "about 5 min left")
        }

        // A real move of more than 15% does change the words.
        state = RemainingPhrase.update(state, seconds: 400)
        #expect(state.text == "about 7 min left")
    }

    @Test("A large drop is followed immediately")
    func realProgressUpdates() {
        var state = RemainingPhrase.update(RemainingPhrase.State(), seconds: 600)
        #expect(state.text == "about 10 min left")
        state = RemainingPhrase.update(state, seconds: 120)
        #expect(state.text == "about 2 min left")
    }
}

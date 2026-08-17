import Foundation

/// Time left, measured rather than guessed.
///
/// The design handoff is explicit: "Time-left is a rolling estimate from measured step duration —
/// not a fixed guess." Four things follow from taking that seriously, and each is a test:
///
///   1. **No estimate before three samples.** One sample is noise; the UI renders nothing for nil
///      and that is the honest state.
///   2. **Pause time is excluded.** A twenty-minute phone call would otherwise be divided into the
///      step average and produce "about 300 min left".
///   3. **Steps are weighted by stage.** Full resolution is one very long step. Treating every
///      step as equal collapses the estimate to "1 min left" and then hangs there for ninety
///      seconds — exactly the small lie this app's design exists to avoid.
///   4. **It owns no clock.** The caller supplies a monotonic uptime, so the entire thing is
///      testable without waiting for real seconds to pass.
public struct StepDurationEstimator: Sendable, Equatable, Codable, Hashable {
    /// Exponential smoothing factor. 0.25 follows a genuine slowdown — a device throttling — in
    /// about four samples, without chasing the jitter between two adjacent steps.
    public let smoothing: Double
    public let minimumSamples: Int

    /// Seconds per *weighted* step.
    private var average: TimeInterval?
    private var lastStepUptime: TimeInterval?
    private var samples: Int
    private var pausedAt: TimeInterval?

    public init(smoothing: Double = 0.25, minimumSamples: Int = 3) {
        self.smoothing = smoothing
        self.minimumSamples = minimumSamples
        self.average = nil
        self.lastStepUptime = nil
        self.samples = 0
        self.pausedAt = nil
    }

    public var sampleCount: Int { samples }
    public var isPaused: Bool { pausedAt != nil }
    public var secondsPerWeightedStep: TimeInterval? { samples >= minimumSamples ? average : nil }

    /// Record that `step` just completed.
    public mutating func record(step: Int, plan: RedesignPlan, at uptime: TimeInterval) {
        defer { lastStepUptime = uptime }
        // While paused, wall time is passing but no work is being done. Drop the interval rather
        // than folding it into the average.
        if pausedAt != nil { return }
        guard let previous = lastStepUptime else { return }

        let elapsed = uptime - previous
        // A non-positive interval means the caller's clock went backwards, which a monotonic clock
        // does not do — so it is a test feeding events out of order, or a bug. Either way it must
        // not poison the average.
        guard elapsed > 0 else { return }

        let weight = plan.weight(of: plan.stage(atStep: step))
        guard weight > 0 else { return }
        let perWeightedStep = elapsed / weight

        if let current = average {
            average = current + smoothing * (perWeightedStep - current)
        } else {
            average = perWeightedStep
        }
        samples += 1
    }

    /// Work stopped. The interval from here until `runResumed` is excluded.
    public mutating func runPaused(at uptime: TimeInterval) {
        guard pausedAt == nil else { return }
        pausedAt = uptime
    }

    /// Work started again. The next step's interval is measured from now, not from before the
    /// pause.
    public mutating func runResumed(at uptime: TimeInterval) {
        guard pausedAt != nil else {
            // A fresh run: anchor the clock so the first interval is measured from the start.
            if lastStepUptime == nil { lastStepUptime = uptime }
            return
        }
        pausedAt = nil
        lastStepUptime = uptime
    }

    /// Seconds of work still to do after `step`, or nil while there is nothing measured.
    public func secondsRemaining(afterStep step: Int, plan: RedesignPlan) -> TimeInterval? {
        guard let perWeightedStep = secondsPerWeightedStep else { return nil }
        let remaining = plan.weightedRemaining(afterStep: step)
        guard remaining > 0 else { return 0 }
        return perWeightedStep * remaining
    }
}

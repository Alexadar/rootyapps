import Foundation

/// Everything the Live Activity shows, as a plain value.
///
/// Kept here, in a Foundation-only package, rather than in the widget: it means the throttle and
/// the "never fake progress" rule can be unit-tested without ActivityKit, a device, or a widget
/// extension. The app maps this onto `RedesignActivityAttributes.ContentState` at the boundary.
public struct ActivitySnapshot: Sendable, Equatable, Codable, Hashable {
    public let jobID: JobID
    public let projectID: String
    public let spaceName: String
    public let styleName: String
    public let variationLabel: String
    /// `GenerationStage.rawValue`, so the widget target need not link the enum.
    public let stage: String
    public let step: Int
    public let totalSteps: Int
    public let queuedCount: Int
    /// Suspended. Step and totalSteps are FROZEN while this is true — the handoff is explicit that
    /// a suspended activity reads "Waiting for you" and never shows progress it is not making.
    public let waiting: Bool
    public let remainingText: String?

    public init(jobID: JobID,
                projectID: String,
                spaceName: String,
                styleName: String,
                variationLabel: String,
                stage: String,
                step: Int,
                totalSteps: Int,
                queuedCount: Int,
                waiting: Bool,
                remainingText: String?) {
        self.jobID = jobID
        self.projectID = projectID
        self.spaceName = spaceName
        self.styleName = styleName
        self.variationLabel = variationLabel
        self.stage = stage
        self.step = step
        self.totalSteps = totalSteps
        self.queuedCount = queuedCount
        self.waiting = waiting
        self.remainingText = remainingText
    }

    /// Build from the queue's head. Returns nil when there is nothing to show.
    public static func make(from state: QueueState, remainingText: String?) -> ActivitySnapshot? {
        guard let head = state.head else { return nil }
        let waiting = head.pauses.contains(.backgroundSuspended)
        return ActivitySnapshot(
            jobID: head.id,
            projectID: head.request.projectID,
            spaceName: head.request.spaceName,
            styleName: head.request.styleName,
            variationLabel: "\(head.request.variationLabel) of \(head.request.variationCount)",
            stage: head.stage.rawValue,
            step: head.step,
            totalSteps: head.totalSteps,
            queuedCount: state.queueDepth,
            waiting: waiting,
            // A suspended job is making no progress, so it has no honest time-left to report.
            remainingText: waiting ? nil : remainingText
        )
    }
}

/// How often the Live Activity may be updated.
///
/// ActivityKit throttles a chatty app and eventually drops its updates outright, which is a
/// failure mode with no error: the activity simply stops moving. A 32-step render must cost
/// roughly ten updates, not thirty-two.
///
/// Some changes are never throttled, because delaying them would make the activity *wrong* rather
/// than merely stale: entering or leaving `waiting`, a stage change, a change in queue depth, and
/// the final step.
public struct LiveActivityThrottle: Sendable, Equatable, Codable, Hashable {
    public let minimumInterval: TimeInterval
    /// Aligned with `RedesignPlan.checkpointCadence` so one moment of work serves both.
    public let stepStride: Int

    public init(minimumInterval: TimeInterval = 4.0, stepStride: Int = 4) {
        self.minimumInterval = minimumInterval
        self.stepStride = stepStride
    }

    public func shouldPublish(_ next: ActivitySnapshot,
                              last: ActivitySnapshot?,
                              lastPublishedAt: TimeInterval?,
                              now: TimeInterval) -> Bool {
        guard let last, let lastPublishedAt else { return true }

        // A different job entirely.
        if next.jobID != last.jobID { return true }
        // The one that matters most: "Waiting for you" must appear the moment it is true, and
        // disappear the moment it is not.
        if next.waiting != last.waiting { return true }
        if next.stage != last.stage { return true }
        if next.queuedCount != last.queuedCount { return true }
        if next.step >= next.totalSteps && last.step < last.totalSteps { return true }

        // A frozen counter publishes nothing: while waiting, `step` does not advance, and there is
        // no reason to spend an update saying so twice.
        if next.waiting { return false }
        if next.step == last.step { return false }

        let strideReached = next.step % stepStride == 0
        let intervalElapsed = (now - lastPublishedAt) >= minimumInterval
        return strideReached && intervalElapsed
    }

    /// When the system should start treating the content as stale — two strides' worth of work.
    /// Past that, iOS dims the activity rather than leaving a frozen counter looking live.
    public func staleInterval(secondsPerStep: TimeInterval?) -> TimeInterval {
        let perStep = secondsPerStep ?? 6
        return max(minimumInterval * 2, perStep * Double(stepStride) * 2)
    }
}

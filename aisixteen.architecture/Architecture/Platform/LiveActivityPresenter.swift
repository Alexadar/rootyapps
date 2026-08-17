import Foundation
import RedesignKit
#if os(iOS)
import ActivityKit
#endif

/// Drives the Live Activity from the engine's state. iOS only.
///
/// macOS deliberately has none of this — the handoff says the Mac gets a standard notification
/// instead, and the Mac's entitlements do not even carry the App Group.
@MainActor
final class LiveActivityPresenter {

    private let throttle = LiveActivityThrottle()
    private var lastSnapshot: ActivitySnapshot?
    private var lastPublishedAt: TimeInterval?
    private var thumbnailStamp = 0

    #if os(iOS)
    private var activity: Activity<RedesignActivityAttributes>?
    #endif

    func update(for state: QueueState, remainingText: String?) {
        #if os(iOS)
        guard let snapshot = ActivitySnapshot.make(from: state, remainingText: remainingText) else {
            end()
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        guard throttle.shouldPublish(snapshot,
                                     last: lastSnapshot,
                                     lastPublishedAt: lastPublishedAt,
                                     now: now) else { return }
        lastSnapshot = snapshot
        lastPublishedAt = now
        publish(snapshot, secondsPerStep: nil)
        #endif
    }

    /// The forming thumbnail travels as a FILE in the App Group, never in the content state —
    /// ActivityKit caps that at a few KB and a picture does not fit. 256 pt, JPEG q 0.7, about
    /// 20 KB, replaced atomically so the widget never reads a half-written frame.
    func writeThumbnail(_ preview: PreviewImage, jobID: JobID, step: Int) {
        #if os(iOS)
        guard let url = RedesignActivity.thumbnailURL(jobID: jobID.rawValue) else { return }
        guard let data = Bitmap.thumbnailData(from: preview, maxPixel: 256) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
        thumbnailStamp = step
        #endif
    }

    func end() {
        #if os(iOS)
        guard let activity else { return }
        self.activity = nil
        lastSnapshot = nil
        lastPublishedAt = nil
        let identifier = activity.attributes.jobID
        Task {
            // A short grace window so a tap on the finished activity can still open the Result.
            await activity.end(nil, dismissalPolicy: .after(.now + 15 * 60))
            if let url = RedesignActivity.thumbnailURL(jobID: identifier) {
                try? FileManager.default.removeItem(at: url)
            }
        }
        #endif
    }

    #if os(iOS)
    private func publish(_ snapshot: ActivitySnapshot, secondsPerStep: TimeInterval?) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let content = RedesignActivityAttributes.ContentState(
            spaceName: snapshot.spaceName,
            styleName: snapshot.styleName,
            stage: snapshot.stage,
            step: snapshot.step,
            totalSteps: snapshot.totalSteps,
            queuedCount: snapshot.queuedCount,
            waiting: snapshot.waiting,
            thumbnailName: "\(snapshot.jobID.rawValue).jpg",
            thumbnailStamp: thumbnailStamp,
            remainingText: snapshot.remainingText)

        // Past the stale date iOS dims the activity instead of leaving a frozen counter looking
        // live. That is the honest treatment for an app that was suspended mid-render.
        let stale = Date().addingTimeInterval(throttle.staleInterval(secondsPerStep: secondsPerStep))

        if let activity, activity.attributes.jobID == snapshot.jobID.rawValue {
            Task {
                await activity.update(ActivityContent(state: content, staleDate: stale),
                                      alertConfiguration: alert(for: snapshot))
            }
        } else {
            // A different job: end the old activity and start a new one, rather than repurposing
            // it — the space name and the variation label are static attributes.
            if let previous = self.activity {
                Task { await previous.end(nil, dismissalPolicy: .immediate) }
            }
            let attributes = RedesignActivityAttributes(projectID: snapshot.projectID,
                                                        jobID: snapshot.jobID.rawValue,
                                                        variationLabel: snapshot.variationLabel)
            activity = try? Activity.request(attributes: attributes,
                                             content: ActivityContent(state: content, staleDate: stale))
        }
    }

    /// Only two moments earn an alert: finishing, and going quiet. Anything else is a buzz for
    /// something the user did not ask to be told about.
    private func alert(for snapshot: ActivitySnapshot) -> AlertConfiguration? {
        if snapshot.waiting && lastSnapshot?.waiting == false {
            return AlertConfiguration(title: "Waiting for you",
                                      body: "Open the app and it picks up where it left off.",
                                      sound: .default)
        }
        return nil
    }
    #endif
}

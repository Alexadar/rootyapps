import Foundation
import UserNotifications

/// One local notification per completed variation.
///
/// Modelled on `eartharound.swift/.../AlertNotifier.swift`, including the delegate — which is not
/// optional and is the bug this repo has already paid for once:
///
/// **Without a `UNUserNotificationCenterDelegate` returning a presentation option from
/// `willPresent`, the system silently swallows any notification posted while the app is
/// frontmost.** On macOS, and in this app's foreground-only build on iOS, frontmost is very often
/// the only moment a completion can fire — so with no delegate the feature simply does not exist,
/// with no error to explain why.
@MainActor
final class RenderNotifier: NSObject {

    private let center = UNUserNotificationCenter.current()
    private var isAuthorised = false
    private var hasAsked = false

    /// Called at launch. Installs the delegate only — it does NOT ask for permission.
    func install() {
        center.delegate = self
    }

    /// Asked at the first render start, not at launch.
    ///
    /// A permission prompt on first launch, before the user has done anything, is a prompt asking
    /// them to agree to something they have no way to evaluate — and it is the one they deny.
    func requestAuthorisationIfNeeded() async {
        guard !hasAsked else { return }
        hasAsked = true
        // Never under XCTest. The unit-test target uses the app as its TEST_HOST, so a test that
        // enqueues a job would raise a real system alert on the simulator — which then sits there
        // modally, blocking every subsequent launch on that device including the screenshot pass.
        // That is exactly what happened, and it is invisible from a green test log.
        guard !Self.isRunningTests else { return }
        isAuthorised = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    static var isRunningTests: Bool {
        NSClassFromString("XCTestCase") != nil
    }

    /// "Your Scandinavian living room is ready."
    func variationFinished(spaceName: String,
                           styleName: String,
                           projectID: String,
                           outputID: String,
                           remainingInQueue: Int) async {
        guard isAuthorised else { return }

        let content = UNMutableNotificationContent()
        content.title = "AISixteen Architecture"
        content.body = Self.body(spaceName: spaceName,
                                 styleName: styleName,
                                 remainingInQueue: remainingInQueue)
        content.sound = .default
        // Variations of one space group together rather than stacking as N unrelated alerts.
        content.threadIdentifier = projectID
        content.userInfo = ["projectID": projectID, "outputID": outputID]

        let request = UNNotificationRequest(identifier: outputID, content: content, trigger: nil)
        try? await center.add(request)
    }

    /// The completion copy, from the design board, with the queue tail made honest.
    static func body(spaceName: String, styleName: String, remainingInQueue: Int) -> String {
        let head = "Your \(styleName.lowercased()) \(spaceName.lowercased()) is ready."
        switch remainingInQueue {
        case 0: return head
        case 1: return head + " One more on the way."
        default: return head + " \(remainingInQueue) more on the way."
        }
    }

    /// Everything this app will never post.
    ///
    /// There is no progress notification, ever. A notification that says "step 18 of 32" is a
    /// notification the user cannot act on, posted repeatedly, about something they can already
    /// see in the Live Activity.
    func clearDelivered(for projectID: String) {
        center.getDeliveredNotifications { notifications in
            let ids = notifications
                .filter { $0.request.content.threadIdentifier == projectID }
                .map(\.request.identifier)
            Task { @MainActor in
                UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids)
            }
        }
    }
}

extension RenderNotifier: UNUserNotificationCenterDelegate {

    /// THE fix. Without this, a completion that fires while the app is frontmost is dropped.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    /// Tapping opens that variation's Result.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        guard let projectID = info["projectID"] as? String else { return }
        let outputID = info["outputID"] as? String
        await MainActor.run {
            NotificationCenter.default.post(name: .arcOpenResult,
                                            object: nil,
                                            userInfo: ["projectID": projectID,
                                                       "outputID": outputID as Any])
        }
    }
}

extension Notification.Name {
    static let arcOpenResult = Notification.Name("arc.openResult")
}

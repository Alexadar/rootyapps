import Foundation
import UserNotifications
import SpaceWeatherFeed

/// Evaluates the alert engine for a fresh snapshot and posts local notifications.
/// Called from every refresh path — the foreground store (iOS + macOS) and the iOS
/// background task — so an event caught while the app is open notifies too.
enum AlertNotifier {

    /// Without a delegate the system swallows notifications posted while the app is
    /// frontmost — which on macOS is the only moment they can fire at all. Install at
    /// launch so a storm that arrives while you're watching the dashboard still alerts.
    private final class Presenter: NSObject, UNUserNotificationCenterDelegate {
        func userNotificationCenter(_ center: UNUserNotificationCenter,
                                    willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions { [.banner, .sound, .list] }
    }
    private static let presenter = Presenter()

    static func start() {
        UNUserNotificationCenter.current().delegate = presenter
    }

    static func handle(_ snapshot: SpaceWeatherSnapshot) {
        let shared = SharedStore()
        let prefs = shared.alertPrefs
        guard prefs.enabled else { return }
        let result = SpaceAlerts.evaluate(current: snapshot, prefs: prefs, state: shared.alertState)
        shared.alertState = result.state
        guard !result.alerts.isEmpty else { return }

        let center = UNUserNotificationCenter.current()
        for alert in result.alerts {
            let content = UNMutableNotificationContent()
            content.title = alert.title
            content.body = alert.body
            content.sound = .default
            content.threadIdentifier = alert.kind.rawValue
            center.add(UNNotificationRequest(identifier: "\(alert.kind.rawValue).\(UUID().uuidString)",
                                             content: content, trigger: nil))
        }
    }

    /// Called when the user flips the master Alerts toggle on.
    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])) ?? false
    }
}

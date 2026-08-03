import Foundation
import UserNotifications
import SpaceWeatherFeed
import GeomagKit
import AuroraKit

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
            let text = render(alert)
            content.title = text.title
            content.body = text.body
            content.sound = .default
            content.threadIdentifier = alert.kind.rawValue
            center.add(UNNotificationRequest(identifier: "\(alert.kind.rawValue).\(UUID().uuidString)",
                                             content: content, trigger: nil))
        }
    }

    /// Turns alert DATA into sentences in the user's chosen language.
    ///
    /// This runs in the background task, where there is no view and therefore no `\.locale`
    /// environment — so the language is read from the app group and passed to every lookup
    /// explicitly, as a bundle plus a locale.
    private static func render(_ alert: SpaceAlert) -> (title: String, body: String) {
        // SWText.str resolves against the app-group language (bundle picks the localization,
        // locale formats the numbers inside it) — the same path the UI uses.
        let t = SWText.str

        // Every geomagnetic alert LEADS WITH THE NUMBER. A notification is read at a glance on a
        // lock screen, and "Aurora chance 45%" answered a question nobody asked while the measured
        // value — the only thing that says how strong this actually is — was either buried in the
        // body or missing entirely.
        switch alert.detail {
        case let .storm(g, kp):
            let level = SWText.loc(Geomag.gLabel(g))       // "G2 Moderate" → "G2 Mäßig"
            guard let kp else { return (t("\(level) geomagnetic storm"), t("NOAA G\(g) conditions now.")) }
            return (t("Kp \(Fmt.num(kp, 1)) · \(level)"), t("NOAA G\(g) conditions now."))

        case let .flare(maxClass, meaning):
            // maxClass is a code (M4.2) and stays verbatim; the meaning is a catalog key.
            // Untouched: a flare is an X-ray event with no Kp to lead with.
            return (t("\(maxClass) solar flare"), SWText.loc(meaning))

        case let .aurora(probability, kp):
            let lat = Int(Aurora.equatorwardGeomagLatitude(kp: kp).rounded())
            return (t("Kp \(Fmt.num(kp, 1)) · aurora \(probability)%"),
                    t("Visible down to \(lat)° geomagnetic latitude."))
        }
    }

    /// Called when the user flips the master Alerts toggle on.
    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])) ?? false
    }
}

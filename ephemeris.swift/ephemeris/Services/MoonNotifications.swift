import Foundation
import UserNotifications
import EphemerisKit

/// Full and new moon alerts.
///
/// The two paid competitors in this niche — Mooncast and My Moon Phase Pro, both $3.99, ~6,200
/// combined ratings — lead their store pages on alerts rather than on display. This is the feature
/// being bought, not a garnish on the widget.
///
/// ## Permission is never requested at launch
///
/// `UNUserNotificationCenter.requestAuthorization` presents a system alert, and this app's rule is
/// that nothing auto-presents on launch — the home screen teaches the ways in and every modal opens
/// from a tap. So authorization is requested from an explicit toggle in Settings and nowhere else.
/// A user who never opens Settings is never asked, which is the intended outcome.
///
/// ## Why the trigger carries a time zone
///
/// A full moon is an **absolute instant**: it happens at the same moment for everyone, and clocks
/// changing does not move it. Two of the three obvious ways to schedule that are wrong.
///
/// - `UNTimeIntervalNotificationTrigger(timeInterval:)` looks right, and drifts: the offset is
///   computed once and the event may be months out.
/// - `UNCalendarNotificationTrigger` with *local* components fires at a wall-clock time. Schedule a
///   full moon that falls at 02:30 on the far side of a daylight-saving change and it arrives an
///   hour early or an hour late, because 02:30 local is no longer the instant it was.
///
/// So the components are derived in **UTC** and carry `timeZone` explicitly. The system then
/// resolves them back to the one instant that is actually correct, whatever the device's clock is
/// doing. This is the same class of defect that cost a debugging round in `RiseSet`.
@MainActor
final class MoonNotifications: ObservableObject {

    /// Persisted so the toggle survives relaunch. Authorization itself lives with the system —
    /// this only records what the user asked for.
    @Published var enabled: Bool {
        didSet {
            guard oldValue != enabled else { return }
            UserDefaults.standard.set(enabled, forKey: Self.key)
            Task { enabled ? await refresh() : cancelAll() }
        }
    }

    /// Nil until asked. Not requested on init — see the type comment.
    @Published private(set) var authorization: UNAuthorizationStatus?

    // `nonisolated` on the constants the pure helpers read. The class is @MainActor, so its
    // statics inherit that isolation, and `schedule`/`components`/`content` are deliberately
    // nonisolated so tests can call them without a main-actor hop. Swift 6 makes the mismatch an
    // error rather than a warning — these are immutable `let`s, so the isolation buys nothing.
    private nonisolated static let key = "moon.notifications.enabled"
    private nonisolated static let idPrefix = "eph.moon."

    /// iOS keeps at most 64 pending local notifications per app and silently drops the rest, so
    /// this schedules a rolling window and tops it up rather than trying to cover a year. Twelve
    /// is about six months of full and new moons — far enough ahead that a user who opens the app
    /// even twice a year never sees a gap, and well clear of the cap for anything else added later.
    nonisolated static let horizon = 12

    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
        self.enabled = UserDefaults.standard.bool(forKey: Self.key)
    }

    // MARK: - The pure part

    /// Which instants to notify about, and what each one says.
    ///
    /// Separated from every `UNUserNotificationCenter` call so it can be tested without a
    /// notification centre, a device, or a granted permission.
    nonisolated static func schedule(from date: Date, limit: Int = horizon) -> [(event: MoonPhases.Event, id: String)] {
        MoonPhases.upcoming([.full, .new], from: date, limit: limit)
            .map { ($0, idPrefix + String(Int($0.date.timeIntervalSince1970))) }
    }

    /// UTC components for an absolute instant, with the zone attached.
    ///
    /// Dropping `timeZone` here is the daylight-saving bug described in the type comment, and it is
    /// invisible for most of the year.
    nonisolated static func components(for date: Date) -> DateComponents {
        var cal = Calendar(identifier: .gregorian)
        let utc = TimeZone(secondsFromGMT: 0)!
        cal.timeZone = utc
        var c = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        c.timeZone = utc
        return c
    }

    nonisolated static func content(for event: MoonPhases.Event) -> UNMutableNotificationContent {
        let c = UNMutableNotificationContent()
        let sign = event.sign.name
        switch event.phase {
        case .full:
            c.title = String(localized: "Full Moon")
            c.body = String(localized: "The Moon is full in \(sign).")
        default:
            c.title = String(localized: "New Moon")
            c.body = String(localized: "The Moon is new in \(sign).")
        }
        c.sound = .default
        return c
    }

    // MARK: - The system part

    func readAuthorization() async {
        authorization = await center.notificationSettings().authorizationStatus
    }

    /// Asks the system, then schedules. Returns whether alerts are actually usable afterwards, so
    /// the toggle can fall back rather than sit on while nothing arrives.
    @discardableResult
    func requestAndEnable() async -> Bool {
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        await readAuthorization()
        if granted {
            enabled = true
            await refresh()
        } else {
            enabled = false
        }
        return granted
    }

    /// Rebuild the pending set. Cheap and idempotent — call it on foreground, because the window
    /// only rolls forward as events pass.
    func refresh(now: Date = .now) async {
        guard enabled else { return }
        await readAuthorization()
        guard authorization == .authorized || authorization == .provisional else { return }

        cancelAll()
        for (event, id) in Self.schedule(from: now) {
            let trigger = UNCalendarNotificationTrigger(dateMatching: Self.components(for: event.date),
                                                        repeats: false)
            // A single rejected request must not abandon the rest of the window — a malformed
            // trigger for one lunation would otherwise silently cost every later alert too.
            try? await center.add(UNNotificationRequest(identifier: id,
                                                        content: Self.content(for: event),
                                                        trigger: trigger))
        }
    }

    /// Removes only this feature's requests, matched by prefix. A blanket
    /// `removeAllPendingNotificationRequests()` would also delete anything a later feature adds.
    func cancelAll() {
        center.getPendingNotificationRequests { requests in
            let mine = requests.map(\.identifier).filter { $0.hasPrefix(Self.idPrefix) }
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: mine)
        }
    }
}

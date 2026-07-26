#if os(iOS) || os(watchOS)
import Foundation
import WatchConnectivity
import WidgetKit
import SpaceWeatherFeed

/// Mirrors the two UI preferences to the watch. App groups are per-device, so the phone's
/// Night/Simple choice cannot reach the wrist through `AppGroup.defaults` — this is the
/// only channel that crosses. Data is deliberately NOT sent: the watch fetches NOAA itself
/// and is standalone-capable, so shipping a snapshot over would just duplicate that.
///
/// `updateApplicationContext` (not `sendMessage`) because this is state, not an event: it
/// keeps only the latest value and delivers it whenever the counterpart next wakes, so a
/// watch that was off still comes up in the right theme.
final class WatchSync: NSObject, WCSessionDelegate {
    static let shared = WatchSync()

    private var session: WCSession? { WCSession.isSupported() ? .default : nil }

    func start() {
        guard let session else { return }
        session.delegate = self
        session.activate()
    }

    /// Phone side: push the current choices. Cheap and idempotent, so it can be called on
    /// every change without bookkeeping.
    func push(theme: String, mode: String) {
        guard let session, session.activationState == .activated else { return }
        try? session.updateApplicationContext([SharedStore.Key.theme: theme,
                                               SharedStore.Key.mode: mode])
    }

    /// Watch side: land the values in this device's own app-group container, which is what
    /// the watch UI and its complications already read.
    func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        let shared = SharedStore()
        if let theme = context[SharedStore.Key.theme] as? String { shared.themeRaw = theme }
        if let mode = context[SharedStore.Key.mode] as? String { shared.modeRaw = mode }
        WidgetCenter.shared.reloadAllTimelines()
    }

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState,
                 error: Error?) {}

    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}
    /// The user switched watches — reactivate so the new one gets the current choices.
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    #endif
}
#endif

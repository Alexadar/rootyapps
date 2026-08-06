import Foundation
#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

/// Phone → watch delivery of a measurement session.
///
/// ## Receive, never capture
///
/// The watch shows measured values and never produces them. A wrist mic at hip height under a sleeve
/// is not a measurement this app can stand behind; sustained capture is expensive for a worse answer
/// than the phone sitting in the same room; and a live meter has no crown target, so it would be the
/// first watch screen to break `CrownFocusChecks`. Tap tempo already gets BPM more reliably than a
/// microphone would.
///
/// ## One direction, one payload
///
/// The phone sends the whole `Codable` session; the watch replaces whatever it had. There is no merge,
/// no partial update and no watch→phone path — all three would be state to reason about in exchange
/// for nothing a user asked for.
///
/// `applicationContext` rather than `sendMessage`: it is the one API that keeps the latest value for a
/// watch that was asleep, unreachable or not yet launched, which is the normal case. `sendMessage`
/// would require both apps foregrounded and would simply fail the rest of the time.
@MainActor
final class SessionTransport: NSObject, ObservableObject {

    /// The most recent session this device knows about. On the watch this is the whole feature.
    @Published private(set) var received: MeasurementStore.Session?

    static let shared = SessionTransport()

    private override init() {
        super.init()
    }

    /// Wire up the session. Safe to call on every platform and every launch — where WatchConnectivity
    /// is unavailable or unsupported (Mac, iPad without a paired watch) it does nothing at all.
    func activate() {
        #if canImport(WatchConnectivity)
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        // A watch launched after the phone measured still needs the value.
        adopt(session.receivedApplicationContext)
        #endif
    }

    /// Phone side: publish the session. Replaces any previous context, which is the intent — the watch
    /// should show the latest measurement, not a queue of old ones.
    func send(_ session: MeasurementStore.Session?) {
        #if canImport(WatchConnectivity)
        guard WCSession.isSupported() else { return }
        let wc = WCSession.default
        guard wc.activationState == .activated else { return }
        do {
            guard let session else {
                try wc.updateApplicationContext([:])   // cleared on the phone → cleared on the wrist
                return
            }
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(session)
            try wc.updateApplicationContext(["session": data])
        } catch {
            // A failed transfer must not take the app with it: the phone still has the measurement,
            // and the wrist simply does not show one.
            #if DEBUG
            print("SessionTransport: \(error.localizedDescription)")
            #endif
        }
        #endif
    }

    /// Test/seed path, and the one the watch UI tests use: no pairing, no phone, no framework.
    func adopt(_ session: MeasurementStore.Session?) { received = session }

    private func adopt(_ context: [String: Any]) {
        guard let data = context["session"] as? Data else {
            received = nil
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        received = try? decoder.decode(MeasurementStore.Session.self, from: data)
    }
}

#if canImport(WatchConnectivity)
extension SessionTransport: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState,
                             error: Error?) {
        let context = session.receivedApplicationContext
        Task { @MainActor in self.adopt(context) }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        Task { @MainActor in self.adopt(context) }
    }

    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { WCSession.default.activate() }
    #endif
}
#endif

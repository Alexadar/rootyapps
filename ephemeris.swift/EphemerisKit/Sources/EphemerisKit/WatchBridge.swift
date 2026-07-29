#if os(iOS) || os(watchOS)
import Foundation
import WatchConnectivity

/// Carries preferences between the phone and the watch.
///
/// This exists because `AppGroup` cannot do it. An app group is shared between an app and its
/// extensions **on one device**; it does not span the pairing. Without this channel the watch
/// reads its own empty container, finds no observer position, and the Ascendant and house cusps
/// are simply undefined — which looks like a bug in the astronomy rather than a missing setting.
///
/// Only preferences cross. Positions, aspects and cusps are deliberately not sent: the watch runs
/// the same EphemerisKit and recomputes them in microseconds, so shipping a snapshot over would
/// buy nothing and add a staleness bug.
///
/// `updateApplicationContext` rather than `sendMessage`, because this is *state*, not an event:
/// it keeps only the latest value and delivers it whenever the counterpart next wakes, so a watch
/// that was off still comes up with the right place.
public final class WatchBridge: NSObject, WCSessionDelegate {
    public static let shared = WatchBridge()

    private var session: WCSession? { WCSession.isSupported() ? .default : nil }

    public func start() {
        guard let session else { return }
        session.delegate = self
        session.activate()
    }

    /// Phone side. Cheap and idempotent, so it can be called on every change without bookkeeping.
    public func push(location: GeoLocation?, languageCode: String, houseSystem: HouseSystem) {
        guard let session, session.activationState == .activated else { return }
        var context: [String: Any] = [
            SharedStore.Key.language: languageCode,
            SharedStore.Key.houseSystem: houseSystem.rawValue,
        ]
        if let location {
            context[SharedStore.Key.latitude]  = location.latitude
            context[SharedStore.Key.longitude] = location.longitude
            context[SharedStore.Key.placeName] = location.name ?? ""
        }
        try? session.updateApplicationContext(context)
    }

    /// Watch side. Lands the values in this device's own app-group container, which is what the
    /// watch UI and its complications already read.
    public func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        let store = SharedStore()
        if let code = context[SharedStore.Key.language] as? String { store.write(languageCode: code) }
        if let raw = context[SharedStore.Key.houseSystem] as? String,
           let system = HouseSystem(rawValue: raw) { store.write(houseSystem: system) }
        if let lat = context[SharedStore.Key.latitude] as? Double,
           let lon = context[SharedStore.Key.longitude] as? Double {
            let name = context[SharedStore.Key.placeName] as? String
            store.write(location: GeoLocation(latitude: lat, longitude: lon,
                                              name: (name?.isEmpty ?? true) ? nil : name))
        }
        NotificationCenter.default.post(name: .ephemerisSharedStoreChanged, object: nil)
    }

    public func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState,
                        error: Error?) {}
    #if os(iOS)
    public func sessionDidBecomeInactive(_ session: WCSession) {}
    public func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    #endif
}

public extension Notification.Name {
    /// Posted on the watch when the phone's preferences land, so the UI can recompute.
    static let ephemerisSharedStoreChanged = Notification.Name("ephemerisSharedStoreChanged")
}
#endif

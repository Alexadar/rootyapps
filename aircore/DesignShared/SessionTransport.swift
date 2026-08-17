import Foundation
import Observation
#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

/// The last state the phone solved, as the wrist needs it.
///
/// A flat value with no behaviour: it crosses a process boundary, so anything clever in it is a
/// decoding failure waiting to happen on a version mismatch.
public struct WristState: Codable, Equatable, Sendable {
    public var dryBulb: Double            // °C
    public var relativeHumidity: Double   // 0…1
    public var wetBulb: Double            // °C
    public var dewPoint: Double?          // °C, absent for perfectly dry air
    public var enthalpy: Double           // kJ/kg dry air
    public var pressure: Double           // Pa
    public var unitSystem: String
    public var capturedAt: Date

    public init(dryBulb: Double, relativeHumidity: Double, wetBulb: Double, dewPoint: Double?,
                enthalpy: Double, pressure: Double, unitSystem: String, capturedAt: Date) {
        self.dryBulb = dryBulb
        self.relativeHumidity = relativeHumidity
        self.wetBulb = wetBulb
        self.dewPoint = dewPoint
        self.enthalpy = enthalpy
        self.pressure = pressure
        self.unitSystem = unitSystem
        self.capturedAt = capturedAt
    }
}

/// Phone → watch delivery of the last solved state.
///
/// ## Receive, never capture
///
/// The watch shows a state the phone computed and runs its own crown conversion; it never sends
/// anything back. One direction means there is no merge to reason about, no conflict, and no way
/// for a stale wrist to overwrite the phone.
///
/// ## `applicationContext`, not `sendMessage`
///
/// `applicationContext` keeps the latest value for a watch that was asleep, unreachable, or has
/// not been launched yet — which is the normal case for a tool you glance at. `sendMessage` needs
/// both apps foregrounded and simply fails the rest of the time.
///
/// ## Still offline
///
/// WatchConnectivity is a local link between two devices in the same pocket. Nothing here reaches
/// a network, and the app behaves identically in Airplane Mode.
@Observable
public final class SessionTransport: NSObject {

    /// The most recent state this device knows about. On the watch, this is the whole feature.
    public private(set) var received: WristState?

    public static let shared = SessionTransport()

    private override init() {
        super.init()
        activate()
    }

    #if canImport(WatchConnectivity)
    private var session: WCSession? {
        WCSession.isSupported() ? .default : nil
    }
    #endif

    private func activate() {
        #if canImport(WatchConnectivity)
        guard let session else { return }
        session.delegate = self
        session.activate()
        if let stored = decode(session.receivedApplicationContext) {
            received = stored
        }
        #endif
    }

    /// Send the current state to the wrist. Cheap enough to call whenever a state changes:
    /// `updateApplicationContext` replaces the pending payload rather than queuing another.
    public func send(_ state: WristState) {
        #if canImport(WatchConnectivity)
        guard let session, session.activationState == .activated else { return }
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? session.updateApplicationContext(["state": data])
        #endif
    }

    private func decode(_ context: [String: Any]) -> WristState? {
        guard let data = context["state"] as? Data else { return nil }
        return try? JSONDecoder().decode(WristState.self, from: data)
    }
}

#if canImport(WatchConnectivity)
extension SessionTransport: WCSessionDelegate {

    public func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState,
                        error: Error?) {
        guard error == nil else { return }
        if let stored = decode(session.receivedApplicationContext) {
            Task { @MainActor in self.received = stored }
        }
    }

    public func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        guard let state = decode(context) else { return }
        Task { @MainActor in self.received = state }
    }

    #if os(iOS)
    public func sessionDidBecomeInactive(_ session: WCSession) {}
    public func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    #endif
}
#endif

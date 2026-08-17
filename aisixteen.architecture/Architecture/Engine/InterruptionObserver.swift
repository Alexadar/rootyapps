import Foundation
import RedesignKit
#if os(iOS)
import UIKit
import CallKit
#endif

/// Turns platform notifications into reducer events.
///
/// This is the thin, untestable layer — deliberately thin, because everything it produces is an
/// `Event` that a test can send directly. `InterruptibleRedesignGenerator` publishes through the
/// same `EnvironmentEventSink`, so the entire pause path is exercised with no device.
@MainActor
final class InterruptionObserver {

    private weak var sink: (any EnvironmentEventSink)?
    private var observers: [NSObjectProtocol] = []
    private var isRunning = false

    #if os(iOS)
    private let callObserver = CXCallObserver()
    private var callDelegate: CallDelegate?
    #endif

    init(sink: any EnvironmentEventSink) {
        self.sink = sink
    }

    /// Start watching. Called when the first job starts, not at launch.
    ///
    /// Battery monitoring in particular costs power, so it is on only while there is a render to
    /// protect — turning it on at launch would drain the battery of a user who never generated
    /// anything, to guard against a low battery.
    func start() {
        guard !isRunning else { return }
        isRunning = true

        observeThermal()
        observePower()
        #if os(iOS)
        observeCalls()
        UIDevice.current.isBatteryMonitoringEnabled = true
        observeBattery()
        #endif

        // The initial read is not optional. `thermalStateDidChangeNotification` fires only on a
        // CHANGE, so a device that is already hot when the render starts sends nothing at all, and
        // the app happily runs a three-minute job on a phone that is about to throttle. Same story
        // for the battery.
        publishThermal()
        publishPower()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        #if os(iOS)
        callDelegate = nil
        callObserver.setDelegate(nil, queue: nil)
        UIDevice.current.isBatteryMonitoringEnabled = false
        #endif
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    // ── thermal ──────────────────────────────────────────────────────────────────────────────

    private func observeThermal() {
        let token = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.publishThermal() }
            }
        observers.append(token)
    }

    private func publishThermal() {
        sink?.publish(.thermalChanged(Self.level(ProcessInfo.processInfo.thermalState)))
    }

    /// Thermal pressure is OBSERVED, never predicted. The app does not guess that a render will
    /// make the phone hot; it notices that it has, and slows down.
    ///
    /// `.nominal` and `.fair` collapse to one level because they mean the same thing here: nothing
    /// to say. `.serious` degrades and keeps going — which is exactly what the pause card's
    /// "Running slower to keep the phone cool" claims. Only `.critical` stops the work.
    static func level(_ state: ProcessInfo.ThermalState) -> ThermalLevel {
        switch state {
        case .nominal, .fair: return .nominal
        case .serious: return .elevated
        case .critical: return .critical
        @unknown default: return .nominal
        }
    }

    // ── power ────────────────────────────────────────────────────────────────────────────────

    private func observePower() {
        let token = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange,
            object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.publishPower() }
            }
        observers.append(token)
    }

    #if os(iOS)
    private func observeBattery() {
        for name in [UIDevice.batteryLevelDidChangeNotification,
                     UIDevice.batteryStateDidChangeNotification] {
            let token = NotificationCenter.default.addObserver(
                forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.publishPower() }
                }
            observers.append(token)
        }
    }
    #endif

    private func publishPower() {
        sink?.publish(.powerChanged(Self.batterySnapshot()))
    }

    static func batterySnapshot() -> BatterySnapshot {
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        #if os(iOS)
        let device = UIDevice.current
        let state = device.batteryState
        // A level of -1 means the system has no reading. Pausing a render on a number the system
        // said it does not have would stop every render in the Simulator.
        let unknown = state == .unknown || device.batteryLevel < 0
        return BatterySnapshot(level: Double(device.batteryLevel),
                               isCharging: state == .charging || state == .full,
                               isUnknown: unknown,
                               lowPowerMode: lowPower)
        #else
        // macOS: no low-battery pause. A laptop battery could be read through IOKit, but stopping
        // a Mac render at 10% is behaviour Mac users would call broken, and Macs are usually
        // plugged in. The reducer keeps the case — it is platform-free and tested on both — and
        // only the observer is silent here.
        return BatterySnapshot(level: 1, isCharging: true, isUnknown: true, lowPowerMode: lowPower)
        #endif
    }

    // ── calls ────────────────────────────────────────────────────────────────────────────────

    #if os(iOS)
    /// `CXCallObserver` needs no entitlement, shows no permission prompt and requires no
    /// Info.plist key — it is read-only observation of the call state, nothing more.
    private func observeCalls() {
        let delegate = CallDelegate { [weak self] active in
            self?.sink?.publish(.callChanged(active: active))
        }
        callDelegate = delegate
        callObserver.setDelegate(delegate, queue: .main)
        // Same reason as the thermal read: starting a render mid-call must pause immediately, and
        // the delegate only fires on a change.
        let active = callObserver.calls.contains { !$0.hasEnded }
        sink?.publish(.callChanged(active: active))
    }

    private final class CallDelegate: NSObject, CXCallObserverDelegate {
        private let onChange: @MainActor (Bool) -> Void

        init(onChange: @escaping @MainActor (Bool) -> Void) {
            self.onChange = onChange
        }

        func callObserver(_ observer: CXCallObserver, callChanged call: CXCall) {
            let active = observer.calls.contains { !$0.hasEnded }
            MainActor.assumeIsolated { onChange(active) }
        }
    }
    #endif
}

#if os(macOS)
/// Keeps a Mac awake for the length of a render.
///
/// macOS never suspends a foreground app the way iOS does, but it will happily sleep the machine
/// partway through three minutes of Neural Engine work. `beginActivity` is the sanctioned way to
/// say "this is user-initiated and it is not finished", and it is released the moment the queue
/// empties so the Mac is not held awake by a render that ended ten minutes ago.
@MainActor
final class SleepAssertion {
    private var token: (any NSObjectProtocol)?

    func begin() {
        guard token == nil else { return }
        token = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled],
            reason: "Rendering a redesign")
    }

    func end() {
        guard let token else { return }
        ProcessInfo.processInfo.endActivity(token)
        self.token = nil
    }

    deinit {
        if let token { ProcessInfo.processInfo.endActivity(token) }
    }
}
#endif

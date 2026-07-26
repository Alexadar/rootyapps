import Foundation
import Network

/// The current network path, so a refresh can say *why* it didn't happen instead of failing
/// silently. Before this, "offline" was inferred from all seven fetches throwing, which made a
/// dead radio and seven dead feeds indistinguishable — and left no way to honour a
/// "don't use cellular" preference deliberately rather than by letting requests fail.
///
/// Cheap enough to keep running: one `NWPathMonitor` per process (app, widget, watch, background
/// task each get their own).
public final class NetworkMonitor: @unchecked Sendable {
    public static let shared = NetworkMonitor()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "eartharound.network-monitor")
    private let lock = NSLock()
    private var path: NWPath?

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            lock.lock(); self.path = path; lock.unlock()
        }
        monitor.start(queue: queue)
    }

    private var current: NWPath? { lock.lock(); defer { lock.unlock() }; return path }

    /// Optimistic until the first path arrives — a monitor that has not reported yet must not
    /// block the launch fetch.
    public var isOnline: Bool {
        guard let current else { return true }
        return current.status == .satisfied
    }

    /// Cellular or a personal hotspot — what a "use cellular data" preference is about.
    public var isExpensive: Bool { current?.isExpensive ?? false }

    /// Low Data Mode.
    public var isConstrained: Bool { current?.isConstrained ?? false }

    /// The reason a fetch should be skipped, or nil to go ahead.
    public func blockedReason(cellularAllowed: Bool) -> FetchOutcome? {
        if !isOnline { return .skippedOffline }
        if isExpensive && !cellularAllowed { return .skippedCellular }
        return nil
    }
}

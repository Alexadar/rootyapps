import Foundation

/// Turns a series of (time, bytes-so-far) samples into a rate that is stable enough to display.
///
/// The naive rate — bytes since the last callback divided by elapsed time — is unusable: Background
/// Assets delivers progress in bursts, so it swings between zero and impossible several times a
/// second and the label becomes a strobe. This smooths with an exponential moving average, which is
/// still an honest measurement of what actually arrived; it is a filter over real data, not an
/// invented number.
///
/// Deliberately a value type with no clock of its own — the caller supplies timestamps, so the
/// whole thing is testable without waiting.
public struct TransferRateEstimator: Sendable, Equatable {

    /// Weight of the newest sample. 0.3 settles within a couple of seconds while still following a
    /// genuine change in connection speed.
    public let smoothing: Double
    /// Samples closer together than this are ignored; two callbacks in the same millisecond produce
    /// a division by almost zero and a nonsense spike.
    public let minimumInterval: TimeInterval

    private var lastTime: TimeInterval?
    private var lastBytes: Int64?
    private var average: Double?

    public init(smoothing: Double = 0.3, minimumInterval: TimeInterval = 0.25) {
        self.smoothing = smoothing
        self.minimumInterval = minimumInterval
    }

    /// The current estimate in bytes per second, or `nil` until there is something real to report.
    public var bytesPerSecond: Double? { average }

    /// Feed one observation. `time` is any monotonically increasing seconds value.
    public mutating func record(bytes: Int64, at time: TimeInterval) {
        defer {
            // Always remember the newest observation, even when it was too close to use as a
            // sample — otherwise a burst of fast callbacks makes the next interval look longer
            // than it was and the rate reads low.
            lastTime = time
            lastBytes = bytes
        }
        guard let previousTime = lastTime, let previousBytes = lastBytes else { return }
        let elapsed = time - previousTime
        guard elapsed >= minimumInterval else { return }
        let delta = bytes - previousBytes
        // A download that restarts reports fewer bytes than last time. That is not a negative rate.
        guard delta >= 0 else {
            average = nil
            return
        }
        let instant = Double(delta) / elapsed
        average = average.map { $0 + smoothing * (instant - $0) } ?? instant
    }

    /// Called when the download pauses. The last known rate describes a connection that is no
    /// longer transferring, and showing it beside a stalled bar is a lie.
    public mutating func stall() { average = nil }

    /// Seconds of work left at the current rate, or `nil` if that cannot be said yet.
    public func secondsRemaining(completed: Int64, total: Int64) -> TimeInterval? {
        guard let rate = average, rate > 0, total > completed else { return nil }
        return Double(total - completed) / rate
    }
}

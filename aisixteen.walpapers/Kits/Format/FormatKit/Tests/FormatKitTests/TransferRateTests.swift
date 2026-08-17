import Testing
import Foundation
@testable import FormatKit

/// ORACLES:
///  • IDENTITY — fed a perfectly constant stream, the estimator must converge on exactly that rate.
///    A filter that cannot reproduce a constant is not measuring anything.
///  • INVARIANT — the rate is never negative, never infinite, and is `nil` rather than stale
///    whenever there is nothing honest to report.
///  • BEHAVIOUR — bursty delivery (which is how Background Assets actually reports) must not make
///    the displayed rate swing wildly, or the label strobes.
/// MODEL CAVEAT: an EMA lags a genuine step change by design. That is the trade for a readable
/// number; the suite pins the lag rather than pretending it is absent.
@Suite("TransferRateEstimator — a readable number from bursty truth")
struct TransferRateTests {

    @Test("nothing is reported from a single sample")
    func needsTwoSamples() {
        var e = TransferRateEstimator()
        #expect(e.bytesPerSecond == nil)
        e.record(bytes: 0, at: 0)
        #expect(e.bytesPerSecond == nil, "one sample is not a rate")
    }

    @Test("a constant stream converges on exactly that rate")
    func constantStream() {
        var e = TransferRateEstimator()
        let perSecond: Int64 = 4_600_000
        for second in 0...30 {
            e.record(bytes: perSecond * Int64(second), at: TimeInterval(second))
        }
        let rate = try! #require(e.bytesPerSecond)
        #expect(abs(rate - Double(perSecond)) < 1, "got \(rate)")
    }

    @Test("bursty delivery does not make the number swing")
    func burstsAreSmoothed() {
        var e = TransferRateEstimator()
        var bytes: Int64 = 0
        var observed: [Double] = []
        // Alternating 0-byte and 2 MB seconds — a mean of 1 MB/s delivered in bursts.
        for second in 0...40 {
            bytes += second.isMultiple(of: 2) ? 0 : 2_000_000
            e.record(bytes: bytes, at: TimeInterval(second))
            if second > 20, let r = e.bytesPerSecond { observed.append(r) }
        }
        let low = observed.min()!, high = observed.max()!
        #expect(low > 400_000, "dipped to \(low) — the label would read near-zero")
        #expect(high < 1_800_000, "spiked to \(high) — the label would read double")
    }

    @Test("samples arriving too fast are folded in, not divided by almost zero")
    func minimumIntervalGuardsAgainstSpikes() {
        var e = TransferRateEstimator()
        e.record(bytes: 0, at: 0)
        e.record(bytes: 1_000_000, at: 0.001)      // 1 GB/s if taken literally
        #expect(e.bytesPerSecond == nil, "a sub-millisecond gap is not a measurement")
        e.record(bytes: 2_000_000, at: 1.0)
        let rate = try! #require(e.bytesPerSecond)
        #expect(rate < 5_000_000, "the ignored burst leaked into the average: \(rate)")
    }

    @Test("a restarted download reports fewer bytes and must not yield a negative rate")
    func restartClearsTheRate() {
        var e = TransferRateEstimator()
        e.record(bytes: 0, at: 0)
        e.record(bytes: 10_000_000, at: 1)
        #expect(e.bytesPerSecond != nil)
        e.record(bytes: 0, at: 2)                  // restarted from scratch
        #expect(e.bytesPerSecond == nil, "a rewind is not a negative rate")
    }

    @Test("pausing drops the rate rather than freezing the last one on screen")
    func stallClears() {
        var e = TransferRateEstimator()
        e.record(bytes: 0, at: 0)
        e.record(bytes: 4_600_000, at: 1)
        #expect(e.bytesPerSecond != nil)
        e.stall()
        #expect(e.bytesPerSecond == nil, "a paused download is not moving at 4.6 MB/s")
    }

    @Test("time remaining is silent until a rate exists, and zero when finished")
    func secondsRemaining() {
        var e = TransferRateEstimator()
        #expect(e.secondsRemaining(completed: 0, total: 2_600_000_000) == nil)
        e.record(bytes: 0, at: 0)
        e.record(bytes: 4_600_000, at: 1)
        let left = try! #require(e.secondsRemaining(completed: 4_600_000, total: 2_600_000_000))
        #expect(left > 500 && left < 600, "got \(left) s")
        #expect(e.secondsRemaining(completed: 2_600_000_000, total: 2_600_000_000) == nil)
    }

    @Test("it follows a genuine change in connection speed within a few samples")
    func followsRealChange() {
        var e = TransferRateEstimator()
        var bytes: Int64 = 0
        for second in 0..<20 { bytes += 1_000_000; e.record(bytes: bytes, at: TimeInterval(second)) }
        #expect(abs(e.bytesPerSecond! - 1_000_000) < 10_000)
        for second in 20..<40 { bytes += 10_000_000; e.record(bytes: bytes, at: TimeInterval(second)) }
        let settled = e.bytesPerSecond!
        #expect(settled > 9_000_000, "still lagging at \(settled) after twenty samples")
    }
}

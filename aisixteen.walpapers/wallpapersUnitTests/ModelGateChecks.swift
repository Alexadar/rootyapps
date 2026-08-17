import XCTest
@testable import Wallpapers

/// The gate's four designed states, plus the failure the design does not have and the app needs.
///
/// Driven through `ModelGate.Event` rather than through `BackgroundAssets`, so the whole machine is
/// covered without a 2.6 GB download. What that leaves untested is one `switch` mapping framework
/// updates onto these events — which is verified on device with `ba-serve`.
@MainActor
final class ModelGateChecks: XCTestCase {

    private typealias Phase = ModelGate.Phase
    private typealias Event = ModelGate.Event

    private func reduce(_ phase: Phase, _ event: Event, wifiOnly: Bool = true) -> Phase {
        ModelGate.reduce(phase, on: event, wifiOnly: wifiOnly)
    }

    // MARK: the designed path

    func testConsentToDownloadingToReady() {
        var phase = Phase.consent
        phase = reduce(phase, .began(total: 2_600_000_000))
        XCTAssertEqual(phase, .downloading(completed: 0, total: 2_600_000_000))

        phase = reduce(phase, .progressed(completed: 1_100_000_000, total: 2_600_000_000))
        XCTAssertEqual(phase, .downloading(completed: 1_100_000_000, total: 2_600_000_000))

        phase = reduce(phase, .finished)
        XCTAssertEqual(phase, .ready)
        XCTAssertTrue(phase.isFinished)
    }

    // MARK: interrupted

    func testPausePreservesTheBytesAlreadyFetched() {
        let downloading = Phase.downloading(completed: 1_100_000_000, total: 2_600_000_000)
        let paused = reduce(downloading, .paused)

        guard case .interrupted(let done, let total, let reason) = paused else {
            return XCTFail("expected the interrupted state, got \(paused)")
        }
        XCTAssertEqual(done, 1_100_000_000, "a pause must not throw away progress")
        XCTAssertEqual(total, 2_600_000_000)
        XCTAssertFalse(reason.isEmpty, "the state must be carried by words, not by colour alone")
    }

    func testPauseReasonNamesWhatItIsWaitingFor() {
        let downloading = Phase.downloading(completed: 10, total: 100)
        if case .interrupted(_, _, let wifi) = reduce(downloading, .paused, wifiOnly: true) {
            XCTAssertTrue(wifi.contains("Wi‑Fi"), "got: \(wifi)")
        } else { XCTFail("expected interrupted") }

        if case .interrupted(_, _, let cellular) = reduce(downloading, .paused, wifiOnly: false) {
            XCTAssertFalse(cellular.contains("Wi‑Fi"), "cellular pause must not blame Wi-Fi: \(cellular)")
        } else { XCTFail("expected interrupted") }
    }

    func testResumingFromInterruptedKeepsGoingRatherThanRestarting() {
        let interrupted = Phase.interrupted(completed: 1_100_000_000,
                                            total: 2_600_000_000,
                                            reason: "Paused — waiting for Wi‑Fi.")
        let resumed = reduce(interrupted, .progressed(completed: 1_200_000_000, total: 2_600_000_000))
        XCTAssertEqual(resumed, .downloading(completed: 1_200_000_000, total: 2_600_000_000))
    }

    func testPausingTwiceDoesNotZeroTheProgress() {
        let once = reduce(.downloading(completed: 500, total: 1000), .paused)
        let twice = reduce(once, .paused)
        XCTAssertEqual(once, twice, "a repeated pause must be idempotent")
    }

    // MARK: bad inputs

    func testProgressBeyondTheTotalIsClampedRatherThanOverflowingTheBar() {
        let phase = reduce(.consent, .progressed(completed: 9_000_000_000, total: 2_600_000_000))
        XCTAssertEqual(phase, .downloading(completed: 2_600_000_000, total: 2_600_000_000))
    }

    func testNegativeProgressIsClampedToZero() {
        let phase = reduce(.consent, .progressed(completed: -10, total: 1000))
        XCTAssertEqual(phase, .downloading(completed: 0, total: 1000))
    }

    // MARK: failure

    func testFailureIsReachableFromEveryState() {
        let states: [Phase] = [
            .consent,
            .downloading(completed: 10, total: 100),
            .interrupted(completed: 10, total: 100, reason: "Paused."),
        ]
        for state in states {
            let failed = reduce(state, .failed(reason: "There isn't enough free space on this device for the model."))
            guard case .failed(let reason) = failed else {
                return XCTFail("no failure path from \(state)")
            }
            XCTAssertFalse(reason.isEmpty)
            XCTAssertFalse(reason.contains("BAError"), "the user must never see a domain: \(reason)")
        }
    }

    // MARK: display

    func testTheDownloadCardShowsRealBytesInOneUnit() {
        let gate = ModelGate()
        gate.apply(.began(total: 2_600_000_000))
        gate.apply(.progressed(completed: 1_100_000_000, total: 2_600_000_000))

        XCTAssertEqual(gate.byteText, "1.1 of 2.6 GB")
        XCTAssertEqual(gate.fraction, 1_100_000_000.0 / 2_600_000_000.0, accuracy: 1e-9)
    }

    func testNoRateIsQuotedBeforeThereIsOneToQuote() {
        let gate = ModelGate()
        gate.apply(.began(total: 2_600_000_000))
        // One sample is not a rate, so the label falls back to naming the connection only.
        XCTAssertEqual(gate.rateText, "Wi‑Fi")
    }

    func testTheGateReportsReadyOnlyWhenItIs() {
        let gate = ModelGate()
        XCTAssertFalse(gate.phase.isFinished, "the gate must not start out satisfied")
        gate.apply(.began(total: 100))
        XCTAssertFalse(gate.phase.isFinished)
        gate.apply(.finished)
        XCTAssertTrue(gate.phase.isFinished)
    }

    func testUsingCellularOnceIsScopedToTheRequest() {
        let gate = ModelGate()
        XCTAssertTrue(gate.wifiOnly, "Wi-Fi only is the default the design specifies")
        gate.wifiOnly = false
        if case .interrupted(_, _, let reason) =
            ModelGate.reduce(.downloading(completed: 1, total: 2), on: .paused, wifiOnly: gate.wifiOnly) {
            XCTAssertFalse(reason.contains("Wi‑Fi"))
        } else { XCTFail("expected interrupted") }
    }
}

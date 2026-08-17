import XCTest
import TarotKit
@testable import Tarot

/// Mock writer: every availability branch and a mid-stream death, no model anywhere near.
@MainActor
final class MockWriter: ReadingWriter {
    var availability: WriterAvailability
    var drafts: [PassageDraft]
    var failAfter: Int?
    /// When set, the stream ends with THIS error instead of MockError (e.g. WriterDeclined).
    var terminalError: Error?

    init(availability: WriterAvailability, drafts: [PassageDraft] = [], failAfter: Int? = nil) {
        self.availability = availability
        self.drafts = drafts
        self.failAfter = failAfter
    }

    struct MockError: Error {}

    func write(reading: Reading, deck: Deck, spread: Spread) -> AsyncThrowingStream<PassageDraft, Error> {
        let drafts = drafts
        let failAfter = failAfter
        let terminalError = terminalError
        return AsyncThrowingStream { continuation in
            Task {
                for (i, draft) in drafts.enumerated() {
                    if let failAfter, i == failAfter {
                        continuation.finish(throwing: terminalError ?? MockError())
                        return
                    }
                    continuation.yield(draft)
                }
                if let terminalError {
                    continuation.finish(throwing: terminalError)
                } else if let failAfter, failAfter >= drafts.count {
                    // "Died mid-response, after everything yielded so far."
                    continuation.finish(throwing: MockError())
                } else {
                    continuation.finish()
                }
            }
        }
    }
}

@MainActor
final class ReadingComposerChecks: XCTestCase {

    private func makeReading() -> Reading {
        Shuffler.draw(deck: .classic1909, spread: .threeCard, seed: 42,
                      allowsReversals: true, date: Date(timeIntervalSince1970: 0))
    }

    private func waitForSettled(_ composer: ReadingComposer) async {
        for _ in 0..<200 {
            switch composer.state {
            case .idle, .writing: try? await Task.sleep(nanoseconds: 10_000_000)
            default: return
            }
        }
    }

    // Each unavailability reason is its own state — three different messages in the UI,
    // asserted separately, never collapsed.
    func testDeviceNotEligibleIsItsOwnState() {
        let composer = ReadingComposer()
        composer.start(reading: makeReading(), deck: .classic1909, spread: .threeCard,
                       writer: MockWriter(availability: .deviceNotEligible))
        XCTAssertEqual(composer.state, .unavailable(.deviceNotEligible))
    }

    func testNotEnabledIsItsOwnState() {
        let composer = ReadingComposer()
        composer.start(reading: makeReading(), deck: .classic1909, spread: .threeCard,
                       writer: MockWriter(availability: .notEnabled))
        XCTAssertEqual(composer.state, .unavailable(.notEnabled))
    }

    func testModelNotReadyIsItsOwnState() {
        let composer = ReadingComposer()
        composer.start(reading: makeReading(), deck: .classic1909, spread: .threeCard,
                       writer: MockWriter(availability: .modelNotReady))
        XCTAssertEqual(composer.state, .unavailable(.modelNotReady))
    }

    func testAvailableStreamsToFinished() async {
        let drafts = [
            PassageDraft(passages: ["First…"], synthesis: nil),
            PassageDraft(passages: ["First…", "Second…"], synthesis: nil),
            PassageDraft(passages: ["First…", "Second…", "Third…"], synthesis: "Together…"),
        ]
        let composer = ReadingComposer()
        composer.start(reading: makeReading(), deck: .classic1909, spread: .threeCard,
                       writer: MockWriter(availability: .available, drafts: drafts))
        await waitForSettled(composer)
        XCTAssertEqual(composer.state, .finished(drafts.last!))
    }

    /// Interrupted mid-response: the partial text survives, the state says it stopped.
    func testMidStreamFailureKeepsThePartial() async {
        let drafts = [
            PassageDraft(passages: ["First…"], synthesis: nil),
            PassageDraft(passages: ["First…", "Sec"], synthesis: nil),
        ]
        let composer = ReadingComposer()
        composer.start(reading: makeReading(), deck: .classic1909, spread: .threeCard,
                       writer: MockWriter(availability: .available, drafts: drafts, failAfter: 2))
        await waitForSettled(composer)
        guard case .failed(let partial) = composer.state else {
            return XCTFail("expected .failed, got \(composer.state)")
        }
        XCTAssertEqual(partial, drafts[1], "the partial that had arrived must survive")
    }

    /// A guardrail decline (both attempts refused) is its own honest state — not a generic
    /// failure, and no canned text stands in for the model.
    func testWriterDeclinedIsItsOwnState() async {
        let writer = MockWriter(availability: .available, drafts: [], failAfter: nil)
        writer.terminalError = WriterDeclined()
        let composer = ReadingComposer()
        composer.start(reading: makeReading(), deck: .classic1909, spread: .threeCard,
                       writer: writer)
        await waitForSettled(composer)
        XCTAssertEqual(composer.state, .declined)
    }

    func testCancelReturnsToIdle() async {
        let composer = ReadingComposer()
        composer.start(reading: makeReading(), deck: .classic1909, spread: .threeCard,
                       writer: MockWriter(availability: .available,
                                          drafts: [PassageDraft(passages: ["x"], synthesis: nil)]))
        composer.cancel()
        XCTAssertEqual(composer.state, .idle)
    }
}

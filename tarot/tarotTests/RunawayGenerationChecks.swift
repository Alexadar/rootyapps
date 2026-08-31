import XCTest
import TarotKit
@testable import Tarot

/// The runaway-generation defences, pinned.
///
/// Reported from a device 2026-08-25: the model produced long, endlessly repeating text, and a
/// second draw then produced nothing at all. One cause — the generation was unbounded, so a
/// repetition loop ran until the context window was exhausted while still holding the model
/// service, which starved the next request.
final class RunawayGenerationChecks: XCTestCase {

    // MARK: The ceiling

    /// `maximumResponseTokens` was left nil, which is what allowed a runaway at all. Every method
    /// must carry a ceiling, and it must leave room for a legitimately full reading.
    func testEveryMethodHasATokenCeiling() {
        for method in Spread.all {
            let cap = WritingLimits.maximumTokens(for: method)
            XCTAssertGreaterThan(cap, 0, "\(method.id) has no ceiling")
            // A token is roughly four characters of English; a full reading must fit with room
            // to spare or the ceiling would truncate good output mid-word.
            let needed = WritingLimits.expectedCharacters(for: method) / 4
            XCTAssertGreaterThan(cap, needed,
                                 "\(method.id): ceiling \(cap) would truncate a full reading (~\(needed) tokens)")
            XCTAssertLessThan(cap, needed * 4,
                              "\(method.id): ceiling \(cap) is so loose it cannot stop a runaway")
        }
    }

    /// Ten brief passages need more room than one long one — a single flat ceiling would either
    /// truncate the Celtic Cross or fail to bound the daily card.
    func testTheCeilingScalesWithTheMethod() {
        XCTAssertLessThan(WritingLimits.maximumTokens(for: .dailyCard),
                          WritingLimits.maximumTokens(for: .celticCross))
        XCTAssertLessThan(WritingLimits.maximumTokens(for: .threeCard),
                          WritingLimits.maximumTokens(for: .crossroads))
    }

    // MARK: The degeneracy test

    /// The exact shape reported: one sentence, over and over.
    func testRepeatedSentenceIsDegenerate() {
        let loop = Array(repeating: "You are in a good place and you feel secure.", count: 6)
            .joined(separator: " ")
        XCTAssertTrue(WritingLimits.isDegenerate(loop, expectedCharacters: 1600))
    }

    /// The other shape: never terminating. Every sentence differs, so a repeat-detector alone
    /// would pass it — length has to be an independent signal.
    func testEndlessButNonRepeatingOutputIsDegenerate() {
        let long = (0..<200).map { "Sentence number \($0) about the card and its meaning." }
            .joined(separator: " ")
        XCTAssertTrue(WritingLimits.isDegenerate(long, expectedCharacters: 1600))
    }

    /// A real reading must survive both checks, or the guard would re-roll good text forever.
    func testARealReadingIsNotDegenerate() {
        let real = """
        This card speaks of stability, wealth, and family. It is a testament to hard work, \
        dedication, and a sense of belonging that brings you peace. It says that you have \
        achieved what you deserve, and that you are surrounded by love and support. You are \
        prosperous, and you feel secure in your accomplishments. This card speaks of change, \
        opportunity, and the unknown. It is a reminder that life is full of surprises, and that \
        there are always new possibilities waiting to be discovered.
        """
        XCTAssertFalse(WritingLimits.isDegenerate(real, expectedCharacters: 1600))
    }

    /// Short repeated fragments are normal prose ("You are." / list items) and must not trip it.
    func testShortRepeatedFragmentsAreTolerated() {
        let fine = "Yes. Yes. Yes. The card speaks of patience and of waiting for the right moment."
        XCTAssertFalse(WritingLimits.isDegenerate(fine, expectedCharacters: 1600))
    }

    /// Boundary: three repeats trip it, two do not. Stated explicitly so a refactor cannot drift
    /// the threshold without a test failing.
    func testTheRepeatThresholdIsThree() {
        let s = "The cards suggest a period of reflection and steady work ahead of you."
        let padding = " Some other sentence entirely, long enough to count as one."
        let twice = [s, s, padding, padding].joined(separator: " ")
        let thrice = [s, s, s, padding].joined(separator: " ")
        XCTAssertFalse(WritingLimits.isDegenerate(twice, expectedCharacters: 4000))
        XCTAssertTrue(WritingLimits.isDegenerate(thrice, expectedCharacters: 4000))
    }
}

/// A new draw must STOP the previous generation, not queue behind it.
///
/// This is the second half of the device bug: the first reading ran away, and the next draw
/// produced nothing because the old request still held the model service. The composer's job is
/// to tear the old stream down before it starts a new one.
final class GenerationCancellationChecks: XCTestCase {

    @MainActor
    func testStartingANewReadingTerminatesThePreviousStream() async {
        let writer = NeverEndingWriter()
        let composer = ReadingComposer()
        let reading = Shuffler.draw(deck: .classic1909, spread: .threeCard, seed: 1,
                                    allowsReversals: false, date: Date(timeIntervalSince1970: 0),
                                    question: nil)
        composer.start(reading: reading, deck: .classic1909, spread: .threeCard, writer: writer)
        for _ in 0..<50 where writer.started == 0 {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(writer.started, 1, "the first generation never began")
        XCTAssertEqual(writer.terminated, 0, "nothing should have stopped it yet")

        // A second draw, exactly as AppModel does it.
        composer.cancel()
        composer.start(reading: reading, deck: .classic1909, spread: .threeCard, writer: writer)
        for _ in 0..<100 where writer.terminated == 0 {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertGreaterThanOrEqual(writer.terminated, 1,
            "the first stream was never terminated — a new draw would queue behind it, which is "
            + "precisely the reported failure")
        XCTAssertEqual(writer.started, 2, "the second generation never began")

        // Stop the second one too. The mock streams forever by design, so leaving it running
        // keeps a task alive after the test returns and the whole suite never exits — which is
        // exactly what happened the first time this test ran.
        composer.cancel()
    }
}

/// Streams forever and records how often it was started and torn down — the mock equivalent of a
/// model stuck in a repetition loop.
@MainActor
private final class NeverEndingWriter: ReadingWriter {
    private(set) var started = 0
    private(set) var terminated = 0
    var availability: WriterAvailability { .available }

    func write(reading: Reading, deck: Deck, spread: Spread) -> AsyncThrowingStream<PassageDraft, Error> {
        started += 1
        return AsyncThrowingStream { continuation in
            let task = Task {
                var draft = PassageDraft(passages: ["", "", ""])
                var n = 0
                while !Task.isCancelled {
                    n += 1
                    draft.passages[0] = String(repeating: "looping ", count: n)
                    continuation.yield(draft)
                    try? await Task.sleep(nanoseconds: 5_000_000)
                }
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
                Task { @MainActor in self.terminated += 1 }
            }
        }
    }
}

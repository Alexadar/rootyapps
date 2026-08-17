import XCTest
import TarotKit
@testable import Tarot

/// The prompt layer over the full method × deck matrix (4 × 3): every combination must
/// name its positions, count itself correctly, carry its deck's tradition, keep the
/// register rules, and never leak a measured-refusal name — whatever the deck calls it.
final class MethodDeckPromptMatrixChecks: XCTestCase {

    private func makeReading(method: Spread, deck: Deck, question: String? = nil) -> Reading {
        Shuffler.draw(deck: deck, spread: method, seed: 20260817,
                      allowsReversals: false, date: Date(timeIntervalSince1970: 0),
                      question: question)
    }

    func testEveryCombinationPromptsCompletely() {
        for method in Spread.all {
            for deck in Deck.all {
                let reading = makeReading(method: method, deck: deck)
                let prompt = ReadingPrompt.prompt(reading: reading, deck: deck, spread: method)
                let instructions = ReadingPrompt.instructions(deck: deck, spread: method)
                for drawn in reading.cards {
                    let position = method.positions[drawn.positionIndex]
                    XCTAssertTrue(prompt.contains(position.name),
                                  "\(method.id)/\(deck.id): missing \(position.name)")
                    XCTAssertTrue(prompt.contains(position.meaning),
                                  "\(method.id)/\(deck.id): missing meaning for \(position.name)")
                }
                XCTAssertTrue(instructions.contains(deck.traditionLine),
                              "\(method.id)/\(deck.id): tradition line absent")
                XCTAssertTrue(instructions.contains(ReadingPrompt.sentenceBudget(method)),
                              "\(method.id)/\(deck.id): sentence budget absent")
                // Register rules hold everywhere.
                XCTAssertTrue(instructions.contains("never predict the future"))
                XCTAssertFalse(prompt.lowercased().contains("rider"),
                               "the trademarked deck name must never appear")
                XCTAssertFalse(instructions.lowercased().contains("rider"))
            }
        }
    }

    /// The closing reminder is the app's cheapest defence against the model naming cards
    /// and predicting — measured to roughly halve both. It has to be LAST except for the
    /// language directive, because last is what a small model weighs most.
    func testTheClosingReminderIsPresentAndTheLanguageLineStaysLast() {
        for method in Spread.all {
            for deck in Deck.all {
                let reading = makeReading(method: method, deck: deck)
                let prompt = ReadingPrompt.prompt(reading: reading, deck: deck, spread: method)
                XCTAssertTrue(prompt.contains("do not write any card's name"),
                              "\(method.id)/\(deck.id): the closing reminder is missing")
                XCTAssertTrue(prompt.contains("never about what will happen"),
                              "\(method.id)/\(deck.id): the non-predictive reminder is missing")
                XCTAssertTrue(prompt.hasSuffix("do not write any card's name."),
                              "the reminder must be last when no language is requested")
                let german = ReadingPrompt.prompt(reading: reading, deck: deck, spread: method,
                                                  language: "German")
                XCTAssertTrue(german.hasSuffix("Write the entire reading in German."),
                              "the language directive must stay last of all")
            }
        }
    }

    func testCountWordingMatchesTheMethod() {
        let expectations: [(String, String)] = [
            ("daily-card", "single-card draw"),
            ("three-card", "three-card draw"),
            ("crossroads", "five-card draw"),
            ("celtic-cross", "ten-card draw"),
        ]
        for (methodID, phrase) in expectations {
            let method = Spread.method(id: methodID)
            let reading = makeReading(method: method, deck: .classic1909)
            let prompt = ReadingPrompt.prompt(reading: reading, deck: .classic1909, spread: method)
            XCTAssertTrue(prompt.contains(phrase), "\(methodID): expected \"\(phrase)\"")
        }
        // The single card asks for no synthesis; every other method asks for one.
        let daily = ReadingPrompt.prompt(reading: makeReading(method: .dailyCard, deck: .classic1909),
                                         deck: .classic1909, spread: .dailyCard)
        XCTAssertTrue(daily.contains("no synthesis"))
        let celtic = ReadingPrompt.prompt(reading: makeReading(method: .celticCross, deck: .classic1909),
                                          deck: .classic1909, spread: .celticCross)
        XCTAssertTrue(celtic.contains("synthesis"))
        XCTAssertFalse(celtic.contains("no synthesis"))
    }

    /// The measured guardrail names stay out of the prompt under EVERY deck — the prompt
    /// vocabulary is canonical 1909 regardless of what the deck shows the user, which is
    /// exactly why new decks add no new guardrail surface.
    func testRefusedNamesStayOutUnderEveryDeck() {
        let riskyCards: [Card] = [.minor(.swords, .five), .minor(.swords, .ten), .major(12)]
        let refusedLiterals = ["Five of Swords", "Ten of Swords", "The Hanged Man"]
        for deck in Deck.all {
            for method in Spread.all where method.positions.count >= 3 {
                var reading = makeReading(method: method, deck: deck)
                var cards = reading.cards
                for (k, risky) in riskyCards.enumerated() where cards.indices.contains(k) {
                    cards[k] = DrawnCard(card: risky, orientation: .upright, positionIndex: k)
                }
                reading = Reading(date: reading.date, deckID: reading.deckID,
                                  spreadID: reading.spreadID, seed: reading.seed,
                                  allowsReversals: reading.allowsReversals, cards: cards,
                                  question: nil)
                let prompt = ReadingPrompt.prompt(reading: reading, deck: deck, spread: method)
                for literal in refusedLiterals {
                    XCTAssertFalse(prompt.contains(literal),
                                   "\(deck.id)/\(method.id): \(literal) reached the prompt")
                }
            }
        }
    }

    /// The composer streams a correct-arity draft for every method through a mock writer —
    /// the count contract the UI relies on, checked without the model.
    @MainActor
    func testComposerHandlesEveryArity() async {
        for method in Spread.all {
            let reading = makeReading(method: method, deck: .classic1909)
            let writer = ArityMockWriter(count: method.positions.count)
            let composer = ReadingComposer()
            composer.start(reading: reading, deck: .classic1909, spread: method, writer: writer)
            for _ in 0..<200 {
                if case .finished = composer.state { break }
                try? await Task.sleep(nanoseconds: 10_000_000)
            }
            guard case .finished(let draft) = composer.state else {
                XCTFail("\(method.id): composer never finished (\(composer.state))")
                continue
            }
            XCTAssertEqual(draft.passages.count, method.positions.count, method.id)
            XCTAssertEqual(draft.synthesis == nil, method.positions.count == 1, method.id)
        }
    }
}

/// Streams n passages then (for n > 1) a synthesis, then finishes — the writer contract
/// at every arity, with no model in the room.
@MainActor
private final class ArityMockWriter: ReadingWriter {
    let count: Int
    init(count: Int) { self.count = count }
    var availability: WriterAvailability { .available }

    func write(reading: Reading, deck: Deck, spread: Spread) -> AsyncThrowingStream<PassageDraft, Error> {
        AsyncThrowingStream { continuation in
            var draft = PassageDraft()
            for i in 0..<count {
                draft.passages.append("Passage \(i + 1) of \(count).")
                continuation.yield(draft)
            }
            if count > 1 {
                draft.synthesis = "A synthesis across \(count)."
                continuation.yield(draft)
            }
            continuation.finish()
        }
    }
}

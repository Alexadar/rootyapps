import Foundation
import Testing
@testable import TarotKit

@Suite("Reading serialization")
struct ReadingCodableTests {

    @Test func readingRoundTripsThroughJSON() throws {
        let original = Shuffler.draw(deck: .classic1909, spread: .threeCard,
                                     seed: 0xC0FF_EE00_1234_5678, allowsReversals: true,
                                     date: Date(timeIntervalSince1970: 1_755_000_000))
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Reading.self, from: data)
        #expect(decoded == original)
    }

    @Test func readingWithInterpretationSeedRoundTrips() throws {
        var reading = Shuffler.draw(deck: .classic1909, spread: .threeCard,
                                    seed: 7, allowsReversals: false,
                                    date: Date(timeIntervalSince1970: 0))
        reading.interpretationSeed = 0xFEED_FACE
        let data = try JSONEncoder().encode(reading)
        let decoded = try JSONDecoder().decode(Reading.self, from: data)
        #expect(decoded == reading)
        #expect(decoded.interpretationSeed == 0xFEED_FACE)
    }

    /// A decoded reading replays to the same cards through the shuffler — the property the
    /// future library screen depends on. Both toggle states, per the house rule.
    @Test func decodedReadingReplaysExactly() throws {
        for allows in [true, false] {
            let original = Shuffler.draw(deck: .classic1909, spread: .threeCard,
                                         seed: 991, allowsReversals: allows,
                                         date: Date(timeIntervalSince1970: 12345))
            let data = try JSONEncoder().encode(original)
            let decoded = try JSONDecoder().decode(Reading.self, from: data)
            let replayed = Shuffler.draw(deck: .classic1909, spread: .threeCard,
                                         seed: decoded.seed, allowsReversals: decoded.allowsReversals,
                                         date: decoded.date)
            #expect(replayed.cards == original.cards)
        }
    }

    /// The question rides along and round-trips; its absence stays absent. And it must
    /// never influence the deal — same seed, with and without a question, same cards.
    @Test func questionRoundTripsAndNeverChangesTheCards() throws {
        let with = Shuffler.draw(deck: .classic1909, spread: .threeCard, seed: 5150,
                                 allowsReversals: true, date: Date(timeIntervalSince1970: 0),
                                 question: "Should I take the new job?")
        let without = Shuffler.draw(deck: .classic1909, spread: .threeCard, seed: 5150,
                                    allowsReversals: true, date: Date(timeIntervalSince1970: 0))
        #expect(with.cards == without.cards, "the question leaked into the shuffle")
        #expect(with.question == "Should I take the new job?")
        #expect(without.question == nil)
        let decoded = try JSONDecoder().decode(Reading.self, from: JSONEncoder().encode(with))
        #expect(decoded == with)
        #expect(decoded.question == with.question)
    }

    /// Every card and orientation survives the trip — including reversed, which must never
    /// quietly decode as upright.
    @Test func orientationSurvivesEncoding() throws {
        let drawn = [
            DrawnCard(card: .major(13), orientation: .reversed, positionIndex: 0),
            DrawnCard(card: .minor(.cups, .queen), orientation: .upright, positionIndex: 1),
            DrawnCard(card: .minor(.swords, .three), orientation: .reversed, positionIndex: 2),
        ]
        let reading = Reading(date: Date(timeIntervalSince1970: 0), deckID: "classic-1909",
                              spreadID: "three-card", seed: 1, allowsReversals: true, cards: drawn)
        let decoded = try JSONDecoder().decode(Reading.self, from: JSONEncoder().encode(reading))
        #expect(decoded.cards == drawn)
    }
}

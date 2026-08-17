import Foundation
import Testing
@testable import TarotKit

/// The method and deck registries: every entry complete, structurally identical where the
/// design demands it, distinct where it earns its place.
@Suite struct RegistryIntegrityTests {

    // MARK: Decks

    @Test func everyDeckHasTheSameSeventyEightCards() {
        let reference = Set(Deck.classic1909.cards.map(\.id))
        #expect(reference.count == 78)
        for deck in Deck.all {
            #expect(deck.cards.count == 78, "\(deck.id)")
            #expect(Set(deck.cards.map(\.id)) == reference, "\(deck.id)")
            // Order matters too — lane indices are positions in this array.
            #expect(deck.cards == Deck.classic1909.cards, "\(deck.id)")
        }
    }

    @Test func everyDeckNamesEveryCardUniquely() {
        for deck in Deck.all {
            let names = deck.cards.map { deck.name(for: $0) }
            #expect(names.allSatisfy { !$0.isEmpty }, "\(deck.id)")
            #expect(Set(names).count == names.count, "\(deck.id) has duplicate names")
            #expect(deck.majorNames.count == 22, "\(deck.id)")
            #expect(!deck.traditionLine.isEmpty, "\(deck.id)")
        }
    }

    @Test func deckRegistryLeadsWithTheDefaultAndFallsBack() {
        #expect(Deck.all.first?.id == "classic-1909")
        #expect(Set(Deck.all.map(\.id)).count == Deck.all.count)
        #expect(Deck.deck(id: "classic-1909").id == "classic-1909")
        #expect(Deck.deck(id: "astral").id == "astral")
        // A stale id from a future update degrades to the default, never crashes.
        #expect(Deck.deck(id: "no-such-deck").id == "classic-1909")
    }

    @Test func marseilleKeepsItsHistoricOrdering() {
        let m = Deck.marseille1760
        #expect(m.majorNames[8] == "Justice")
        #expect(m.majorNames[11] == "Strength")
        // 1909 has them swapped — the differentiator is real, not cosmetic.
        #expect(Deck.classic1909.majorNames[8] == "Strength")
        #expect(Deck.classic1909.majorNames[11] == "Justice")
        #expect(m.name(for: .minor(.wands, .page)) == "Valet of Wands")
        #expect(Deck.classic1909.name(for: .minor(.wands, .page)) == "Page of Wands")
    }

    @Test func astralSharesNoMajorNameWithAnyTradition() {
        let astral = Set(Deck.astral.majorNames)
        let traditions = Set(Deck.classic1909.majorNames).union(Deck.marseille1760.majorNames)
        #expect(astral.isDisjoint(with: traditions), "an original deck must be original")
    }

    @Test func classicNamingMatchesTheCanonicalCardNames() {
        for card in Deck.classic1909.cards {
            #expect(Deck.classic1909.name(for: card) == card.displayName)
        }
    }

    // MARK: Methods

    @Test func everyMethodIsCompleteAndDistinct() {
        #expect(Spread.all.map(\.positions.count) == [1, 3, 5, 10])
        #expect(Set(Spread.all.map(\.id)).count == Spread.all.count)
        for method in Spread.all {
            #expect(!method.displayName.isEmpty)
            #expect(!method.tagline.isEmpty)
            let names = method.positions.map(\.name)
            #expect(Set(names).count == names.count, "\(method.id) repeats a position name")
            for position in method.positions {
                #expect(!position.name.isEmpty)
                #expect(!position.meaning.isEmpty)
            }
        }
    }

    @Test func methodRegistryFallsBackToTheDefault() {
        #expect(Spread.method(id: "three-card").id == "three-card")
        #expect(Spread.method(id: "celtic-cross").positions.count == 10)
        #expect(Spread.method(id: "no-such-method").id == "three-card")
    }

    /// The register rule, held as data: no position meaning may promise the future.
    @Test func noMethodMeaningIsPredictive() {
        let forbidden = ["will ", "future", "fate", "destiny", "predict"]
        for method in Spread.all {
            for position in method.positions {
                let meaning = position.meaning.lowercased()
                for word in forbidden {
                    #expect(!meaning.contains(word), "\(method.id)/\(position.name): \(word)")
                }
            }
        }
    }

    /// Every method draws fairly from every deck — the shuffle machinery is method- and
    /// deck-generic by construction; this pins it.
    @Test func everyMethodDrawsFromEveryDeck() {
        for method in Spread.all {
            for deck in Deck.all {
                let reading = Shuffler.draw(deck: deck, spread: method, seed: 99,
                                            allowsReversals: false,
                                            date: Date(timeIntervalSince1970: 0))
                #expect(reading.cards.count == method.positions.count)
                #expect(Set(reading.cards.map { $0.card.id }).count == method.positions.count)
                #expect(reading.deckID == deck.id)
                #expect(reading.spreadID == method.id)
            }
        }
    }
}

/// `Card.id` and `Card(id:)` are two halves of one contract — the round trip is the only
/// thing that keeps them from drifting apart.
@Suite struct CardIdentifierTests {

    @Test func everyCardSurvivesTheRoundTrip() {
        for card in Deck.standardCards {
            #expect(Card(id: card.id) == card, "\(card.id)")
        }
        #expect(Deck.standardCards.count == 78)
    }

    @Test func malformedIdentifiersAreRejected() {
        // Shapes unlike the obvious ones, deliberately: the guard has to actually fire.
        for bad in ["", "major", "major-", "major-22", "major-99", "major-x", "-", "cups",
                    "cups-", "cups-0", "cups-15", "cups-1", "cups-king", "goblets-3",
                    "Cups-3", "major-01-extra", "swords-ACE"] {
            #expect(Card(id: bad) == nil, "accepted \(bad)")
        }
        // …and the two shapes that ARE legal stay legal, so the test can fail both ways.
        #expect(Card(id: "major-00") == .major(0))
        #expect(Card(id: "pentacles-ace") == .minor(.pentacles, .ace))
        #expect(Card(id: "swords-14") == .minor(.swords, .king))
    }
}

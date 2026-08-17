import Testing
@testable import TarotKit

@Suite("Deck integrity")
struct DeckIntegrityTests {

    @Test func deckHasExactly78Cards() {
        #expect(Deck.classic1909.cards.count == 78)
    }

    @Test func majorsAreNumberedZeroThroughTwentyOneWithNames() {
        let majors = Deck.classic1909.cards.compactMap { card -> Int? in
            if case .major(let n) = card { return n }
            return nil
        }
        #expect(majors == Array(0...21))
        #expect(Card.majorNames.count == 22)
        for n in 0...21 {
            #expect(!Card.major(n).displayName.isEmpty)
            #expect(Card.major(n).displayName != "Major \(n)", "major \(n) is missing a real name")
        }
    }

    @Test func everySuitHasExactlyFourteenRanks() {
        for suit in Suit.allCases {
            let ranks = Deck.classic1909.cards.compactMap { card -> Rank? in
                if case .minor(let s, let r) = card, s == suit { return r }
                return nil
            }
            #expect(ranks.count == 14, "\(suit) has \(ranks.count) ranks")
            #expect(Set(ranks).count == 14, "\(suit) repeats a rank")
        }
    }

    @Test func allCardIDsAreUnique() {
        let ids = Deck.classic1909.cards.map(\.id)
        #expect(Set(ids).count == 78)
    }

    @Test func cardIDsAreStable() {
        // These exact strings are the serialization contract — saved readings reference them.
        #expect(Card.major(0).id == "major-00")
        #expect(Card.major(21).id == "major-21")
        #expect(Card.minor(.wands, .ace).id == "wands-ace")
        #expect(Card.minor(.pentacles, .king).id == "pentacles-14")
        #expect(Card.minor(.swords, .ten).id == "swords-10")
    }

    @Test func spreadShipsExactlyThreePositions() {
        #expect(Spread.threeCard.positions.count == 3)
        #expect(Spread.threeCard.positions.map(\.name) == ["Situation", "Action", "Outcome"])
        for p in Spread.threeCard.positions {
            #expect(!p.meaning.isEmpty)
        }
    }

    /// The trademarked phrase must not appear in any string this Kit could ever surface.
    /// (The 1909 artwork and names are public domain; the two-word brand is not.)
    @Test func noTrademarkedDeckBrandInAnyUserFacingString() {
        var strings = Card.majorNames
        strings.append(Deck.classic1909.displayName)
        strings.append(Deck.classic1909.id)
        strings.append(contentsOf: Deck.classic1909.cards.map(\.displayName))
        strings.append(contentsOf: Spread.threeCard.positions.flatMap { [$0.name, $0.meaning] })
        for s in strings {
            #expect(!s.lowercased().contains("rider"), "trademarked brand fragment in: \(s)")
        }
    }
}

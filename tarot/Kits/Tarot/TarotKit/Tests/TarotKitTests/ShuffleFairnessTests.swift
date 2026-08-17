import Foundation
import Testing
@testable import TarotKit

@Suite("Shuffle fairness")
struct ShuffleFairnessTests {

    // MARK: - The generator itself has an external authority

    /// Vigna's published reference sequence for state 0 — http://prng.di.unimi.it/splitmix64.c
    /// The only third-party oracle in this Kit; everything else is statistics against it.
    @Test func splitMix64MatchesPublishedReferenceVectors() {
        var rng = SplitMix64(seed: 0)
        let expected: [UInt64] = [
            0xE220_A839_7B1D_CDAF,
            0x6E78_9E6A_A1B9_65F4,
            0x06C4_5D18_8009_454F,
            0xF88B_B8A8_724C_81EC,
            0x1B39_896A_51A8_749B,
        ]
        for value in expected {
            #expect(rng.next() == value)
        }
    }

    // MARK: - Uniformity

    /// Chi-square over which card lands at a position, across 78,000 draws (expected 1,000 per
    /// card per position). df = 77; critical value at α = 0.001 is ≈ 121.2 (Wilson–Hilferty).
    /// The seed is fixed, so this is deterministic — a regression gate, not a flaky sampler —
    /// and it runs at the first AND last spread position, because "uniform at position 0" says
    /// nothing about a bug that skews later deals.
    @Test func cardFrequencyIsUniformAtEveryPosition() {
        let draws = 78_000
        let deck = Deck.classic1909
        var counts = [[Int]](repeating: [Int](repeating: 0, count: 78), count: 3)

        for i in 0..<draws {
            let reading = Shuffler.draw(deck: deck, spread: .threeCard,
                                        seed: UInt64(i) &* 0x9E37_79B9 &+ 42,
                                        allowsReversals: true, date: Date(timeIntervalSince1970: 0))
            for drawn in reading.cards {
                let index = deck.cards.firstIndex(of: drawn.card)!
                counts[drawn.positionIndex][index] += 1
            }
        }

        let expected = Double(draws) / 78.0
        for position in [0, 2] {
            var chi = 0.0
            for c in counts[position] {
                let d = Double(c) - expected
                chi += d * d / expected
            }
            #expect(chi < 121.2, "position \(position): chi-square \(chi) exceeds α=0.001 critical value")
            // Sandwich from the other side: a chi-square near zero means the "randomness" is
            // suspiciously even — e.g. dealing round-robin. Lower 0.001 tail for df=77 ≈ 44.
            #expect(chi > 44.0, "position \(position): chi-square \(chi) is too uniform to be random")
        }
    }

    @Test func everyCardAppearsAcrossManyDraws() {
        var seen = Set<Card>()
        for i in 0..<2_000 {
            let reading = Shuffler.draw(deck: .classic1909, spread: .threeCard,
                                        seed: UInt64(i), allowsReversals: false,
                                        date: Date(timeIntervalSince1970: 0))
            for drawn in reading.cards { seen.insert(drawn.card) }
        }
        #expect(seen.count == 78, "only \(seen.count) of 78 cards ever appeared")
    }

    // MARK: - Reversal rate, both toggle states

    /// 50% within tolerance when on. 234,000 orientation draws; binomial σ ≈ 0.001, so ±0.005
    /// is 5σ against drift while catching the shipped-competitor bug (~70%) by a mile.
    @Test func reversalRateIsHalfWhenAllowed() {
        var reversed = 0, total = 0
        for i in 0..<78_000 {
            let reading = Shuffler.draw(deck: .classic1909, spread: .threeCard,
                                        seed: UInt64(i) &* 31 &+ 7, allowsReversals: true,
                                        date: Date(timeIntervalSince1970: 0))
            for drawn in reading.cards {
                total += 1
                if drawn.orientation == .reversed { reversed += 1 }
            }
        }
        let rate = Double(reversed) / Double(total)
        #expect(abs(rate - 0.5) < 0.005, "reversal rate \(rate)")
    }

    /// The dead-toggle rule: off must mean exactly zero, verified over a large sample —
    /// not just the default state.
    @Test func reversalRateIsZeroWhenDisallowed() {
        for i in 0..<10_000 {
            let reading = Shuffler.draw(deck: .classic1909, spread: .threeCard,
                                        seed: UInt64(i), allowsReversals: false,
                                        date: Date(timeIntervalSince1970: 0))
            for drawn in reading.cards {
                #expect(drawn.orientation == .upright)
            }
        }
    }

    /// Toggling reversals must not change WHICH cards are dealt — orientations come from a
    /// separate stream. Without this property, flipping the setting re-deals a saved seed.
    @Test func reversalToggleNeverChangesTheCards() {
        for i in 0..<1_000 {
            let on = Shuffler.draw(deck: .classic1909, spread: .threeCard,
                                   seed: UInt64(i), allowsReversals: true,
                                   date: Date(timeIntervalSince1970: 0))
            let off = Shuffler.draw(deck: .classic1909, spread: .threeCard,
                                    seed: UInt64(i), allowsReversals: false,
                                    date: Date(timeIntervalSince1970: 0))
            #expect(on.cards.map(\.card) == off.cards.map(\.card))
        }
    }

    // MARK: - No duplicates, reproducibility

    @Test func noDuplicateCardWithinAnyDraw() {
        for i in 0..<10_000 {
            let reading = Shuffler.draw(deck: .classic1909, spread: .threeCard,
                                        seed: UInt64(i) &* 6_364_136_223_846_793_005 &+ 1,
                                        allowsReversals: true,
                                        date: Date(timeIntervalSince1970: 0))
            let cards = reading.cards.map(\.card)
            #expect(Set(cards).count == cards.count, "duplicate in draw \(i): \(cards)")
        }
    }

    @Test func identicalSeedReproducesIdenticalCards() {
        let date = Date(timeIntervalSince1970: 1_755_000_000)
        for seed: UInt64 in [0, 1, 42, .max, 0xDEAD_BEEF] {
            let a = Shuffler.draw(deck: .classic1909, spread: .threeCard,
                                  seed: seed, allowsReversals: true, date: date)
            let b = Shuffler.draw(deck: .classic1909, spread: .threeCard,
                                  seed: seed, allowsReversals: true, date: date)
            #expect(a.cards == b.cards)
            #expect(a.seed == b.seed)
        }
    }

    @Test func permutationIsAPermutation() {
        for seed: UInt64 in [0, 7, 0xFFFF_FFFF_FFFF_FFFF] {
            let order = Shuffler.permutation(count: 78, seed: seed)
            #expect(order.sorted() == Array(0..<78))
        }
    }
}

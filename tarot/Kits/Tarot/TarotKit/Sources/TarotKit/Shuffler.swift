import Foundation

/// The shuffle, written to be provably fair — because shipped competitors provably are not
/// (one returns a reversed card ~70% of the time and its reviews say so).
///
/// Guarantees, each of them tested:
///
/// * **Uniform permutation.** Fisher–Yates over all 78, driven by Lemire-debiased integers from
///   a seeded SplitMix64. No position is special; the chi-square test holds at every position.
/// * **No duplicates by construction.** A draw is the first `k` cards of one permutation.
/// * **Reversals at exactly 50%, independently per card** — and decided from a *separate RNG
///   stream* derived from the same seed, so the same seed deals the same three cards whether
///   the reversal toggle is on or off. The toggle changes orientations, never identities.
/// * **Reproducible.** Same (deck, spread, seed, allowsReversals) → the same `Reading` cards.
///
/// Pure, stateless.
public enum Shuffler {

    /// The stream-splitting constant: orientation draws come from `seed ^ orientationStream`
    /// so toggling reversals cannot shift the permutation stream. Arbitrary odd 64-bit value;
    /// never change it — saved readings replay through it.
    static let orientationStream: UInt64 = 0xA5A5_5A5A_C3C3_3C3C

    /// The full shuffled order of deck indices for `seed`. Exposed so the deck-shuffle
    /// animation can *replay* the permutation — presentation never generates its own.
    public static func permutation(count: Int, seed: UInt64) -> [Int] {
        var rng = SplitMix64(seed: seed)
        var order = Array(0..<count)
        guard count > 1 else { return order }
        for i in stride(from: count - 1, to: 0, by: -1) {
            let j = rng.int(in: 0...i)
            order.swapAt(i, j)
        }
        return order
    }

    /// Deal a reading: the first `spread.positions.count` cards of the seeded permutation,
    /// each with an independently 50% reversed orientation (when allowed).
    /// The question rides along for the interpretation; the shuffle never reads it.
    public static func draw(deck: Deck, spread: Spread, seed: UInt64,
                            allowsReversals: Bool, date: Date,
                            question: String? = nil) -> Reading {
        let order = permutation(count: deck.cards.count, seed: seed)
        var orientationRNG = SplitMix64(seed: seed ^ orientationStream)

        let drawn = (0..<spread.positions.count).map { position -> DrawnCard in
            let card = deck.cards[order[position]]
            let reversed = orientationRNG.chance(0.5)
            return DrawnCard(card: card,
                             orientation: (allowsReversals && reversed) ? .reversed : .upright,
                             positionIndex: position)
        }
        return Reading(date: date, deckID: deck.id, spreadID: spread.id,
                       seed: seed, allowsReversals: allowsReversals, cards: drawn,
                       question: question)
    }
}

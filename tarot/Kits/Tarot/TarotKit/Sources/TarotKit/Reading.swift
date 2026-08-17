import Foundation

/// One card as it landed: which card, which way up, and in which spread position.
public struct DrawnCard: Equatable, Codable, Sendable {
    public let card: Card
    public let orientation: Orientation
    public let positionIndex: Int

    public init(card: Card, orientation: Orientation, positionIndex: Int) {
        self.card = card
        self.orientation = orientation
        self.positionIndex = positionIndex
    }
}

/// A completed draw, serializable now even though this run ships no library screen.
///
/// The seed makes the reading replayable: `Shuffler.draw` with the same deck, spread, seed and
/// reversal setting reproduces these exact cards, which is what lets a future library replay
/// the animation of an old reading rather than merely list it.
public struct Reading: Equatable, Codable, Sendable, Identifiable {
    public let id: UUID
    public let date: Date
    public let deckID: String
    public let spreadID: String
    public let seed: UInt64
    public let allowsReversals: Bool
    public let cards: [DrawnCard]
    /// The reader's question, if they asked one. The interpretation speaks to it;
    /// the shuffle never sees it.
    public var question: String?
    /// Recorded sampling seed of the on-device interpretation, if one was written.
    /// Provenance only — model updates may change the text; the cards never change.
    public var interpretationSeed: UInt64?

    public init(id: UUID = UUID(), date: Date, deckID: String, spreadID: String,
                seed: UInt64, allowsReversals: Bool, cards: [DrawnCard],
                question: String? = nil,
                interpretationSeed: UInt64? = nil) {
        self.id = id
        self.date = date
        self.deckID = deckID
        self.spreadID = spreadID
        self.seed = seed
        self.allowsReversals = allowsReversals
        self.cards = cards
        self.question = question
        self.interpretationSeed = interpretationSeed
    }
}

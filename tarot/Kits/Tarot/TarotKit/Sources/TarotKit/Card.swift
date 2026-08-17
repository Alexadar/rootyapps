import Foundation

/// Major or minor arcana. The two halves of a 78-card deck.
public enum Arcana: String, Codable, Sendable, CaseIterable {
    case major
    case minor
}

/// The four minor suits.
public enum Suit: String, Codable, Sendable, CaseIterable {
    case wands
    case cups
    case swords
    case pentacles
}

/// The fourteen ranks of a minor suit: ace through ten, then the four court cards.
public enum Rank: Int, Codable, Sendable, CaseIterable {
    case ace = 1
    case two, three, four, five, six, seven, eight, nine, ten
    case page = 11
    case knight, queen, king

    public var displayName: String {
        switch self {
        case .ace: return "Ace"
        case .two: return "Two"
        case .three: return "Three"
        case .four: return "Four"
        case .five: return "Five"
        case .six: return "Six"
        case .seven: return "Seven"
        case .eight: return "Eight"
        case .nine: return "Nine"
        case .ten: return "Ten"
        case .page: return "Page"
        case .knight: return "Knight"
        case .queen: return "Queen"
        case .king: return "King"
        }
    }
}

/// One card. Identity is structural — a major is its number, a minor is suit × rank — and the
/// derived `id` string is the stable key everything else (art lookup, serialization) hangs off.
public enum Card: Hashable, Codable, Sendable {
    case major(Int)
    case minor(Suit, Rank)

    public var arcana: Arcana {
        switch self {
        case .major: return .major
        case .minor: return .minor
        }
    }

    /// Stable identifier, e.g. `"major-00"`, `"wands-ace"`, `"swords-11"`.
    /// Never shown to the user; never change its format — saved `Reading`s reference it.
    public var id: String {
        switch self {
        case .major(let n):
            return String(format: "major-%02d", n)
        case .minor(let suit, let rank):
            switch rank {
            case .ace: return "\(suit.rawValue)-ace"
            case .page, .knight, .queen, .king: return "\(suit.rawValue)-\(rank.rawValue)"
            default: return "\(suit.rawValue)-\(rank.rawValue)"
            }
        }
    }

    /// The inverse of `id` — parse a card back out of its stable identifier.
    ///
    /// `id` had no inverse until scenarios needed to name cards in a file. Anything that
    /// serialises a card by id (a saved reading, a filming scenario, a bug report) needs
    /// this to read it back, and a round-trip test over all 78 keeps the two halves from
    /// drifting apart.
    public init?(id: String) {
        let parts = id.split(separator: "-", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        if parts[0] == "major" {
            guard let n = Int(parts[1]), (0...21).contains(n) else { return nil }
            self = .major(n)
            return
        }
        guard let suit = Suit(rawValue: parts[0]) else { return nil }
        if parts[1] == "ace" {
            self = .minor(suit, .ace)
            return
        }
        guard let raw = Int(parts[1]), let rank = Rank(rawValue: raw), rank != .ace else { return nil }
        self = .minor(suit, rank)
    }

    /// The display name, e.g. "The Fool", "Ace of Wands".
    public var displayName: String {
        switch self {
        case .major(let n):
            return Card.majorNames.indices.contains(n) ? Card.majorNames[n] : "Major \(n)"
        case .minor(let suit, let rank):
            return "\(rank.displayName) of \(suit.rawValue.capitalized)"
        }
    }

    /// The 22 major arcana names of the classic 1909 deck, indexed 0–21.
    /// This ordering (Strength at 8, Justice at 11) is the 1909 ordering and is public domain.
    public static let majorNames: [String] = [
        "The Fool",             // 0
        "The Magician",         // 1
        "The High Priestess",   // 2
        "The Empress",          // 3
        "The Emperor",          // 4
        "The Hierophant",       // 5
        "The Lovers",           // 6
        "The Chariot",          // 7
        "Strength",             // 8
        "The Hermit",           // 9
        "Wheel of Fortune",     // 10
        "Justice",              // 11
        "The Hanged Man",       // 12
        "Death",                // 13
        "Temperance",           // 14
        "The Devil",            // 15
        "The Tower",            // 16
        "The Star",             // 17
        "The Moon",             // 18
        "The Sun",              // 19
        "Judgement",            // 20
        "The World",            // 21
    ]
}

/// Upright or reversed. First-class — a `DrawnCard` without an orientation does not exist,
/// which is what keeps "reversed" from ever being a bolted-on afterthought.
public enum Orientation: String, Codable, Sendable, CaseIterable {
    case upright
    case reversed

    public var displayName: String {
        switch self {
        case .upright: return "Upright"
        case .reversed: return "Reversed"
        }
    }
}

import Foundation

/// A deck: identity, display metadata, and an ordered list of cards.
///
/// The deck is data, never views. Multiple decks can coexist (a generated art deck later drops
/// in as a second `Deck` value with its own `id`), and everything downstream — art lookup,
/// shuffling, saved readings — keys off `Deck.id` + `Card.id`, so a new deck touches no code.
public struct Deck: Equatable, Codable, Sendable, Identifiable {
    public let id: String
    public let displayName: String
    public let cards: [Card]
    /// The deck's 22 major names, indexed 0–21 — a deck IS a naming tradition; this array
    /// is where traditions differ (Marseille swaps 8/11, the Astral renames everything).
    public let majorNames: [String]
    /// The lowest court's title ("Page" in 1909, "Valet" in Marseille). The other three
    /// courts are named identically across every shipped tradition.
    public let pageTitle: String
    /// One English line describing the tradition, fed verbatim into the writer's prompt
    /// and shown (localized) as picker copy.
    public let traditionLine: String

    public init(id: String, displayName: String, cards: [Card],
                majorNames: [String] = Card.majorNames, pageTitle: String = "Page",
                traditionLine: String = "") {
        self.id = id
        self.displayName = displayName
        self.cards = cards
        self.majorNames = majorNames
        self.pageTitle = pageTitle
        self.traditionLine = traditionLine
    }

    /// The name this deck gives a card — the UI vocabulary. The writer's prompt keeps
    /// `Card.displayName` (canonical 1909) for every deck: the guardrail refusal table was
    /// measured against those exact names, and the model never repeats names anyway.
    public func name(for card: Card) -> String {
        switch card {
        case .major(let n):
            return majorNames.indices.contains(n) ? majorNames[n] : card.displayName
        case .minor(let suit, let rank):
            let rankWord = rank == .page ? pageTitle : rank.displayName
            return "\(rankWord) of \(suit.rawValue.capitalized)"
        }
    }

    /// The 78 cards every shipped deck contains, in canonical order: majors 0–21, then
    /// each suit ace→king. Decks differ in names, never in structure — which is what keeps
    /// shuffle fairness, motion capacity and saved readings deck-independent.
    public static let standardCards: [Card] = {
        var cards: [Card] = (0...21).map { .major($0) }
        for suit in Suit.allCases {
            for rank in Rank.allCases {
                cards.append(.minor(suit, rank))
            }
        }
        return cards
    }()

    /// Card list of the classic 1909 deck (Waite–Smith), which is public domain.
    /// The user-facing description of this deck is "the classic 1909 deck" — nothing else.
    public static let classic1909 = Deck(
        id: "classic-1909", displayName: "Classic 1909", cards: standardCards,
        traditionLine: "the classic 1909 tradition — scenic, symbolic, the modern standard")

    /// The Marseille tradition (Conver 1760, public domain): austere and direct. Justice
    /// sits at 8 and Strength at 11 (the historic ordering the 1909 deck swapped), XIII is
    /// authentically nameless, and the lowest court is the Valet.
    public static let marseille1760 = Deck(
        id: "marseille-1760", displayName: "Marseille 1760", cards: standardCards,
        majorNames: [
            "The Fool",              // 0
            "The Juggler",           // 1
            "The Papess",            // 2
            "The Empress",           // 3
            "The Emperor",           // 4
            "The Pope",              // 5
            "The Lover",             // 6
            "The Chariot",           // 7
            "Justice",               // 8  ← the 1760 ordering
            "The Hermit",            // 9
            "The Wheel of Fortune",  // 10
            "Strength",              // 11 ← the 1760 ordering
            "The Hanged Man",        // 12
            "The Nameless Arcanum",  // 13 (XIII carries no name on the 1760 card)
            "Temperance",            // 14
            "The Devil",             // 15
            "The House of God",      // 16
            "The Star",              // 17
            "The Moon",              // 18
            "The Sun",               // 19
            "Judgement",             // 20
            "The World",             // 21
        ],
        pageTitle: "Valet",
        traditionLine: "the old Marseille tradition of 1760 — austere, medieval, direct")

    /// The Astral deck: an original night-sky reading of the arcana, written for this app.
    /// Every name is ours — no tradition's phrasing — which is also the strongest possible
    /// licensing position. Index-aligned to the same archetypes as the other decks.
    public static let astral = Deck(
        id: "astral", displayName: "Astral", cards: standardCards,
        majorNames: [
            "The Comet",         // 0  — the fool's headlong arrival
            "The Spark",         // 1
            "The Veil",          // 2
            "The Aurora",        // 3
            "The Polestar",      // 4
            "The Keeper",        // 5
            "The Twin Stars",    // 6
            "The Meteor",        // 7
            "The Ember",         // 8  — strength held quietly
            "The Lantern",       // 9
            "The Orbit",         // 10
            "The Balance",       // 11
            "The Eclipse",       // 12
            "The Falling Star",  // 13
            "The Confluence",    // 14
            "The Shadow",        // 15
            "The Lightning",     // 16
            "The Beacon",        // 17
            "The Tide",          // 18
            "The Dawn",          // 19
            "The Awakening",     // 20
            "The Cosmos",        // 21
        ],
        traditionLine: "the Astral deck — a night-sky reading of the arcana, original to this app")

    // MARK: Registry

    /// Every deck the app offers, in picker order. The default leads.
    public static let all: [Deck] = [.classic1909, .marseille1760, .astral]

    /// Lookup with a hard fallback to the default: a stale persisted id (a deck removed in
    /// an update) must degrade gracefully, never crash.
    public static func deck(id: String) -> Deck {
        all.first { $0.id == id } ?? .classic1909
    }
}

/// A named position within a spread, with the meaning the interpretation writes against.
public struct Position: Equatable, Codable, Sendable {
    public let name: String
    public let meaning: String

    public init(name: String, meaning: String) {
        self.name = name
        self.meaning = meaning
    }
}

/// An ordered set of positions — a METHOD: how many cards, laid where, asking what.
public struct Spread: Equatable, Codable, Sendable, Identifiable {
    public let id: String
    public let displayName: String
    /// One-line picker copy ("Three cards. A question, read plainly.").
    public let tagline: String
    public let positions: [Position]

    public init(id: String, displayName: String, tagline: String = "", positions: [Position]) {
        self.id = id
        self.displayName = displayName
        self.tagline = tagline
        self.positions = positions
    }
}

/// The reading METHOD, by its proper name (owner, 2026-08-17): a method is a spread —
/// how many cards are laid, where, and what each position asks. The app's three
/// abstractions are Method (here), Deck (here), and Skin (app-side, purely visual).
public typealias Method = Spread

extension Spread {
    /// One card, one breath — the smallest method the app offers.
    public static let dailyCard = Spread(
        id: "daily-card",
        displayName: "Daily Card",
        tagline: "One card. A daily pulse.",
        positions: [
            Position(name: "Focus", meaning: "what asks for your attention today"),
        ]
    )

    /// The DEFAULT method. Situation/Action/Outcome is the practitioner-standard
    /// three-card semantic for question-led readings (Past/Present/Future is the
    /// no-question timeline default, and its "Future" slot contradicted this app's
    /// non-predictive register). Outcome is worded as tendency, never prophecy.
    /// Alignment decided 2026-08-17 after research.
    public static let threeCard = Spread(
        id: "three-card",
        displayName: "Three Cards",
        tagline: "Three cards. A question, read plainly.",
        positions: [
            Position(name: "Situation", meaning: "the heart of the matter as it stands"),
            Position(name: "Action", meaning: "what is yours to do or reconsider"),
            Position(name: "Outcome", meaning: "where this is tending as things stand"),
        ]
    )

    /// Five cards for a decision: the crossing of ways, walked around rather than solved.
    /// Every meaning is our own non-predictive wording (spread structures carry no rights).
    public static let crossroads = Spread(
        id: "crossroads",
        displayName: "Crossroads",
        tagline: "Five cards. A decision, walked around.",
        positions: [
            Position(name: "Situation", meaning: "the heart of the matter as it stands"),
            Position(name: "Obstacle", meaning: "what stands in the way"),
            Position(name: "Foundation", meaning: "what this rests on, often unseen"),
            Position(name: "Advice", meaning: "what is yours to try or reconsider"),
            Position(name: "Direction", meaning: "where this is tending as things stand"),
        ]
    )

    /// The full ten-card cross-and-staff — position 1 at the heart, position 2 laid
    /// across it. All wording ours, tendency never prophecy.
    public static let celticCross = Spread(
        id: "celtic-cross",
        displayName: "Celtic Cross",
        tagline: "Ten cards. The whole terrain.",
        positions: [
            Position(name: "Heart of the Matter", meaning: "the heart of the matter as it stands"),
            Position(name: "What Crosses It", meaning: "what cuts across it, helping or hindering"),
            Position(name: "Foundation", meaning: "what this rests on, deep and settled"),
            Position(name: "What Passes", meaning: "what is loosening its hold"),
            Position(name: "The Crown", meaning: "the best that can be made of this"),
            Position(name: "What Approaches", meaning: "what is coming into play"),
            Position(name: "The Self", meaning: "how you stand within this"),
            Position(name: "The House", meaning: "the people and surroundings around it"),
            Position(name: "Hopes and Fears", meaning: "what is hoped for and what is feared, often the same thing"),
            Position(name: "Where It Tends", meaning: "where this is tending as things stand"),
        ]
    )

    // MARK: Registry

    /// Every method the app offers, in picker order (smallest first; the default is
    /// `threeCard` — the picker preselects it, not the first row).
    public static let all: [Spread] = [.dailyCard, .threeCard, .crossroads, .celticCross]

    /// Lookup with a hard fallback to the default — a stale persisted id must never crash.
    public static func method(id: String) -> Spread {
        all.first { $0.id == id } ?? .threeCard
    }
}

import Foundation
import TarotKit

/// The three distinct reasons the on-device writer can be missing, plus available. Three
/// different messages, three different user actions — never collapsed into one error.
enum WriterAvailability: Equatable {
    case available
    /// The hardware cannot run Apple Intelligence. Said clearly, once, without nagging.
    case deviceNotEligible
    /// Apple Intelligence is off. Explain plainly; point at Settings.
    case notEnabled
    /// The model is still downloading. Say that; drawing works meanwhile.
    case modelNotReady
}

/// A partially- or fully-written reading: one passage per position, then a synthesis.
/// Fields fill in as the stream arrives, so the UI can render each card's text as it is
/// being written.
struct PassageDraft: Equatable, Sendable {
    var passages: [String] = []
    var synthesis: String?
}

/// The seam between the app and the writing model. The Foundation Models implementation is
/// the only real conformer; tests drive every availability branch and a mid-stream failure
/// through mocks. There is deliberately NO bundled text and NO fallback writer — the model
/// writes it or nothing does (that is what keeps the app free of anyone's copyrighted
/// card meanings).
@MainActor
protocol ReadingWriter {
    var availability: WriterAvailability { get }
    /// Stream the written reading. The stream throws if writing fails mid-way; whatever
    /// partial text arrived stays on screen.
    func write(reading: Reading, deck: Deck, spread: Spread) -> AsyncThrowingStream<PassageDraft, Error>
}

/// Prompt construction is pure and lives outside the FM conformer so tests can hold it to
/// the register rules without any model present.
enum ReadingPrompt {

    /// The register rules, framed for the SELECTED deck and method: the deck contributes
    /// its one-line tradition (the writer should read a Marseille draw more austerely than
    /// an Astral one), the method its per-card sentence budget (ten passages only fit the
    /// on-device model when each is brief). Card names in prompts stay canonical 1909
    /// vocabulary regardless of deck — the guardrail table was measured against it.
    static func instructions(deck: Deck, spread: Spread) -> String {
        let deckLine = deck.traditionLine.isEmpty
            ? "the classic 1909 tradition" : deck.traditionLine
        return """
        You write short, grounded reflections on tarot cards, read in the spirit of \
        \(deckLine). \
        You never predict the future, never promise outcomes, and never give medical, legal, \
        or financial advice. A reading is a mirror for thinking about the present, not a \
        forecast. Write warmly and concretely, in the second person, without mysticism cliches. \
        For each card, reflect on what its traditional imagery might invite the reader to \
        consider about the named position, in \(sentenceBudget(spread)). Reversed cards read as the quality turned inward, \
        blocked, or asked about rather than a bad omen. Never repeat, translate, or rename a \
        card's name in your writing — the reader already sees the names; refer to each card by \
        its position, or as "this card". Plain prose only: no markdown, no underscores, and \
        no headings — never begin a passage with the position name as a title; the app \
        already labels each passage. If the reader asked a \
        question, let each reflection quietly speak to it — as perspective, never as an answer \
        about what will happen.
        """
    }

    /// Per-method passage budget: one lone card earns a fuller note; ten brief ones must
    /// share a small model's attention.
    static func sentenceBudget(_ spread: Spread) -> String {
        switch spread.positions.count {
        case 1: "five or six sentences"
        case 10: "two or three sentences"
        default: "three or four sentences"
        }
    }

    /// What the model is told a card is. Three tiers, established empirically against the
    /// on-device guardrails (2026-08, macOS 26.5):
    ///  * most cards: their real name;
    ///  * The Devil: real name + a calming gloss (the bare name is refused, the glossed
    ///    name passes);
    ///  * Five/Ten of Swords and The Hanged Man: a NAMELESS paraphrase — no gloss rescues
    ///    the literal name for these ("Detected content likely to be unsafe"). The UI still
    ///    shows the real name; only the model's brief omits it.
    /// `safe: true` paraphrases EVERY card namelessly — the retry mode for a refusal the
    /// table didn't predict (guardrail behavior can shift with OS updates, and reader
    /// questions add uncontrolled text).
    static func promptLabel(for card: Card, safe: Bool = false) -> String {
        if !safe {
            switch card.id {
            case "major-15":
                return "The Devil (a card about noticing one's own chains and the freedom of choice)"
            case "major-12":
                return "the twelfth major arcana, about willing pause and seeing from a new angle"
            case "swords-5":
                return "the fifth card of the air suit, about hollow wins and choosing peace over being right"
            case "swords-10":
                return "the tenth card of the air suit, about a hard chapter fully ending so a new one can begin"
            default:
                return card.displayName
            }
        }
        switch card {
        case .major(let n):
            return "major arcana number \(n), traditionally called a card of change and perspective"
        case .minor(let suit, let rank):
            let element: String
            switch suit {
            case .wands: element = "fire"
            case .cups: element = "water"
            case .swords: element = "air"
            case .pentacles: element = "earth"
            }
            return "the \(rank.displayName.lowercased()) of the \(element) suit"
        }
    }

    static func prompt(reading: Reading, deck: Deck, spread: Spread, safe: Bool = false,
                       language: String? = nil) -> String {
        let lines = reading.cards.map { drawn -> String in
            let position = spread.positions.indices.contains(drawn.positionIndex)
                ? spread.positions[drawn.positionIndex]
                : Position(name: "Position \(drawn.positionIndex + 1)", meaning: "")
            return "\(position.name) (\(position.meaning)): \(promptLabel(for: drawn.card, safe: safe)), \(drawn.orientation.displayName.lowercased())"
        }
        let count = spread.positions.count
        let countWord = ["one", "two", "three", "four", "five", "six", "seven", "eight",
                         "nine", "ten"].indices.contains(count - 1)
            ? ["one", "two", "three", "four", "five", "six", "seven", "eight", "nine",
               "ten"][count - 1] : "\(count)"
        var text = """
        Write the reading for this \(count == 1 ? "single-card" : "\(countWord)-card") draw:
        \(lines.joined(separator: "\n"))
        """
        if let question = reading.question?.trimmingCharacters(in: .whitespacesAndNewlines),
           !question.isEmpty {
            text += "\nThe reader's question: \"\(question)\" — let the reflection speak to it."
        }
        if count == 1 {
            text += "\nOne reflective passage on this card — no synthesis, no summary."
        } else {
            text += """
            \nOne reflective passage per card, in the order given, then a short synthesis \
            weaving the \(countWord) together\(reading.question == nil ? "" : " and returning to the reader's question").
            """
        }
        // The closing reminder, and the reason it is HERE rather than in `instructions`:
        // a small on-device model weighs the last thing it was told most heavily, and the
        // instructions are already a long block of prohibitions it half-follows. Measured
        // over 36 readings across three draws (2026-08-18): naming a card fell from 61% to
        // 31% and predictive phrasing from 33% to 17%, with passage length unchanged — so
        // the reflections keep their specificity. It is a reduction, not a cure: this model
        // has real sampling variance and no phrasing tested made it obey every time.
        text += "\nWrite about what is true for the reader now, never about what will happen. "
            + "Call each card \"this card\" — do not write any card's name."

        // The reading's language is the CALLER's decision (the FM writer resolves it from
        // the rendered UI language ∩ the model's supported set — localized or English,
        // never a mismatch); the prompt itself stays English regardless (the guardrail
        // label table was measured against English card vocabulary).
        if let language {
            text += "\nWrite the entire reading in \(language)."
        }
        return text
    }
}

/// Thrown when the on-device model declines both the normal and the safe-mode prompt.
/// Surfaced honestly — never papered over with canned text.
struct WriterDeclined: Error, Equatable {}

import Foundation
import TarotKit
import os

/// A FILMING SCENARIO: every variable of a take, pinned.
///
/// Marketing video needs the app to do the same thing twice. A live run cannot — the shuffle
/// is seeded from the system RNG and the reading comes from a model whose wording changes
/// every time. A scenario fixes the deck, the method, the exact cards, the typed question, the
/// pacing, and the text, so a second take is comparable to the first and a re-shoot after a
/// code change is still the same video.
///
/// Debug-only, in the same category as `-TAROT_AUTOPILOT`. The reading text is REAL on-device
/// model output captured once and pasted in — the video shows genuinely what the app writes,
/// with only the variance removed.
struct FilmScenario: Equatable {
    var id: String
    var skinID: String
    var deckID: String
    var methodID: String
    var seed: UInt64
    var date: Date
    var question: String
    /// Filming forces these on, because a saved `false` would film a reading with no text
    /// at all, or a take with no sound.
    var interpretations: Bool
    var sounds: Bool
    var cards: [Card]
    var passages: [String]
    var synthesis: String?
    var timing: Timing
    var writing: Writing

    struct Timing: Equatable {
        /// Seconds between typed characters — the question types itself on camera.
        var typeInterval: Double
        /// Beat after the question is complete, before the draw begins.
        var pauseAfter: Double
        /// The shuffle settling before the first card is grabbed.
        var settle: Double
        /// One card's whole window: grab, drag, release, dwell.
        var perCard: Double
        /// How long to sit on the finished reading before the take ends.
        var hold: Double
        /// Grab and drag inside a card's window. The remainder is dwell — and it must be
        /// dwell with the pointer UP, because a pressed pointer zeroes the landing hitstop
        /// and collapses the reading transition.
        var grabHold = 0.20
        var dragDuration = 0.95
    }

    struct Writing: Equatable {
        /// Delay from `startDraw` to the first word. THE number that decides whether a take
        /// is worth anything: the reading panel opens at `settle + n·perCard + 1.1`, and the
        /// text must still be arriving when it does. Too short and the reading is already
        /// finished when the panel appears — the panel snaps open onto a wall of text and
        /// there is nothing to watch.
        var firstDelay: Double
        /// Must match `MagicalStreamText.basePace` (55). Above it the reveal frontier hits
        /// its catch-up mode and text pastes instead of materialising.
        var charsPerSecond: Double
        var chunkInterval: Double
    }

    var method: Spread { Spread.method(id: methodID) }
    var deck: Deck { Deck.deck(id: deckID) }

    /// When the reading panel opens, in scenario time from the start of the take. The scenario
    /// author needs this to choose `firstDelay`; the tests need it to know when to look.
    var readingOpensAt: Double {
        drawStartsAt + timing.settle + Double(cards.count) * timing.perCard + 1.1
    }

    var drawStartsAt: Double {
        Double(question.count) * timing.typeInterval + timing.pauseAfter
    }
}

// MARK: - Loading

extension FilmScenario {

    /// `-TAROT_SCENARIO <name-or-path>`: a bundled scenario's name, or an absolute path so a
    /// scenario can be edited on the Mac between takes without rebuilding the app.
    static func fromLaunchArguments() -> FilmScenario? {
        guard let requested = LaunchOverride.argument("TAROT_SCENARIO") else { return nil }
        let url: URL?
        if requested.hasPrefix("/") {
            url = URL(fileURLWithPath: requested)
        } else {
            url = Bundle.main.url(forResource: requested, withExtension: "scenario.yaml")
                ?? Bundle.main.url(forResource: "\(requested).scenario", withExtension: "yaml")
        }
        guard let url, let text = try? String(contentsOf: url, encoding: .utf8) else {
            report("no scenario at \(requested)", line: 0)
            return nil
        }
        do {
            return try FilmScenario(yaml: text)
        } catch let error as ScenarioError {
            report(error.message, line: error.line)
            return nil
        } catch {
            report("\(error)", line: 0)
            return nil
        }
    }

    /// Loud, never silent, never partial: a take filmed from a half-parsed scenario is the
    /// expensive failure. The status also lands in the Debug chrome so a device run shows it.
    private static func report(_ message: String, line: Int) {
        Logger(subsystem: "oleksandr.aisixteen.tarot", category: "scenario")
            .error("SCENARIO_ERROR line \(line, privacy: .public): \(message, privacy: .public)")
        lastError = "scenario line \(line): \(message)"
        assertionFailure("scenario line \(line): \(message)")
    }

    /// Surfaced by the Debug chrome (MenuOverlay) — a mis-authored scenario must be visible
    /// on the device you are filming with, not just in a log nobody is watching.
    nonisolated(unsafe) static var lastError: String?

    init(yaml text: String) throws {
        let root = try YAMLReader.parse(text)
        func string(_ key: String) throws -> String {
            guard case .scalar(let v)? = root[key] else {
                throw ScenarioError(line: 0, message: "missing '\(key)'")
            }
            return v
        }
        func optionalBool(_ key: String, default fallback: Bool) -> Bool {
            if case .scalar(let v)? = root[key] { return v == "true" || v == "1" }
            return fallback
        }
        func list(_ key: String) throws -> [String] {
            guard case .list(let items)? = root[key] else {
                throw ScenarioError(line: 0, message: "missing list '\(key)'")
            }
            return try items.map {
                guard case .scalar(let v) = $0 else {
                    throw ScenarioError(line: 0, message: "'\(key)' must be a list of scalars")
                }
                return v
            }
        }
        func number(_ map: [String: YAMLReader.Node], _ key: String, _ owner: String) throws -> Double {
            guard case .scalar(let v)? = map[key], let d = Double(v) else {
                throw ScenarioError(line: 0, message: "missing number '\(owner).\(key)'")
            }
            guard d > 0 else {
                throw ScenarioError(line: 0, message: "'\(owner).\(key)' must be positive")
            }
            return d
        }
        guard case .map(let timingMap)? = root["timing"] else {
            throw ScenarioError(line: 0, message: "missing 'timing' block")
        }
        guard case .map(let writingMap)? = root["writing"] else {
            throw ScenarioError(line: 0, message: "missing 'writing' block")
        }

        id = try string("id")
        skinID = try string("skin")
        deckID = try string("deck")
        methodID = try string("method")
        guard let seedValue = UInt64(try string("seed")) else {
            throw ScenarioError(line: 0, message: "'seed' must be a whole number")
        }
        seed = seedValue
        let dateText = try string("date")
        guard let parsed = ISO8601DateFormatter().date(from: dateText) else {
            throw ScenarioError(line: 0, message: "'date' must be ISO-8601, got '\(dateText)'")
        }
        date = parsed
        question = try string("question")
        interpretations = optionalBool("interpretations", default: true)
        sounds = optionalBool("sounds", default: true)

        cards = try list("cards").map { entry in
            guard let card = Self.card(named: entry) else {
                throw ScenarioError(line: 0, message: "no card called '\(entry)'")
            }
            return card
        }
        passages = try list("passages")
        if case .scalar(let text)? = root["synthesis"] { synthesis = text } else { synthesis = nil }

        timing = Timing(typeInterval: try number(timingMap, "typeInterval", "timing"),
                        pauseAfter: try number(timingMap, "pauseAfter", "timing"),
                        settle: try number(timingMap, "settle", "timing"),
                        perCard: try number(timingMap, "perCard", "timing"),
                        hold: try number(timingMap, "hold", "timing"))
        writing = Writing(firstDelay: try number(writingMap, "firstDelay", "writing"),
                          charsPerSecond: try number(writingMap, "charsPerSecond", "writing"),
                          chunkInterval: try number(writingMap, "chunkInterval", "writing"))
        try validate()
    }

    /// Cards may be written by display name ("Ten of Pentacles" — deck-independent canonical
    /// 1909, which is what the reader will recognise) or by `Card.id` ("pentacles-10").
    static func card(named entry: String) -> Card? {
        let wanted = entry.trimmingCharacters(in: .whitespaces).lowercased()
        if let byID = Card(id: wanted) { return byID }
        return Deck.standardCards.first { $0.displayName.lowercased() == wanted }
    }

    /// Everything that would make a take wrong, refused at load rather than discovered in the
    /// footage.
    func validate() throws {
        let positions = method.positions.count
        guard Spread.all.contains(where: { $0.id == methodID }) else {
            throw ScenarioError(line: 0, message: "unknown method '\(methodID)'")
        }
        guard Deck.all.contains(where: { $0.id == deckID }) else {
            throw ScenarioError(line: 0, message: "unknown deck '\(deckID)'")
        }
        guard Skins.all.contains(where: { $0.id == skinID }) else {
            throw ScenarioError(line: 0, message: "unknown skin '\(skinID)'")
        }
        guard cards.count == positions else {
            throw ScenarioError(line: 0,
                                message: "\(methodID) lays \(positions) cards, scenario gives \(cards.count)")
        }
        guard Set(cards.map(\.id)).count == cards.count else {
            throw ScenarioError(line: 0, message: "the same card is drawn twice")
        }
        guard passages.count == positions else {
            throw ScenarioError(line: 0,
                                message: "\(positions) positions need \(positions) passages, got \(passages.count)")
        }
        guard !passages.contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw ScenarioError(line: 0, message: "a passage is empty")
        }
        // A one-card reading physically cannot have a synthesis — `WrittenReadingOne` has no
        // such field — so a scenario with one would film a screen the app cannot produce.
        if positions == 1, synthesis != nil {
            throw ScenarioError(line: 0, message: "a single-card method has no synthesis")
        }
        if positions > 1, synthesis?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            throw ScenarioError(line: 0, message: "missing 'synthesis'")
        }
        // The pointer must be released before the flight lands and stay released, or the
        // hitstop and the reading transition are cancelled by the press itself.
        let minimum = timing.grabHold + timing.dragDuration + 0.55 + 0.9
        guard timing.perCard >= minimum else {
            throw ScenarioError(line: 0,
                                message: "perCard \(timing.perCard) is under the \(minimum) a card needs to land")
        }
    }
}

struct ScenarioError: Error, Equatable {
    let line: Int
    let message: String
}

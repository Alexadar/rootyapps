import Foundation

/// What one screen can tell a language model about itself.
///
/// ## The three layers, and why all three are needed
///
/// A model handed `Sun 26.07` can say nothing useful. It needs:
///
/// 1. **Where we are** — which screen, for what moment and place, in which zodiac. Without this the
///    same numbers could be a live sky, a birth chart or a projection years away.
/// 2. **What the fields mean** — from `Glossary`. A title is not a meaning: told only that a column
///    is called "Dignity", a model invents a definition, and inventing beside an oracle-tested
///    engine is the one failure this app cannot afford.
/// 3. **The data itself** — ranked and truncated, because the ceiling is 4,096 tokens shared
///    between the prompt and the answer.
///
/// ## Truncation is disclosed, not hidden
///
/// `omitted` travels with the rows and is rendered into the prompt. A model shown four of a hundred
/// and four events, and *not* told so, will answer as though it saw them all — confidently, and
/// wrongly, about what is "coming up". Saying "4 of 104, nearest to now" costs a dozen tokens and
/// converts a false answer into a true and partial one.
///
/// This is the same rule the rest of the app already follows: polar absence is stated rather than
/// filled in, the void-of-course body set is named on screen, and the export sheet shows its count
/// before it writes anything.
public struct ScreenContext: Hashable, Sendable {

    /// Which surface this is. Stable, so a test can assert every screen provides one.
    public let screen: ScreenID
    /// What the user has actually entered — the model must not suggest a chart reading to someone
    /// who has entered no birth data.
    public let gate: Gate
    /// One line naming the moment, the place and the frame.
    public let situation: String
    /// The vocabulary this screen uses, with meanings.
    public let schema: [Glossary.Entry]
    /// The visible data, already ranked and cut.
    public let rows: [ContextRow]
    /// What was left out, or nil when everything is here.
    public let omitted: Omission?

    public init(screen: ScreenID, gate: Gate, situation: String,
                schema: [Glossary.Entry], rows: [ContextRow], omitted: Omission? = nil) {
        self.screen = screen
        self.gate = gate
        self.situation = situation
        self.schema = schema
        self.rows = rows
        self.omitted = omitted
    }

    // MARK: - Pieces

    public struct ScreenID: Hashable, Sendable {
        /// Stable identifier, e.g. `sky.wheel`. Never localized — it is a key, not a label.
        public let id: String
        /// What a person would call it, e.g. "Sky · chart wheel".
        public let title: String

        public init(id: String, title: String) {
            self.id = id
            self.title = title
        }
    }

    /// What the user has given the app, which decides what can honestly be shown or suggested.
    public enum Gate: String, Hashable, Sendable, CaseIterable {
        case nothing        // a brand-new install
        case place          // a location, no birth data
        case oneChart
        case twoCharts
        case chartAndRange

        public var explanation: String {
            switch self {
            case .nothing:       "The user has entered nothing yet — no place and no birth details."
            case .place:         "The user has set a place but no birth details."
            case .oneChart:      "The user has one saved birth chart."
            case .twoCharts:     "The user has two birth charts open for comparison."
            case .chartAndRange: "The user has a birth chart and a date range."
            }
        }
    }

    /// One visible item: a title plus its named fields.
    public struct ContextRow: Hashable, Sendable {
        public let title: String
        public let fields: [Field]

        public init(title: String, fields: [Field]) {
            self.title = title
            self.fields = fields
        }

        public struct Field: Hashable, Sendable {
            public let name: String
            public let value: String
            public init(_ name: String, _ value: String) {
                self.name = name
                self.value = value
            }
        }
    }

    /// What was dropped, and on what basis.
    public struct Omission: Hashable, Sendable {
        public let shown: Int
        public let total: Int
        /// How the shown ones were chosen — "nearest to now", "tightest orb". Never "the first few":
        /// if that is the honest answer, the ranking is wrong.
        public let ranking: String

        public init(shown: Int, total: Int, ranking: String) {
            self.shown = shown
            self.total = total
            self.ranking = ranking
        }

        public var hidden: Int { Swift.max(0, total - shown) }
    }

    // MARK: - Rendering

    /// The context as the text the model actually receives.
    ///
    /// Deliberately flat and label-led rather than JSON: JSON spends a meaningful share of a 4,096
    /// token budget on braces and quotes, and the model gains nothing from them here — there is no
    /// nesting to disambiguate.
    public var promptText: String {
        var out: [String] = []
        out.append("SCREEN: \(screen.title)")
        out.append("SITUATION: \(situation)")
        out.append("USER DATA: \(gate.explanation)")

        if !schema.isEmpty {
            out.append("")
            out.append("WHAT THE TERMS MEAN:")
            out += schema.map { "- \($0.term): \($0.meaning)" }
        }

        out.append("")
        if let omitted {
            out.append("VISIBLE DATA (\(omitted.shown) of \(omitted.total), chosen by \(omitted.ranking)):")
        } else {
            out.append("VISIBLE DATA (all \(rows.count)):")
        }
        out += rows.map { row in
            let fields = row.fields.map { "\($0.name) \($0.value)" }.joined(separator: " · ")
            return fields.isEmpty ? row.title : "\(row.title): \(fields)"
        }

        // Stated last so it is the final thing read before the question — the position a model is
        // least likely to lose track of.
        if let omitted, omitted.hidden > 0 {
            out.append("")
            out.append("NOT SHOWN: \(omitted.hidden) more, not included because of the size limit. "
                       + "Do not describe them or imply the list is complete.")
        }
        return out.joined(separator: "\n")
    }
}

/// A surface that can describe itself.
public protocol ScreenContextProviding {
    /// - Parameter rowLimit: the most rows to include. The caller may lower it further after
    ///   measuring real tokens; providers must never exceed it.
    func screenContext(rowLimit: Int) -> ScreenContext
}

public extension ScreenContextProviding {
    /// Four rows is the default everywhere, deliberately.
    ///
    /// Not because four is what fits — often far more would. A short, ranked answer about four
    /// representative items is more useful than a long one the model skims, and holding every
    /// screen to the same small number means the truncation path is the *normal* path and gets
    /// exercised constantly, rather than being a rare branch that breaks unnoticed on the one
    /// screen with a hundred rows.
    func screenContext() -> ScreenContext { screenContext(rowLimit: 4) }
}

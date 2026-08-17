import Foundation

/// The *Surprise me* corpus.
///
/// **This fills the field visibly; it never generates directly.** That is the design decision, and
/// the reason is teaching: a user who does not know what to type learns what a good prompt looks
/// like by reading one, and can then edit a word and make it theirs. A button that silently
/// generated would hand them a picture and no vocabulary — the second tap would be the same
/// mystery as the first.
///
/// ### Palettes, because a flat corpus produced nonsense or produced one mood
///
/// The first version composed from three flat lists — subject × treatment × light — which gave
/// sixteen hundred combinations that were **all the same picture**: muted photographic naturalism.
/// Slate, fog, moss, birch, chalk, salt flats. The variety was arithmetic rather than felt, and it
/// reached none of the categories people actually put on a phone.
///
/// The obvious fix — adding "a gas giant's cloud bands" and "neon" to the flat lists — produces
/// *"a gas giant's cloud bands in warm lamplight, cyanotype"*. Every axis multiplies with every
/// other, so widening a flat corpus buys nonsense at exactly the rate it buys range.
///
/// So the corpus is grouped. Each `Palette` carries the subjects, lights and treatments that belong
/// together, and a suggestion is composed **within one**. Range and coherence stop trading against
/// each other, and each palette is a category someone would actually browse.
///
/// ### Which categories, and why those
///
/// From how the large wallpaper apps organise their catalogues and what their users ask for:
/// **dark and near-black**, **space**, **city at night** and **abstract** dominate, with 2026 trend
/// reporting adding tonal single-hue abstracts, Art Deco geometrics in warm jewel tones, oversized
/// florals on moody grounds, and painterly brushwork. Dark earns the largest palette twice over: it
/// is the most-requested category, and near-black pixels cost an OLED panel almost nothing.
///
/// ### The format is a constraint on every line in here
///
/// The master is square and gets cropped to roughly the middle 46 % of its width, with a clock and a
/// grid of icons over the top. So subjects are written for a **quiet centre-top with the interest in
/// the texture**, and nothing depends on something happening at the left or right edge — that part
/// of the picture does not survive. It is also why there are no people: a face is where these models
/// fail most visibly, and a wallpaper with a face on it is a photograph.
public struct SurpriseMe: Sendable {

    /// One coherent corner of the corpus: things that go together, and the light and handling that
    /// suit them.
    public struct Palette: Sendable, Equatable {
        /// What a person would call this shelf. Not shown anywhere yet — it exists so the grouping
        /// is legible in code and so a future browse-by-category has something to hang on.
        public let name: String
        public let subjects: [String]
        public let lights: [String]
        public let treatments: [String]

        public init(name: String, subjects: [String], lights: [String], treatments: [String]) {
            self.name = name
            self.subjects = subjects
            self.lights = lights
            self.treatments = treatments
        }

        public var combinationCount: Int { subjects.count * lights.count * treatments.count }
    }

    /// The house corpus, read once from `sd15cn_sampleprompts.yaml`.
    ///
    /// A bundled resource that fails to parse is a build mistake, not a runtime condition, and the
    /// tests load and count it so it cannot ship broken. Trapping here rather than degrading to an
    /// empty corpus is deliberate: a *Surprise me* that silently does nothing is the "control that
    /// appears broken" this whole file is written against.
    public static let corpus: PromptCorpus = {
        do { return try PromptCorpus.load() }
        catch { fatalError("the bundled prompt corpus is unusable: \(error)") }
    }()

    public static var palettes: [Palette] { corpus.palettes }
    public static var curated: [String] { corpus.curated }

    /// Every subject in the corpus, flattened. The composer never uses this — it would cross
    /// palettes, which is the nonsense the grouping exists to prevent.
    public static var subjects: [String] { palettes.flatMap(\.subjects) }
    public static var lights: [String] { Array(Set(palettes.flatMap(\.lights))).sorted() }
    public static var treatments: [String] { Array(Set(palettes.flatMap(\.treatments))).sorted() }

    /// Total distinct suggestions. Worth knowing: it must comfortably exceed the number of times a
    /// user will tap before they either edit one or give up.
    public static var combinationCount: Int {
        palettes.reduce(0) { $0 + $1.combinationCount } + curated.count
    }

    /// How often a tap returns a hand-written prompt rather than a composed one.
    ///
    /// One in four. Enough that the best-written examples come round often, not so much that twenty
    /// strings start repeating — which is the one thing the composed corpus is genuinely good at
    /// preventing.
    static let curatedShare = 0.25

    public init() {}

    /// A suggestion is a *pair*. Half of what makes a generated picture good is what it was told to
    /// avoid, and someone learning to prompt from this control should see both halves — otherwise
    /// they learn that a prompt is one box and the negative stays a mystery they never touch.
    public struct Suggestion: Sendable, Equatable {
        public let prompt: String
        public let negative: String
    }

    /// The prompt, paired with the negative that suits it.
    ///
    /// Figurative subjects get the character-art negative; everything else gets the wallpaper one.
    /// The corpus has no people in it today — this is the rule for when it does.
    public func suggestionPair(using generator: inout some RandomNumberGenerator,
                               avoiding previous: String? = nil) -> Suggestion {
        let text = suggestion(using: &generator, avoiding: previous)
        let figurative = ["portrait", "figure", "hands", "face", "dancer"]
        let negative = figurative.contains(where: text.contains)
            ? NegativePrompt.figurative : NegativePrompt.wallpaperDefault
        return Suggestion(prompt: text, negative: negative)
    }

    /// One suggestion, drawn with the caller's generator.
    ///
    /// - Parameter avoiding: the suggestion currently in the field. Re-tapping *Surprise me* must
    ///   visibly change something — a control that sometimes appears to do nothing reads as broken —
    ///   so a repeat is rolled again.
    public func suggestion(using generator: inout some RandomNumberGenerator,
                           avoiding previous: String? = nil) -> String {
        // Bounded: with thousands of combinations a collision streak of eight is beyond improbable,
        // and an unbounded loop over a degenerate corpus would hang the main thread.
        for _ in 0..<8 {
            let candidate = compose(using: &generator)
            if candidate != previous { return candidate }
        }
        return compose(using: &generator)
    }

    private func compose(using generator: inout some RandomNumberGenerator) -> String {
        if Double.random(in: 0..<1, using: &generator) < Self.curatedShare {
            return Self.curated.randomElement(using: &generator)!
        }
        // Within one palette, never across. Crossing them is how "a gas giant's cloud bands in warm
        // lamplight, cyanotype" gets written.
        let palette = Self.palettes.randomElement(using: &generator)!
        let subject = palette.subjects.randomElement(using: &generator)!
        let light = palette.lights.randomElement(using: &generator)!
        let treatment = palette.treatments.randomElement(using: &generator)!
        return "\(subject) \(light), \(treatment)"
    }
}

/// What the app considers a usable prompt.
///
/// The only rule that matters is that Create stays disabled until there is something to generate
/// from — the design's lighter fill and 35 % label. Everything else is trimming, because a prompt
/// ending in a newline is the same prompt.
public enum PromptRules {
    /// Long enough to mean something. One character is a typo, not a prompt.
    public static let minimumLength = 2
    /// Far beyond any real prompt; exists so a pasted document cannot be sent to a pipeline that
    /// will truncate it at 77 tokens anyway and silently ignore the rest.
    public static let maximumLength = 500

    public static func normalised(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
           .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    public static func isUsable(_ raw: String) -> Bool {
        let text = normalised(raw)
        return text.count >= minimumLength && text.count <= maximumLength
    }

    /// What actually goes to the generator.
    ///
    /// Truncated, not rejected: someone who pastes a paragraph gets a picture from the front of it
    /// rather than an error. The cap is far beyond any real prompt and exists because CLIP would
    /// silently drop everything past 77 tokens anyway — this at least keeps the size of what is sent
    /// honest.
    public static func prepared(_ raw: String) -> String {
        String(normalised(raw).prefix(maximumLength))
    }
}

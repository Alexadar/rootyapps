import Testing
import Foundation
@testable import PromptKit

/// A reproducible generator for the suite. The package deliberately ships none — the app supplies
/// GenerationKit's seeded one — so the tests bring their own rather than depending on system
/// randomness, which would make failures unreproducible.
private struct TestGenerator: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// ORACLES:
///  • INVARIANT — the same seed always yields the same suggestion. Without this, "regenerate from
///    this prompt" and every screenshot are unreproducible.
///  • BEHAVIOUR — re-tapping must visibly change the field. A control that sometimes appears to do
///    nothing reads as broken, and this is the first control a new user touches.
///  • INVARIANT — every suggestion names a light, which is the one thing beginners omit and the
///    thing that most changes the result.
/// MODEL CAVEAT: nothing here judges whether a prompt produces a *good* picture — that depends on
/// the model, which does not exist yet. These are structural properties of the corpus.
@Suite("SurpriseMe — the corpus and the re-roll")
struct SurpriseMeTests {

    @Test("the corpus is large enough that a user will not see a repeat")
    func corpusSize() {
        #expect(SurpriseMe.combinationCount >= 1000, "got \(SurpriseMe.combinationCount)")
        #expect(!SurpriseMe.subjects.isEmpty)
        #expect(!SurpriseMe.treatments.isEmpty)
        #expect(!SurpriseMe.lights.isEmpty)
    }

    @Test("the same seed replays the same suggestion")
    func deterministic() {
        var a = TestGenerator(seed: 7), b = TestGenerator(seed: 7)
        let s = SurpriseMe()
        #expect(s.suggestion(using: &a) == s.suggestion(using: &b))
    }

    @Test("re-tapping never leaves the field unchanged")
    func neverRepeatsItself() {
        var g = TestGenerator(seed: 1)
        let s = SurpriseMe()
        var current = s.suggestion(using: &g)
        for tap in 0..<200 {
            let next = s.suggestion(using: &g, avoiding: current)
            #expect(next != current, "tap \(tap) produced no visible change")
            current = next
        }
    }

    @Test("a suggestion is either a hand-written one or a well-formed composed one")
    func everySuggestionIsComplete() {
        var g = TestGenerator(seed: 99)
        let s = SurpriseMe()
        var curated = 0, composed = 0
        for _ in 0..<400 {
            let text = s.suggestion(using: &g)
            if SurpriseMe.curated.contains(text) { curated += 1; continue }
            composed += 1
            #expect(SurpriseMe.subjects.contains { text.hasPrefix($0) }, "no subject in: \(text)")
            #expect(SurpriseMe.lights.contains { text.contains($0) }, "no light in: \(text)")
            #expect(SurpriseMe.treatments.contains { text.hasSuffix($0) }, "no treatment in: \(text)")
        }
        // Both sources must actually appear. A share that silently collapsed to one would leave
        // either the researched categories unreachable or the corpus repeating twenty strings.
        #expect(curated > 40, "hand-written prompts barely appeared: \(curated) of 400")
        #expect(composed > 40, "composed prompts barely appeared: \(composed) of 400")
    }

    /// ORACLE: the hand-written set exists to cover what the composed corpus cannot — the categories
    /// people actually put on a phone. A duplicate, or a prompt too long to survive CLIP, is a
    /// silent loss of one twentieth of that coverage.
    @Test("the hand-written set is twenty distinct, usable prompts")
    func curatedSetIsWellFormed() {
        #expect(SurpriseMe.curated.count == 20)
        #expect(Set(SurpriseMe.curated).count == 20, "a duplicate hand-written prompt")

        for text in SurpriseMe.curated {
            #expect(PromptRules.isUsable(text), "unusable: \(text)")
            #expect(PromptRules.prepared(text) == text, "needs normalising: \(text)")
            // CLIP truncates at 77 tokens without saying so. Roughly four characters a token, so
            // anything past ~250 characters is losing its tail — and the tail is where the light
            // and the treatment are.
            #expect(text.count < 250, "long enough to lose its tail to CLIP: \(text)")
            #expect(!text.contains("  "), "double space in: \(text)")
        }
    }

    @Test("the hand-written set covers the categories the composed corpus misses")
    func curatedSetCoversTheResearchedCategories() {
        // Not a style preference: these are the categories the large wallpaper apps are organised
        // around. The composed corpus is entirely muted photographic naturalism and reaches none of
        // them, which is what made every tap feel like the same picture.
        let all = SurpriseMe.curated.joined(separator: " | ").lowercased()
        for category in ["black", "space", "neon", "gradient", "deco", "watercolour", "chrome"] {
            #expect(all.contains(category), "no prompt covers \(category)")
        }

        // Dark carries the most weight — most-requested, and near-free on an OLED panel.
        let dark = SurpriseMe.curated.filter {
            let t = $0.lowercased()
            return t.contains("black") || t.contains("night") || t.contains("shade")
                || t.contains("new moon") || t.contains("deep shade")
        }
        #expect(dark.count >= 4, "only \(dark.count) dark prompts")
    }

    @Test("a suggestion is always accepted by the rules that gate the Create button")
    func suggestionsAreAlwaysUsable() {
        var g = TestGenerator(seed: 4242)
        let s = SurpriseMe()
        for _ in 0..<300 {
            let text = s.suggestion(using: &g)
            #expect(PromptRules.isUsable(text), "Surprise me produced an unusable prompt: \(text)")
            #expect(PromptRules.prepared(text) == text, "a suggestion should need no normalising")
        }
    }

    @Test("the corpus has no duplicates, which would skew the roll")
    func noDuplicates() {
        #expect(Set(SurpriseMe.subjects).count == SurpriseMe.subjects.count)
        #expect(Set(SurpriseMe.treatments).count == SurpriseMe.treatments.count)
        #expect(Set(SurpriseMe.lights).count == SurpriseMe.lights.count)
    }

    @Test("the roll actually spreads across the corpus")
    func coverage() {
        var g = TestGenerator(seed: 11)
        let s = SurpriseMe()
        var seenSubjects = Set<String>()
        var seenCurated = Set<String>()
        // 900, not 400: half the rolls now go to the hand-written set, so the composed corpus gets
        // half the draws it used to and 400 no longer reaches all twenty subjects.
        for _ in 0..<900 {
            let text = s.suggestion(using: &g)
            if let subject = SurpriseMe.subjects.first(where: { text.hasPrefix($0) }) {
                seenSubjects.insert(subject)
            }
            if SurpriseMe.curated.contains(text) { seenCurated.insert(text) }
        }
        #expect(seenSubjects.count == SurpriseMe.subjects.count,
                "only \(seenSubjects.count) of \(SurpriseMe.subjects.count) subjects ever appeared")
        #expect(seenCurated.count == SurpriseMe.curated.count,
                "only \(seenCurated.count) of \(SurpriseMe.curated.count) hand-written prompts appeared")
    }
}

/// ORACLES:
///  • SPEC — the design's empty state disables Create until there is a prompt. `isUsable` is the
///    single definition of "there is a prompt"; if it and the button ever disagree, the button lies.
///  • INVARIANT — normalising is idempotent, so a stored prompt round-trips unchanged.
@Suite("PromptRules — what enables the Create button")
struct PromptRulesTests {

    @Test("whitespace alone is not a prompt")
    func whitespaceIsEmpty() {
        for blank in ["", " ", "\n", "\t\t", "   \n  "] {
            #expect(!PromptRules.isUsable(blank), "accepted \(blank.debugDescription)")
        }
    }

    @Test("one character is a typo, two is a prompt")
    func minimumLength() {
        #expect(!PromptRules.isUsable("a"))
        #expect(PromptRules.isUsable("ok"))
    }

    @Test("surrounding whitespace and runs of spaces are collapsed")
    func normalisation() {
        #expect(PromptRules.normalised("  molten   glass \n poppies  ") == "molten glass poppies")
        #expect(PromptRules.normalised("a\tb") == "a b")
    }

    @Test("normalising twice changes nothing")
    func idempotent() {
        let messy = "  ink   dissolving \n\n in water  "
        let once = PromptRules.normalised(messy)
        #expect(PromptRules.normalised(once) == once)
    }

    @Test("emoji and quotes survive, because people type them")
    func unicodeSurvives() {
        let text = "a “paper” crane 🕊 at dusk"
        #expect(PromptRules.isUsable(text))
        #expect(PromptRules.prepared(text) == text)
    }

    @Test("a pasted document is truncated rather than sent whole")
    func maximumLength() {
        let huge = String(repeating: "wallpaper ", count: 200)   // 2000 characters
        #expect(!PromptRules.isUsable(huge))
        #expect(PromptRules.prepared(huge).count == PromptRules.maximumLength)
    }
}

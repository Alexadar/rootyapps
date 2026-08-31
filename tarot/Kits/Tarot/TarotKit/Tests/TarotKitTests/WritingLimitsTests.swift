import Testing
@testable import TarotKit

/// The runaway-generation defences.
///
/// Reported from a device 2026-08-25: the model produced long, endlessly repeating text, and the
/// next draw then produced nothing, because the unbounded request was still holding the model
/// service. These limits are what makes that impossible rather than merely unlikely.
///
/// They live in the Kit rather than beside the writer for two reasons: they are pure policy with
/// no Foundation Models dependency, and the app's XCTest target cannot currently be run on this
/// machine (Xcode's test coordination hangs before launching a host), while `swift test` here
/// runs in seconds.
@Suite("Writing limits")
struct WritingLimitsTests {

    @Test("every method carries a token ceiling that fits a full reading but still bounds a loop")
    func ceilings() {
        for method in Spread.all {
            let cap = WritingLimits.maximumTokens(for: method)
            let needed = WritingLimits.expectedCharacters(for: method) / 4   // ~4 chars per token
            #expect(cap > needed,
                    "\(method.id): ceiling \(cap) would truncate a full reading (~\(needed) tokens)")
            #expect(cap < needed * 4,
                    "\(method.id): ceiling \(cap) is too loose to stop a runaway")
        }
    }

    @Test("the ceiling scales with the method")
    func ceilingScales() {
        #expect(WritingLimits.maximumTokens(for: .dailyCard) < WritingLimits.maximumTokens(for: .celticCross))
        #expect(WritingLimits.maximumTokens(for: .threeCard) < WritingLimits.maximumTokens(for: .crossroads))
    }

    @Test("a sentence repeated over and over is degenerate — the exact shape reported")
    func repetitionIsCaught() {
        let loop = Array(repeating: "You are in a good place and you feel secure.", count: 6)
            .joined(separator: " ")
        #expect(WritingLimits.isDegenerate(loop, expectedCharacters: 1600))
    }

    /// The other shape: never terminating. Every sentence differs, so a repeat detector alone
    /// would pass it — length has to be an independent signal.
    @Test("output that simply never ends is degenerate even without repetition")
    func runawayLengthIsCaught() {
        let long = (0..<200).map { "Sentence number \($0) about the card and its meaning." }
            .joined(separator: " ")
        #expect(WritingLimits.isDegenerate(long, expectedCharacters: 1600))
    }

    /// The guard must not re-roll good text forever.
    @Test("a real reading passes both checks")
    func realReadingSurvives() {
        let real = """
        This card speaks of stability, wealth, and family. It is a testament to hard work, \
        dedication, and a sense of belonging that brings you peace. It says that you have \
        achieved what you deserve, and that you are surrounded by love and support. You are \
        prosperous, and you feel secure in your accomplishments. This card speaks of change, \
        opportunity, and the unknown. It is a reminder that life is full of surprises.
        """
        #expect(!WritingLimits.isDegenerate(real, expectedCharacters: 1600))
    }

    @Test("short repeated fragments are ordinary prose, not a loop")
    func shortFragmentsTolerated() {
        let fine = "Yes. Yes. Yes. The card speaks of patience and of waiting for the right moment."
        #expect(!WritingLimits.isDegenerate(fine, expectedCharacters: 1600))
    }

    /// Stated explicitly so a refactor cannot drift the threshold unnoticed.
    @Test("three repeats trip it, two do not")
    func repeatThreshold() {
        let s = "The cards suggest a period of reflection and steady work ahead of you."
        let pad = " Some other sentence entirely, long enough to count as one."
        #expect(!WritingLimits.isDegenerate([s, s, pad, pad].joined(separator: " "), expectedCharacters: 4000))
        #expect(WritingLimits.isDegenerate([s, s, s, pad].joined(separator: " "), expectedCharacters: 4000))
    }
}

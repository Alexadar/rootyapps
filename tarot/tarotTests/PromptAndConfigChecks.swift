import XCTest
import TarotKit
import CardMotionKit
@testable import Tarot

final class PromptAndConfigChecks: XCTestCase {

    private func makeReading(reversals: Bool) -> Reading {
        Shuffler.draw(deck: .classic1909, spread: .threeCard, seed: 7,
                      allowsReversals: reversals, date: Date(timeIntervalSince1970: 0))
    }

    /// The prompt names every card, orientation and position; the instructions hold the
    /// register: reflective, never predictive, and free of the trademarked brand.
    func testPromptNamesEveryCardPositionAndOrientation() {
        for reversals in [true, false] {
            let reading = makeReading(reversals: reversals)
            let prompt = ReadingPrompt.prompt(reading: reading, deck: .classic1909, spread: .threeCard)
            for drawn in reading.cards {
                XCTAssertTrue(prompt.contains(drawn.card.displayName), "missing \(drawn.card.displayName)")
                XCTAssertTrue(prompt.contains(drawn.orientation.displayName.lowercased()))
            }
            for position in Spread.threeCard.positions {
                XCTAssertTrue(prompt.contains(position.name))
            }
        }
    }

    /// The guardrail label table, held to what was measured (2026-08, macOS 26.5): the
    /// literal names that the on-device safety layer refuses must never reach a prompt,
    /// The Devil ships glossed, and safe mode names no card at all.
    func testRefusedCardNamesNeverReachThePrompt() {
        let risky: [(Card, String)] = [
            (.minor(.swords, .five), "Five of Swords"),
            (.minor(.swords, .ten), "Ten of Swords"),
            (.major(12), "The Hanged Man"),
        ]
        for (card, literal) in risky {
            let reading = Reading(date: Date(timeIntervalSince1970: 0), deckID: "classic-1909",
                                  spreadID: "three-card", seed: 1, allowsReversals: true,
                                  cards: [DrawnCard(card: card, orientation: .upright, positionIndex: 0),
                                          DrawnCard(card: .major(19), orientation: .upright, positionIndex: 1),
                                          DrawnCard(card: .minor(.cups, .six), orientation: .upright, positionIndex: 2)])
            let prompt = ReadingPrompt.prompt(reading: reading, deck: .classic1909, spread: .threeCard)
            XCTAssertFalse(prompt.contains(literal), "\(literal) reached the prompt — measured refusal")
        }
        // The Devil keeps its name, glossed.
        XCTAssertTrue(ReadingPrompt.promptLabel(for: .major(15)).contains("The Devil"))
        XCTAssertTrue(ReadingPrompt.promptLabel(for: .major(15)).contains("("))
    }

    func testSafeModeNamesNoCard() {
        for card in Deck.classic1909.cards {
            let label = ReadingPrompt.promptLabel(for: card, safe: true)
            XCTAssertFalse(label.contains(card.displayName),
                           "safe mode leaked the name for \(card.displayName)")
            XCTAssertFalse(label.lowercased().contains("swords"),
                           "safe mode leaked a suit name for \(card.displayName)")
        }
    }

    /// The question reaches the prompt when present, is absent when absent, and never
    /// reaches the shuffle (TarotKit proves the deal side; this proves the prompt side).
    func testQuestionThreadsIntoThePrompt() {
        var reading = makeReading(reversals: false)
        var prompt = ReadingPrompt.prompt(reading: reading, deck: .classic1909, spread: .threeCard)
        XCTAssertFalse(prompt.contains("reader's question"))
        reading.question = "Should I take the new job?"
        prompt = ReadingPrompt.prompt(reading: reading, deck: .classic1909, spread: .threeCard)
        XCTAssertTrue(prompt.contains("Should I take the new job?"))
        XCTAssertTrue(prompt.contains("speak to it"))
        XCTAssertTrue(ReadingPrompt.instructions(deck: .classic1909, spread: .threeCard)
                        .contains("never as an answer about what will happen"),
                      "questions must stay non-predictive")
    }

    /// The reading matches the UI — localized or English, never a mismatch: the language
    /// directive appears exactly when a language is passed (the FM writer only passes one
    /// when the rendered UI language is also in the model's supported set).
    @MainActor
    func testLanguageDirectiveAppearsOnlyWhenAskedFor() {
        let reading = makeReading(reversals: false)
        let english = ReadingPrompt.prompt(reading: reading, deck: .classic1909,
                                           spread: .threeCard)
        XCTAssertFalse(english.contains("Write the entire reading in"),
                       "no directive means English — the model's default")
        let german = ReadingPrompt.prompt(reading: reading, deck: .classic1909,
                                          spread: .threeCard, language: "German")
        XCTAssertTrue(german.contains("Write the entire reading in German."))
        // On this en-rendered test host the resolver must decline to pick a language.
        XCTAssertNil(FoundationModelsWriter.readingLanguage())
    }

    func testInstructionsForbidPredictionAndHoldTheRegister() {
        let text = ReadingPrompt.instructions(deck: .classic1909, spread: .threeCard).lowercased()
        XCTAssertTrue(text.contains("never predict"), "the non-prediction rule must be explicit")
        XCTAssertTrue(text.contains("classic 1909"), "the deck is described as the classic 1909 deck")
        XCTAssertFalse(text.contains("rider"), "trademarked brand in the instructions")
        XCTAssertTrue(text.contains("reversed"), "reversed cards need their own framing")
    }

    /// The sampling-seed range must never exceed Int32.max — the measured boundary where
    /// the on-device model service rejects the request (seed 2147483647 streams,
    /// 2147483648 fails with ModelManagerError 1032; macOS 26.5). If an SDK update lifts
    /// this, widen the range deliberately — never by accident.
    @MainActor
    func testInterpretationSeedStaysBelowTheMeasuredServiceBoundary() {
        XCTAssertLessThanOrEqual(AppModel.interpretationSeedRange.upperBound, UInt64(Int32.max))
        XCTAssertGreaterThan(AppModel.interpretationSeedRange.lowerBound, 0)
    }

    /// Reversals are parked: whatever the stored user setting says, a draw comes out
    /// upright while the feature flag is off — both directions of the stored setting.
    @MainActor
    func testReversalsParkedMeansAlwaysUpright() {
        XCTAssertFalse(AppModel.reversalsFeatureEnabled)
        XCTAssertFalse(AppModel.effectiveAllowsReversals(true))
        XCTAssertFalse(AppModel.effectiveAllowsReversals(false))
    }

    /// Reduce Motion maps to the kernel mode — both directions (the dead-toggle rule).
    @MainActor
    func testReduceMotionMapsToKernelMode() {
        XCTAssertFalse(AppModel.config(methodID: "three-card", reduceMotion: false).reduceMotion)
        XCTAssertTrue(AppModel.config(methodID: "three-card", reduceMotion: true).reduceMotion)
        // …and everything else about the two configs is identical: the mode changes
        // presentation, never rules.
        var a = AppModel.config(methodID: "three-card", reduceMotion: true)
        a.reduceMotion = false
        XCTAssertEqual(a, AppModel.config(methodID: "three-card", reduceMotion: false))
    }

    /// The FM availability enum maps one-to-one onto the UI states — no branch collapsed.
    @MainActor
    func testEveryAvailabilityBranchHasADistinctState() {
        let reasons: [WriterAvailability] = [.deviceNotEligible, .notEnabled, .modelNotReady]
        var states = Set<String>()
        for reason in reasons {
            let composer = ReadingComposer()
            composer.start(reading: makeReading(reversals: true), deck: .classic1909,
                           spread: .threeCard, writer: MockWriter(availability: reason))
            states.insert(String(describing: composer.state))
        }
        XCTAssertEqual(states.count, 3, "unavailability reasons collapsed: \(states)")
    }
}

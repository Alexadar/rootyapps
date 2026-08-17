import XCTest
@testable import RecipeKit

/// **The invariant the whole app hangs on.**
///
/// "Sliding to 0 *is* the original, bit for bit" and "backing off never re-runs the model" are two
/// separate promises, and both are made here rather than in a view.
final class BlendTests: XCTestCase {

    private func passed(_ scope: Scope = .whole, at rendered: Strength) -> ScopeEdit {
        var edit = ScopeEdit(scope: scope)
        edit.markRendered(at: rendered)
        return edit
    }

    // MARK: Zero is the original — as a case, not as a fraction

    func testZeroIsADistinctCaseAndNotABlendAtZero() {
        var edit = passed(at: .subtle)
        edit.strength = .zero

        XCTAssertEqual(edit.outcome, .original)
        XCTAssertNil(edit.outcome.fraction,
                     "a fraction of 0 would send the original through a composite and an encode — "
                     + "the one path that can move a channel by a bit")
    }

    func testTheWholeRecipeCollapsesToOriginalWhenNothingContributes() {
        var recipe = makeRecipe()
        recipe.update(.whole) { $0.markRendered(at: .balanced) }
        XCTAssertFalse(recipe.composite().isOriginal)

        recipe.update(.whole) { $0.strength = .zero }
        XCTAssertEqual(recipe.composite(), .original)
    }

    func testAnUntouchedRecipeIsTheOriginal() {
        XCTAssertEqual(makeRecipe().composite(), .original)
        XCTAssertFalse(makeRecipe().hasVisibleEnhancement)
    }

    func testRevertingReturnsToTheOriginalAndKeepsTheDialWhereItWas() {
        var recipe = makeRecipe()
        recipe.update(.whole) { $0.markRendered(at: .strong) }
        recipe.revertAll()

        XCTAssertEqual(recipe.composite(), .original)
        XCTAssertEqual(recipe.edit(for: .whole)?.strength, .strong,
                       "pressing Enhance again should do the obvious thing, not reset the dial")
        XCTAssertNil(recipe.edit(for: .whole)?.rendered)
    }

    // MARK: Backing off is free; pushing past what was rendered is not

    func testBackingOffIsAFreeBlendOfTheRenderedPass() {
        var edit = passed(at: .balanced)          // rendered at 55

        edit.strength = .balanced
        XCTAssertEqual(edit.outcome, .blend(1))

        edit.strength = Strength(27.5)
        XCTAssertEqual(edit.outcome.fraction!, 0.5, accuracy: 1e-12)

        edit.strength = .whisper                   // 15 of 55
        XCTAssertEqual(edit.outcome.fraction!, 15.0 / 55.0, accuracy: 1e-12)

        for outcome in [BlendOutcome.blend(1), .blend(0.5)] {
            XCTAssertFalse(outcome.requiresRerun, "backing off must never cost another pass")
        }
    }

    func testPushingAboveTheRenderedStrengthDemandsARerunRatherThanLying() {
        var edit = passed(at: .subtle)             // rendered at 35
        edit.strength = .strong                    // asked for 80

        XCTAssertEqual(edit.outcome, .needsRerun(at: .strong))
        XCTAssertNil(edit.outcome.fraction,
                     "showing the 35 pass while the dial reads 80 would be a lie about the number "
                     + "under the user's thumb")
    }

    func testTheRecipeNamesEveryScopeThatNeedsARerun() {
        var recipe = makeRecipe(edits: [])
        recipe.update(.background) { $0.markRendered(at: .whisper); $0.strength = .strong }
        recipe.update(.subject) { $0.markRendered(at: .strong); $0.strength = .subtle }

        XCTAssertEqual(recipe.scopesNeedingRerun, [.background])
    }

    // MARK: A pass at zero is not a pass

    func testAPassCannotBeRecordedAtZero() {
        var edit = ScopeEdit(scope: .whole)
        edit.markRendered(at: .zero)

        XCTAssertNil(edit.rendered)
        XCTAssertFalse(edit.hasPass)
        XCTAssertEqual(edit.outcome, .original,
                       "believing in an enhanced image that was never rendered is how a blank "
                       + "frame ships")
    }

    func testEveryDetentPlusZeroAndFullRoundTripThroughTheOutcomeRule() {
        let dialPositions: [Strength] = [.zero, .whisper, .subtle, .balanced, .strong, .full]
        var edit = passed(at: .full)               // rendered at the top of the rail

        for position in dialPositions {
            edit.strength = position
            switch position {
            case .zero:
                XCTAssertEqual(edit.outcome, .original, "at \(position.value)")
            default:
                XCTAssertEqual(edit.outcome.fraction!, position.value / 100, accuracy: 1e-12,
                               "at \(position.value)")
            }
        }
    }
}

// MARK: - Support

func makeRecipe(edits: [ScopeEdit] = [ScopeEdit(scope: .whole)]) -> EditRecipe {
    EditRecipe(sourceFilename: "original.heic",
               sourceDigest: String(repeating: "a", count: 64),
               seed: 0x5EED,
               createdAt: Date(timeIntervalSince1970: 1_786_000_000),
               appVersion: "1.0",
               edits: edits)
}

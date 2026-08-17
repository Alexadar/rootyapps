import XCTest
@testable import RecipeKit

/// Scopes singly, scopes composed, and the mask pairing that keeps subject and background exact
/// complements.
final class ScopeCompositionTests: XCTestCase {

    func testOnlyWholePhotoGoesWithoutAMask() {
        XCTAssertFalse(Scope.whole.requiresMask)
        for scope in [Scope.subject, .background, .brush] {
            XCTAssertTrue(scope.requiresMask, "\(scope)")
            XCTAssertNotNil(MaskRef.forScope(scope))
        }
        XCTAssertNil(MaskRef.forScope(.whole),
                     "whole photo is the absence of masking, not an all-white mask")
    }

    func testSubjectAndBackgroundAreOneMaskReadTwoWays() {
        let subject = MaskRef.forScope(.subject)!
        let background = MaskRef.forScope(.background)!

        XCTAssertEqual(subject.filename, background.filename)
        XCTAssertTrue(subject.isComplement(of: background))
        XCTAssertTrue(background.isComplement(of: subject))
        XCTAssertFalse(background.inverted == subject.inverted,
                       "a pixel must never be in both or in neither")
    }

    func testBrushHasItsOwnMaskAndIsNotInverted() {
        let brush = MaskRef.forScope(.brush)!
        XCTAssertEqual(brush.source, .brush)
        XCTAssertFalse(brush.inverted)
        XCTAssertFalse(brush.isComplement(of: MaskRef.forScope(.subject)!))
    }

    func testEachScopeHoldsItsOwnStrength() {
        // The handoff's own example: background at 55 while the subject stays at 0.
        var recipe = makeRecipe(edits: [])
        recipe.update(.background) { $0.markRendered(at: .balanced) }
        recipe.update(.subject) { $0.strength = .zero }

        XCTAssertEqual(recipe.edit(for: .background)?.strength, .balanced)
        XCTAssertEqual(recipe.edit(for: .subject)?.strength, .zero)

        let layers = recipe.composite().layers
        XCTAssertEqual(layers.map(\.scope), [.background],
                       "a scope sitting at zero must not appear in the composite at all")
    }

    func testComposedScopesRenderBroadestFirstWhateverOrderTheUserClickedIn() {
        var clickedNarrowFirst = makeRecipe(edits: [])
        for scope in [Scope.brush, .subject, .background, .whole] {
            clickedNarrowFirst.update(scope) { $0.markRendered(at: .subtle) }
        }

        var clickedBroadFirst = makeRecipe(edits: [])
        for scope in [Scope.whole, .background, .subject, .brush] {
            clickedBroadFirst.update(scope) { $0.markRendered(at: .subtle) }
        }

        let expected: [Scope] = [.whole, .background, .subject, .brush]
        XCTAssertEqual(clickedNarrowFirst.composite().layers.map(\.scope), expected)
        XCTAssertEqual(clickedBroadFirst.composite().layers.map(\.scope), expected)
        XCTAssertEqual(clickedNarrowFirst.composite(), clickedBroadFirst.composite(),
                       "two recipes with the same content must render identically")
    }

    func testEveryScopeSinglyProducesExactlyOneLayerCarryingItsOwnMask() {
        for scope in Scope.allCases {
            var recipe = makeRecipe(edits: [])
            recipe.update(scope) { $0.markRendered(at: .balanced) }

            let layers = recipe.composite().layers
            XCTAssertEqual(layers.count, 1, "\(scope)")
            XCTAssertEqual(layers.first?.scope, scope)
            XCTAssertEqual(layers.first?.mask, MaskRef.forScope(scope), "\(scope)")
            XCTAssertEqual(layers.first?.fraction, 1, "\(scope)")
        }
    }

    func testComposedScopesEachKeepTheirOwnBlendFraction() {
        var recipe = makeRecipe(edits: [])
        recipe.update(.whole) { $0.markRendered(at: .balanced); $0.strength = Strength(27.5) }
        recipe.update(.subject) { $0.markRendered(at: .strong) }

        let layers = recipe.composite().layers
        XCTAssertEqual(layers.count, 2)
        XCTAssertEqual(layers[0].fraction, 0.5, accuracy: 1e-12)
        XCTAssertEqual(layers[1].fraction, 1, accuracy: 1e-12)
    }

    func testSettingAScopeTwiceReplacesItRatherThanStackingIt() {
        var recipe = makeRecipe(edits: [])
        recipe.update(.subject) { $0.markRendered(at: .whisper) }
        recipe.update(.subject) { $0.markRendered(at: .strong) }

        XCTAssertEqual(recipe.edits.count, 1)
        XCTAssertEqual(recipe.edit(for: .subject)?.rendered, .strong)
    }

    func testTheCompactLabelsAreShorterOnlyWhereTheDesignShortensThem() {
        XCTAssertEqual(Scope.whole.displayName, "Whole photo")
        XCTAssertEqual(Scope.whole.compactDisplayName, "Whole")
        for scope in [Scope.subject, .background, .brush] {
            XCTAssertEqual(scope.displayName, scope.compactDisplayName, "\(scope)")
        }
    }

    func testARecipeSurvivesARoundTripThroughDisk() throws {
        var recipe = makeRecipe(edits: [])
        recipe.update(.background) { $0.markRendered(at: .balanced); $0.strength = .whisper }
        recipe.update(.brush) { $0.markRendered(at: .strong) }

        let data = try JSONEncoder().encode(recipe)
        let decoded = try JSONDecoder().decode(EditRecipe.self, from: data)

        XCTAssertEqual(decoded, recipe)
        XCTAssertEqual(decoded.composite(), recipe.composite(),
                       "an edit reopened next year must render the same picture")
    }
}

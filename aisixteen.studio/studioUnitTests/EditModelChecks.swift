import XCTest
import CoreGraphics
import RecipeKit
import EnhanceKit
@testable import Studio

/// The job machine: idle → running → complete / failed / cancelled, and what each transition does
/// to the recipe, the capsule and the photo.
@MainActor
final class EditModelChecks: XCTestCase {

    // MARK: The morph

    func testTheCapsuleStartsAsEnhanceAndBecomesSaveOnlyOnceSomethingIsVisible() async {
        let fixture = makeEditFixture()
        XCTAssertEqual(fixture.model.morphStage, .enhance)

        fixture.model.enhance()
        await waitUntil("the pass to land") { fixture.model.phase == .complete }

        XCTAssertEqual(fixture.model.morphStage, .save)
    }

    func testTheCapsuleGoesToProgressWhileRunningAndCarriesTheStepLabel() async {
        let fixture = makeEditFixture(enhancer: HangingEnhancer())
        fixture.model.enhance()

        await waitUntil("a step to be reported") {
            if case .running(let step, _) = fixture.model.phase { return step > 0 }
            return false
        }
        XCTAssertEqual(fixture.model.morphStage, .progress)
        XCTAssertTrue(fixture.model.stepLabel.hasPrefix("Enhancing · step "), fixture.model.stepLabel)
        XCTAssertTrue(fixture.model.stepLabel.hasSuffix(" of 20"), fixture.model.stepLabel)
        XCTAssertFalse(fixture.model.stepLabel.contains("%"))

        fixture.model.cancel()
    }

    func testAFailureShowsTheCardAndACancelNeverDoes() async {
        let failing = makeEditFixture(enhancer: FailingPhotoEnhancer(failAtStep: 2,
                                                                     error: .outOfMemory,
                                                                     speed: .instant))
        failing.model.enhance()
        await waitUntil("the failure") { failing.model.phase.isFailed }
        XCTAssertEqual(failing.model.morphStage, .failure)

        let cancelled = makeEditFixture(enhancer: HangingEnhancer())
        cancelled.model.enhance()
        await waitUntil("the pass to start") { cancelled.model.phase.isRunning }
        cancelled.model.cancel()

        await waitUntil("the pass to unwind") { cancelled.model.phase == .idle }
        XCTAssertFalse(cancelled.model.phase.isFailed,
                       "a user who pressed Stop was not shown an error and must not be")
        XCTAssertEqual(cancelled.model.morphStage, .enhance)
    }

    // MARK: Cancel changes nothing

    func testCancellingLeavesTheRecipeAndThePhotoExactlyAsTheyWere() async {
        let fixture = makeEditFixture(enhancer: HangingEnhancer())
        let before = fixture.model.recipe

        fixture.model.enhance()
        await waitUntil("the pass to start") { fixture.model.phase.isRunning }
        fixture.model.cancel()
        await waitUntil("the pass to unwind") { fixture.model.phase == .idle }

        XCTAssertEqual(fixture.model.recipe, before)
        XCTAssertTrue(fixture.model.isShowingOriginalOnly)
        XCTAssertTrue(fixture.model.displayImage === fixture.model.original)
        XCTAssertTrue(fixture.model.originalIsIntact())
    }

    // MARK: Strength, end to end through the model

    func testAfterAPassTheDialBlendsDownAndZeroReturnsTheOriginalImageItself() async {
        let fixture = makeEditFixture()
        fixture.model.strength = .balanced
        fixture.model.enhance()
        await waitUntil("the pass to land") { fixture.model.phase == .complete }

        XCTAssertFalse(fixture.model.isShowingOriginalOnly)

        fixture.model.strength = Strength(27.5)
        XCTAssertEqual(fixture.model.recipe.edit(for: .whole)?.outcome.fraction ?? 0,
                       0.5, accuracy: 1e-12)

        fixture.model.strength = .zero
        XCTAssertTrue(fixture.model.isShowingOriginalOnly)
        XCTAssertTrue(fixture.model.displayImage === fixture.model.original,
                      "dial at zero must be the original image, not a re-render of it")
    }

    func testPushingAboveTheRenderedStrengthAsksForARerunInsteadOfLying() async {
        let fixture = makeEditFixture()
        fixture.model.strength = .subtle
        fixture.model.enhance()
        await waitUntil("the pass to land") { fixture.model.phase == .complete }

        fixture.model.strength = .strong
        XCTAssertTrue(fixture.model.needsRerun)
        XCTAssertEqual(fixture.model.recipe.edit(for: .whole)?.rendered, .subtle,
                       "the recipe must not silently claim it rendered at 80")
    }

    func testEveryDetentIsReachableAndRunsAPassAtThatExactStrength() async {
        for detent in Detent.allCases {
            let fixture = makeEditFixture()
            fixture.model.strength = detent.strength
            fixture.model.enhance()
            await waitUntil("the pass at \(detent.name)") { fixture.model.phase == .complete }

            XCTAssertEqual(fixture.model.recipe.edit(for: .whole)?.rendered, detent.strength,
                           "at \(detent.name)")
        }
    }

    func testEnhanceIsRefusedAtZeroBecauseThereIsNothingToRun() {
        let fixture = makeEditFixture()
        fixture.model.strength = .zero
        XCTAssertFalse(fixture.model.canEnhance)
    }

    func testEnhanceIsRefusedWhileAPassIsAlreadyRunning() async {
        let fixture = makeEditFixture(enhancer: HangingEnhancer())
        fixture.model.enhance()
        await waitUntil("the pass to start") { fixture.model.phase.isRunning }

        XCTAssertFalse(fixture.model.canEnhance)
        fixture.model.cancel()
    }

    // MARK: Revert

    func testRevertThrowsThePassAwayAndIsAlwaysFree() async {
        let fixture = makeEditFixture()
        fixture.model.enhance()
        await waitUntil("the pass to land") { fixture.model.phase == .complete }

        fixture.model.revert()

        XCTAssertTrue(fixture.model.isShowingOriginalOnly)
        XCTAssertEqual(fixture.model.morphStage, .enhance)
        XCTAssertTrue(fixture.model.displayImage === fixture.model.original)
        XCTAssertTrue(fixture.model.originalIsIntact())
    }

    // MARK: Scopes and masks

    func testSubjectAndBackgroundShareOneComputedMask() async {
        let fixture = makeEditFixture()
        fixture.model.scope = .subject
        await waitUntil("the mask") { fixture.model.maskAvailability == .ready }

        let afterSubject = fixture.model.masks[.segmentation]
        fixture.model.scope = .background
        await waitUntil("background to be ready") { fixture.model.maskAvailability == .ready }

        XCTAssertNotNil(afterSubject)
        XCTAssertTrue(fixture.model.masks[.segmentation] === afterSubject,
                      "computing it twice would be two segmentations of the same photo")
    }

    func testAPhotoWithNoSubjectSaysSoInsteadOfOfferingADeadScope() async {
        let fixture = makeEditFixture(segmenter: EmptySegmenter())
        fixture.model.scope = .subject
        await waitUntil("the answer") { fixture.model.maskAvailability != .working }

        XCTAssertEqual(fixture.model.maskAvailability, .noSubjectFound)
        XCTAssertFalse(fixture.model.canEnhance)
        XCTAssertEqual(fixture.model.maskAvailability.blockingMessage,
                       "No clear subject in this photo. Try Whole photo or Brush.")
    }

    func testBrushRefusesUntilSomethingIsActuallyPainted() async {
        let fixture = makeEditFixture()
        fixture.model.scope = .brush
        await waitUntil("brush to settle") { fixture.model.maskAvailability != .working }

        XCTAssertEqual(fixture.model.maskAvailability, .nothingPainted)
        XCTAssertFalse(fixture.model.canEnhance)

        fixture.model.paintBrush(at: [CGPoint(x: 20, y: 20)], radius: 8, erasing: false)
        XCTAssertEqual(fixture.model.maskAvailability, .ready)
        XCTAssertTrue(fixture.model.canEnhance)
        XCTAssertNotNil(fixture.model.masks[.brush])
    }

    func testWholePhotoNeedsNoMaskAtAll() {
        let fixture = makeEditFixture()
        fixture.model.scope = .whole
        XCTAssertEqual(fixture.model.maskAvailability, .ready)
        XCTAssertTrue(fixture.model.canEnhance)
    }

    func testEachScopeKeepsItsOwnStrength() async {
        let fixture = makeEditFixture()

        fixture.model.strength = .balanced
        fixture.model.enhance()
        await waitUntil("the whole-photo pass") { fixture.model.phase == .complete }

        fixture.model.scope = .subject
        await waitUntil("the mask") { fixture.model.maskAvailability == .ready }
        fixture.model.strength = .whisper
        fixture.model.enhance()
        await waitUntil("the subject pass") { fixture.model.phase == .complete }

        XCTAssertEqual(fixture.model.recipe.edit(for: .whole)?.rendered, .balanced)
        XCTAssertEqual(fixture.model.recipe.edit(for: .subject)?.rendered, .whisper)
        XCTAssertEqual(fixture.model.recipe.composite().layers.count, 2)
    }

    // MARK: The veil

    func testTheVeilOnlyExistsWhileAPassIsRunning() async {
        let fixture = makeEditFixture(enhancer: HangingEnhancer())
        XCTAssertEqual(fixture.model.veilBlur, 0)

        fixture.model.enhance()
        await waitUntil("a step") {
            if case .running(let step, _) = fixture.model.phase { return step >= 1 }
            return false
        }
        XCTAssertGreaterThan(fixture.model.veilBlur, 0)
        XCTAssertEqual(fixture.model.veilOpacity, 0.22, accuracy: 1e-12)

        fixture.model.cancel()
        await waitUntil("idle") { fixture.model.phase == .idle }
        XCTAssertEqual(fixture.model.veilBlur, 0)
    }
}

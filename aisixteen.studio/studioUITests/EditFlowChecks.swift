import XCTest

/// The whole loop, on the real app: import → scope → strength → enhance → compare → export.
///
/// ⚠️ Written, not run (PROMPT §10). See `../uitests.md`.
final class EditFlowChecks: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    // MARK: 1a — import

    func testTheImportScreenStatesThePrivacyPositionOnce() {
        let app = XCUIApplication.launchedEmpty()

        expect(app.buttons["import.library"], "the Choose from Library button")
        let privacy = app.staticTexts["import.privacy"]
        expect(privacy, "the privacy footer")
        XCTAssertTrue(privacy.label.contains("never leaves this device"), privacy.label)
    }

    // MARK: 1b — the editor

    func testTheEditorOffersFourScopesAndDefaultsToWholePhotoAtSubtle() {
        let app = XCUIApplication.launchedWithPhoto()

        expect(app.otherElements["edit.scope"], "the scope segment")
        for scope in ["whole", "subject", "background", "brush"] {
            XCTAssertTrue(app.buttons["edit.scope.\(scope)"].exists, "missing scope: \(scope)")
        }
        XCTAssertTrue(app.buttons["edit.scope.whole"].isSelected)

        let strength = app.otherElements["edit.strength"]
        expect(strength, "the strength dial")
        // ⚠️ The dial announces a detent NAME, never a bare number.
        XCTAssertEqual(strength.value as? String, "Subtle")
    }

    func testThereIsNoPromptFieldAnywhere() {
        // The distinctness test (1m): Studio is an editor, not a generator. A text field on this
        // screen would be the single clearest way to fail Guideline 4.3 against the sibling apps.
        let app = XCUIApplication.launchedWithPhoto()
        expect(app.otherElements["edit.scope"], "the editor")
        XCTAssertEqual(app.textFields.count, 0)
        XCTAssertEqual(app.textViews.count, 0)
    }

    func testOnlyStrongWarnsAboutFineDetail() {
        let app = XCUIApplication.launchedWithPhoto()
        let strength = app.otherElements["edit.strength"]
        expect(strength, "the strength dial")

        XCTAssertFalse(app.staticTexts["edit.strength.warning"].exists)
        for _ in 0..<9 { strength.adjust(toNormalizedSliderPosition: 1) }
        expect(app.staticTexts["edit.strength.warning"], "the Strong warning")
    }

    // MARK: 1c — the pass

    func testThePassReportsStepsNotAPercentageAndCanAlwaysBeCancelled() {
        let app = XCUIApplication.launchedWithPhoto(enhancer: "fast")
        app.buttons["edit.enhance"].tap()

        let progress = app.otherElements["edit.progress"]
        expect(progress, "the progress capsule")
        XCTAssertTrue(progress.label.hasPrefix("Enhancing · step "), progress.label)
        XCTAssertFalse(progress.label.contains("%"), progress.label)
        XCTAssertTrue(app.buttons["edit.cancel"].exists, "Cancel must be present at every moment")
    }

    func testTheComparisonHandleIsPresentDuringThePassNotOnlyAfterIt() {
        // 1j: "the split is there during the wait, not after it."
        let app = XCUIApplication.launchedWithPhoto(enhancer: "fast")
        app.buttons["edit.enhance"].tap()
        expect(app.otherElements["edit.progress"], "the progress capsule")
        XCTAssertTrue(app.images["compare.canvas"].exists || app.otherElements["compare.canvas"].exists)
    }

    func testCancellingReturnsToEnhanceAndNeverShowsTheFailureCard() {
        let app = XCUIApplication.launchedWithPhoto(enhancer: "fast")
        app.buttons["edit.enhance"].tap()
        expect(app.buttons["edit.cancel"], "the Cancel button")
        app.buttons["edit.cancel"].tap()

        expect(app.buttons["edit.enhance"], "the Enhance capsule coming back")
        XCTAssertFalse(app.otherElements["edit.failure"].exists,
                       "a user who pressed Stop was not shown an error and must not be")
    }

    func testAFailedPassShowsTheCardAndKeepsThePhoto() {
        let app = XCUIApplication.launchedWithPhoto(enhancer: "failing")
        app.buttons["edit.enhance"].tap()

        expect(app.otherElements["edit.failure"], "the failure card")
        XCTAssertTrue(app.staticTexts["That one didn't come together"].exists)
        XCTAssertTrue(app.buttons["Try again"].exists)
    }

    func testTheEarlyFailureIsReachableToo() {
        // Fails before the first preview, so the other half of the transition — capsule straight to
        // card, without ever becoming a picture — is exercised.
        let app = XCUIApplication.launchedWithPhoto(enhancer: "failing-early")
        app.buttons["edit.enhance"].tap()
        expect(app.otherElements["edit.failure"], "the failure card")
    }

    // MARK: 1d — comparison and the live dial

    func testAfterThePassTheCapsuleBecomesSaveAndRevertAppearsBesideIt() {
        let app = XCUIApplication.launchedWithPhoto(enhancer: "fast")
        app.buttons["edit.enhance"].tap()

        expect(app.buttons["edit.save"], "the Save capsule", timeout: 20)
        XCTAssertTrue(app.buttons["edit.revert"].exists, "Revert is always present and always free")
        expectGone(app.otherElements["edit.progress"], "the progress capsule")
    }

    func testTheComparisonIsOneAdjustableElementThatAnnouncesItsPosition() {
        let app = XCUIApplication.launchedWithPhoto(enhancer: "fast")
        app.buttons["edit.enhance"].tap()
        expect(app.buttons["edit.save"], "the pass to land", timeout: 20)

        let canvas = app.descendants(matching: .any)["compare.canvas"]
        expect(canvas, "the comparison canvas")
        XCTAssertEqual(canvas.value as? String, "Showing enhanced")

        canvas.adjust(toNormalizedSliderPosition: 0.7)
        XCTAssertNotEqual(canvas.value as? String, "Showing enhanced",
                          "adjusting must move the split and say so")
    }

    func testDroppingTheDialToZeroSaysItIsShowingTheOriginal() {
        let app = XCUIApplication.launchedWithPhoto(enhancer: "fast")
        app.buttons["edit.enhance"].tap()
        expect(app.buttons["edit.save"], "the pass to land", timeout: 20)

        let strength = app.otherElements["edit.strength"]
        strength.adjust(toNormalizedSliderPosition: 0)
        XCTAssertEqual(strength.value as? String, "Off. Showing the original.")
    }

    func testRaisingAboveTheRenderedStrengthAsksForARerun() {
        let app = XCUIApplication.launchedWithPhoto(enhancer: "fast")
        app.buttons["edit.enhance"].tap()
        expect(app.buttons["edit.save"], "the pass to land", timeout: 20)

        app.otherElements["edit.strength"].adjust(toNormalizedSliderPosition: 1)
        expect(app.staticTexts["edit.strength.rerun"], "the re-run notice")
        XCTAssertTrue(app.buttons["edit.enhance"].exists, "the capsule offers the pass again")
    }

    func testRevertReturnsToTheEnhanceCapsule() {
        let app = XCUIApplication.launchedWithPhoto(enhancer: "fast")
        app.buttons["edit.enhance"].tap()
        expect(app.buttons["edit.revert"], "Revert", timeout: 20)
        app.buttons["edit.revert"].tap()

        expect(app.buttons["edit.enhance"], "the Enhance capsule")
    }

    // MARK: Scopes

    func testBrushRefusesUntilSomethingIsPainted() {
        let app = XCUIApplication.launchedWithPhoto()
        app.buttons["edit.scope.brush"].tap()

        expect(app.staticTexts["edit.scope.blocked"], "the nothing-painted message")
        XCTAssertFalse(app.buttons["edit.enhance"].isEnabled)

        let canvas = app.otherElements["brush.canvas"]
        expect(canvas, "the brush canvas")
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.4))
            .press(forDuration: 0.1,
                   thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.6)))

        XCTAssertTrue(app.buttons["edit.enhance"].isEnabled)
    }

    func testSelectingSubjectEitherBecomesReadyOrSaysThereIsNoSubject() {
        // Both outcomes are correct — the fixture photo is a landscape, so "no clear subject" is the
        // honest answer, and the test asserts the app says one of them rather than going silent.
        let app = XCUIApplication.launchedWithPhoto()
        app.buttons["edit.scope.subject"].tap()

        let blocked = app.staticTexts["edit.scope.blocked"]
        let enhance = app.buttons["edit.enhance"]
        let settled = NSPredicate(format: "exists == true")
        let expectation = XCTNSPredicateExpectation(predicate: settled, object: blocked)
        _ = XCTWaiter().wait(for: [expectation], timeout: 8)

        XCTAssertTrue(blocked.exists || enhance.isEnabled,
                      "a scope must never sit silently unavailable")
    }

    // MARK: 1e — export

    func testTheExportSheetSaysWhatHappensToTheOriginalOnEveryRow() {
        let app = XCUIApplication.launchedWithPhoto(enhancer: "fast")
        app.buttons["edit.enhance"].tap()
        expect(app.buttons["edit.save"], "the Save capsule", timeout: 20)
        app.buttons["edit.save"].tap()

        expect(app.otherElements["export.sheet"], "the export sheet")

        let saveAsNew = app.buttons["export.saveAsNew"]
        expect(saveAsNew, "the Save as new row")
        XCTAssertTrue((saveAsNew.value as? String ?? "").contains("Nothing is overwritten"),
                      saveAsNew.value as? String ?? "nil")

        XCTAssertTrue(app.buttons["export.share"].exists)
        XCTAssertFalse(app.buttons["export.replaceInPhotos"].exists,
                       "this build is add-only by design")

        let footer = app.staticTexts["export.privacy"]
        expect(footer, "the export footer")
        XCTAssertTrue(footer.label.contains("Never uploaded"), footer.label)
    }

    func testTheExportSheetCarriesNoUpsell() {
        let app = XCUIApplication.launchedWithPhoto(enhancer: "fast")
        app.buttons["edit.enhance"].tap()
        expect(app.buttons["edit.save"], "the Save capsule", timeout: 20)
        app.buttons["edit.save"].tap()
        expect(app.otherElements["export.sheet"], "the export sheet")

        for banned in ["Pro", "Upgrade", "Unlock", "Premium", "Watermark"] {
            XCTAssertFalse(app.staticTexts[banned].exists, "found an upsell: \(banned)")
        }
    }

    // MARK: 1f — library

    func testTheLibraryDescribesTheFolderAndNotAnAccount() {
        let app = XCUIApplication.launchedWithPhoto()
        app.buttons["edit.back"].tap()

        let promise = app.staticTexts["library.promise"]
        expect(promise, "the library promise")
        for banned in ["account", "server", "sign in", "uploaded"] {
            XCTAssertFalse(promise.label.localizedCaseInsensitiveContains(banned),
                           "\(promise.label) mentions \(banned)")
        }
    }

    func testAnEnhancedPhotoAppearsInTheLibrary() {
        let app = XCUIApplication.launchedWithPhoto(enhancer: "fast")
        app.buttons["edit.enhance"].tap()
        expect(app.buttons["edit.save"], "the pass to land", timeout: 20)
        app.buttons["edit.back"].tap()

        expect(app.buttons["library.tile"].firstMatch, "a library tile")
    }
}

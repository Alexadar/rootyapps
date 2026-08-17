import XCTest
@testable import RecipeKit

/// The handle: its 10 % steps, its announcements, and the transient hold that must never persist.
final class ComparisonTests: XCTestCase {

    func testItStartsFullyEnhancedBecauseThatIsWhatTheUserJustAskedFor() {
        let comparison = Comparison()
        XCTAssertEqual(comparison.revealed, 1)
        XCTAssertTrue(comparison.isShowingEnhancedFully)
        XCTAssertEqual(comparison.accessibilityValue, "Showing enhanced")
    }

    func testItIsOneAdjustableElement() {
        // 1j: "Comparison. Showing enhanced. Adjustable." — not a slider plus a button.
        let comparison = Comparison()
        XCTAssertEqual(comparison.accessibilityLabel, "Comparison")
        XCTAssertEqual(comparison.accessibilityValue, "Showing enhanced")
    }

    func testSwipingMovesInTenPercentStepsAndAnnouncesThePosition() {
        var comparison = Comparison()
        comparison.decrement()
        comparison.decrement()
        comparison.decrement()

        XCTAssertEqual(comparison.revealed, 0.7, accuracy: 1e-12)
        XCTAssertEqual(comparison.accessibilityValue, "70 percent enhanced")
    }

    func testRepeatedSteppingDoesNotAccumulateFloatingPointDrift() {
        var comparison = Comparison()
        for _ in 0..<10 { comparison.decrement() }
        XCTAssertEqual(comparison.revealed, 0)
        XCTAssertEqual(comparison.accessibilityValue, "Showing original")

        for _ in 0..<10 { comparison.increment() }
        XCTAssertEqual(comparison.revealed, 1)
        XCTAssertEqual(comparison.accessibilityValue, "Showing enhanced")
    }

    func testTheHandleStopsAtBothEnds() {
        var comparison = Comparison()
        for _ in 0..<40 { comparison.increment() }
        XCTAssertEqual(comparison.revealed, 1)

        for _ in 0..<40 { comparison.decrement() }
        XCTAssertEqual(comparison.revealed, 0)
    }

    func testDraggingClampsAndSurvivesNonsense() {
        var comparison = Comparison()
        comparison.setRevealed(1.8)
        XCTAssertEqual(comparison.revealed, 1)
        comparison.setRevealed(-0.4)
        XCTAssertEqual(comparison.revealed, 0)
        comparison.setRevealed(.nan)
        XCTAssertEqual(comparison.revealed, 1)
    }

    func testHoldingShowsTheOriginalAndReleasingRestoresThePositionExactly() {
        var comparison = Comparison()
        comparison.setRevealed(0.42)

        comparison.isHoldingOriginal = true
        XCTAssertEqual(comparison.effectiveRevealed, 0)
        XCTAssertTrue(comparison.isShowingOriginalFully)
        XCTAssertEqual(comparison.accessibilityValue, Comparison.holdAnnouncement)

        comparison.isHoldingOriginal = false
        XCTAssertEqual(comparison.revealed, 0.42, "the hold must not move the handle")
        XCTAssertEqual(comparison.effectiveRevealed, 0.42)
        XCTAssertEqual(comparison.releaseAnnouncement, "42 percent enhanced")
    }

    func testTheGripIsSmallerThanItsTargetAndTheTargetClearsTheFloor() {
        XCTAssertEqual(ComparisonHandleMetrics.gripDiameter, 38)
        XCTAssertEqual(ComparisonHandleMetrics.targetDiameter, 56)
        XCTAssertTrue(ComparisonHandleMetrics.satisfiesMinimumTarget)
        XCTAssertGreaterThan(ComparisonHandleMetrics.targetDiameter,
                             ComparisonHandleMetrics.gripDiameter,
                             "a 38 pt visual grip on a 38 pt target is the failure this guards")
    }

    func testTheMacNamesTheKeyBecauseThereIsNothingToPressAndHold() {
        XCTAssertTrue(Comparison.macHoldAffordance.contains("Space"))
        XCTAssertFalse(Comparison.holdAffordance.contains("Space"))
    }
}

/// The export sheet's copy, which is where the app's one promise is actually made.
final class ExportCopyTests: XCTestCase {

    func testKeepBothIsTheDefault() {
        XCTAssertEqual(ExportOption.default, .saveAsNew)
    }

    func testEveryRowSaysWhatHappensToTheOriginal() {
        for option in ExportOption.allCases {
            XCTAssertTrue(option.namesTheOriginal,
                          "\(option) does not name the original: \(option.fateOfTheOriginal)")
        }
    }

    func testSaveAsNewPromisesNothingIsOverwritten() {
        XCTAssertTrue(ExportOption.saveAsNew.fateOfTheOriginal.contains("Nothing is overwritten"))
    }

    func testOnlySavingNeedsPhotoLibraryAccess() {
        XCTAssertTrue(ExportOption.saveAsNew.needsPhotoLibraryAddAccess)
        XCTAssertFalse(ExportOption.share.needsPhotoLibraryAddAccess,
                       "the share sheet asks for nothing, and neither should we")
    }

    func testTheSheetHasNoUpsellRow() {
        let copy = ExportOption.allCases.map { $0.title + $0.fateOfTheOriginal }.joined()
        for banned in ["Pro", "Upgrade", "Unlock", "watermark", "Premium"] {
            XCTAssertFalse(copy.localizedCaseInsensitiveContains(banned), "found \(banned)")
        }
    }

    func testThePrivacyPromiseIsMadeWhereTheHandoffSaysAndSaysNothingAboutAServer() {
        XCTAssertTrue(PrivacyCopy.importFooter.contains("never leaves this device"))
        XCTAssertTrue(PrivacyCopy.exportFooter(deviceName: "iPhone").contains("Never uploaded"))
        XCTAssertEqual(PrivacyCopy.exportFooter(deviceName: "Mac"),
                       "Enhanced on this Mac. Never uploaded.")
    }
}

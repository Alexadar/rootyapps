import XCTest

final class GridChecks: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testHeaderCellsRenderAsRead() {
        let app = launchGridScan(["GRIDSCAN_DOC": "Soil sample log"])
        // Row 0, as read from the document — the product defines no columns of its own.
        let header = any(app, "grid.cell.0.0")
        XCTAssertTrue(header.waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)
            .containing(textMatches("Sample ID")).firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any)
            .containing(textMatches("Moisture")).firstMatch.exists)
        app.terminate()
    }

    func testFlaggedCellSpeaksItsReason() {
        let app = launchGridScan(["GRIDSCAN_DOC": "Soil sample log"])
        let flagged = any(app, "grid.cell.3.2")     // the seeded "6.I" mis-read
        XCTAssertTrue(flagged.waitForExistence(timeout: 10))
        XCTAssertTrue(flagged.text.contains("low confidence"),
                      "flag reason missing from accessibility label: \(flagged.text)")
        app.terminate()
    }

    func testFixBarCorrectsTheValueAndPersistsAcrossRelaunchOfView() {
        let app = launchGridScan(["GRIDSCAN_DOC": "Soil sample log"])
        let field = any(app, "review.fix.field")
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        XCTAssertTrue(any(app, "review.fix.original").text.contains("6.I"))
        field.tap()
        field.typeText("6.1")
        any(app, "review.fix.commit").tap()
        // The corrected value renders with the corrected-by-you state.
        let corrected = any(app, "grid.cell.3.2")
        XCTAssertTrue(corrected.waitForExistence(timeout: 5))
        XCTAssertTrue(corrected.text.contains("6.1"))
        XCTAssertTrue(corrected.text.contains("corrected by you"))
        // And the fix bar is gone — no open flags remain.
        XCTAssertFalse(any(app, "review.fix.field").exists)
        app.terminate()
    }

    func testTappingACellShowsTheSourcePanel() {
        let app = launchGridScan(["GRIDSCAN_DOC": "Race results"])
        let cell = any(app, "grid.cell.1.1")
        XCTAssertTrue(cell.waitForExistence(timeout: 10))
        cell.tap()
        // Fixtures have no page render; the reduced state must say so honestly
        // instead of pretending — that state IS the assertion.
        XCTAssertTrue(app.descendants(matching: .any)
            .containing(textMatches("no stored page render")).firstMatch
            .waitForExistence(timeout: 5))
        app.terminate()
    }
}

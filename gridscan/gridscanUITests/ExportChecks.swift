import XCTest

final class ExportChecks: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testDestinationsListShowsOnlyFileKinds() {
        let app = launchGridScan(["GRIDSCAN_TAB": "destinations"])
        XCTAssertTrue(any(app, "dest.kind.csvFile").waitForExistence(timeout: 10))
        XCTAssertTrue(any(app, "dest.kind.xlsxFile").exists)
        // Tier one ships file destinations ONLY: webhook must be absent, not disabled.
        XCTAssertFalse(app.descendants(matching: .any)
            .containing(textMatches("webhook")).firstMatch.exists)
        app.terminate()
    }

    func testDestinationDetailStatesCustodyPlainly() {
        let app = launchGridScan(["GRIDSCAN_TAB": "destinations"])
        let csv = any(app, "dest.kind.csvFile")
        XCTAssertTrue(csv.waitForExistence(timeout: 10))
        csv.tap()
        XCTAssertTrue(app.descendants(matching: .any)
            .containing(textMatches("Nothing leaves this device")).firstMatch
            .waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)
            .containing(textMatches("recorded in Activity")).firstMatch.exists)
        app.terminate()
    }

    func testExportMenuOffersBothFormatsOnATableDocument() {
        let app = launchGridScan(["GRIDSCAN_DOC": "Race results"])
        let export = any(app, "doc.export")
        XCTAssertTrue(export.waitForExistence(timeout: 10))
        export.tap()
        XCTAssertTrue(app.descendants(matching: .any)
            .containing(textMatches("CSV file")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)
            .containing(textMatches("Excel workbook")).firstMatch.exists)
        app.terminate()
    }
}

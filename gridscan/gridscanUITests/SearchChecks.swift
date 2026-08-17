import XCTest

final class SearchChecks: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func openSearch(_ app: XCUIApplication) {
        app.descendants(matching: .any).containing(textMatches("Search"))
            .firstMatch.tap()
    }

    func testQueryHitsASeededCellValue() {
        let app = launchGridScan(["GRIDSCAN_TAB": "search"])
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("Lind")
        // The result shows WHAT matched — the value, not a filename.
        XCTAssertTrue(app.descendants(matching: .any)
            .containing(textMatches("T. Lind")).firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)
            .containing(textMatches(Fixture.race)).firstMatch.exists)
        app.terminate()
    }

    func testNothingFoundStateIsHonestAndOffline() {
        let app = launchGridScan(["GRIDSCAN_TAB": "search"])
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("zebra unicorn nothing")
        XCTAssertTrue(any(app, "search.nothingFound").waitForExistence(timeout: 10))
        // Never suggests the web.
        XCTAssertFalse(app.descendants(matching: .any)
            .containing(textMatches("web")).firstMatch.exists)
        app.terminate()
    }

    func testNoAnswerCardExistsInTierOne() {
        // The v2 generated-answer layer must be ABSENT from this target, not hidden.
        let app = launchGridScan(["GRIDSCAN_TAB": "search"])
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("what is the pH of plot seven")
        XCTAssertFalse(any(app, "answer.card").exists)
        XCTAssertFalse(app.descendants(matching: .any)
            .containing(textMatches("ANSWER")).firstMatch.exists)
        app.terminate()
    }
}

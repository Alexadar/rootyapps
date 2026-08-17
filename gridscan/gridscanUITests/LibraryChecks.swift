import XCTest

final class LibraryChecks: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testSeededTilesAllPresent() {
        let app = launchGridScan()
        for title in Fixture.all {
            XCTAssertTrue(app.descendants(matching: .any)
                .containing(textMatches(title)).firstMatch
                .waitForExistence(timeout: 10), "missing tile: \(title)")
        }
        app.terminate()
    }

    func testReviewBadgeOnFlaggedFixtureOnly() {
        let app = launchGridScan()
        _ = app.descendants(matching: .any).containing(textMatches(Fixture.soil))
            .firstMatch.waitForExistence(timeout: 10)
        // Exactly one fixture (soil log) carries an open review flag.
        let badges = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'library.tile.review.'"))
        XCTAssertEqual(badges.count, 1)
        app.terminate()
    }

    func testKindFilterNarrowsToForms() {
        let app = launchGridScan()
        let filter = any(app, "library.kindFilter")
        XCTAssertTrue(filter.waitForExistence(timeout: 10))
        filter.tap()
        app.descendants(matching: .any).containing(textMatches("Form")).firstMatch.tap()
        // The one form fixture stays; a table fixture disappears.
        XCTAssertTrue(app.descendants(matching: .any)
            .containing(textMatches(Fixture.checklist)).firstMatch
            .waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)
            .containing(textMatches(Fixture.race)).firstMatch.exists)
        app.terminate()
    }

    func testSelectShowsBulkBar() {
        let app = launchGridScan()
        let select = any(app, "library.select")
        XCTAssertTrue(select.waitForExistence(timeout: 10))
        select.tap()
        app.descendants(matching: .any).containing(textMatches(Fixture.race))
            .firstMatch.tap()
        XCTAssertTrue(any(app, "library.bulk.count").waitForExistence(timeout: 5))
        XCTAssertTrue(any(app, "library.bulk.delete").exists)
        app.terminate()
    }
}

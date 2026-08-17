import XCTest

/// Deep links must work in BOTH layouts (compact tab bar AND regular/Mac sidebar) —
/// the Storypole bug was `_TAB` silently ignored at regular width. These run on
/// whatever destination executes the suite; the section-state seam is shared by both
/// containers, so a pass here covers the wiring for each.
final class DeepLinkChecks: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testTabDeepLinksLand() {
        let expectations: [(env: String, marker: String)] = [
            ("library", "Library"),
            ("search", "Search your documents"),
            ("destinations", "CSV file"),
            ("activity", "Activity"),
        ]
        for (env, marker) in expectations {
            let app = launchGridScan(["GRIDSCAN_TAB": env])
            XCTAssertTrue(app.descendants(matching: .any)
                .containing(textMatches(marker)).firstMatch.waitForExistence(timeout: 10),
                          "GRIDSCAN_TAB=\(env) did not land on \(marker)")
            app.terminate()
        }
    }

    func testDocDeepLinkLandsOnDocumentNotLibrary() {
        let app = launchGridScan(["GRIDSCAN_DOC": "Vaccination roster"])
        // Positive: the document's grid is up.
        XCTAssertTrue(any(app, "grid.cell.0.0").waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)
            .containing(textMatches("Patient code")).firstMatch.exists)
        // Negative: not just sitting on the Library grid (bring-in affordance hidden
        // behind the pushed document view on compact; on regular the doc detail shows).
        XCTAssertFalse(any(app, "library.bulk.count").exists)
        app.terminate()
    }

    func testUnknownTabValueFallsBackToLibrary() {
        let app = launchGridScan(["GRIDSCAN_TAB": "nonsense"])
        XCTAssertTrue(app.descendants(matching: .any)
            .containing(textMatches(Fixture.race)).firstMatch.waitForExistence(timeout: 10))
        app.terminate()
    }
}

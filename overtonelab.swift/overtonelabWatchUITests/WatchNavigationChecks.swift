import XCTest

/// Getting to the catalog and back, both ways.
///
/// The wrist app is two states — the catalog or one tool — after vertical paging was removed for
/// fighting the crown. That leaves exactly two routes back to the list, and both are easy to break
/// silently: the header button is a plain `Button` inside a `ScrollView`, and the swipe is a
/// `simultaneousGesture` with a 2:1 horizontal-to-vertical test that a later layout change could
/// starve. Neither shows up in a screenshot.
final class WatchNavigationChecks: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    private func open(_ tool: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-otl.watch.lastTool", tool]
        app.launch()
        XCTAssertTrue(any(app, "result.\(tool)").waitForExistence(timeout: 30),
                      "\(tool) must open straight onto its number")
        return app
    }

    func testHeaderButtonReachesTheCatalog() {
        let app = open("sabine")
        any(app, "nav.toolList").tap()
        XCTAssertTrue(any(app, "tool.tempo").waitForExistence(timeout: 10),
                      "the header button must reach the catalog")
    }

    func testSwipeLeftToRightReachesTheCatalog() {
        let app = open("sabine")
        app.swipeRight()
        XCTAssertTrue(any(app, "tool.tempo").waitForExistence(timeout: 10),
                      "a left-to-right swipe must reach the catalog")
    }

    /// The catalog's job: reach a tool that is nowhere near the one you started on.
    func testCatalogOpensADistantTool() {
        let app = open("tempo")
        any(app, "nav.toolList").tap()

        // Thiele is the last row of 26. Neither platform publishes content that has never been on
        // screen, so it has to be scrolled into the tree before it can be found at all — querying
        // first would fail looking exactly like a catalog missing an entry.
        let row = any(app, "tool.thiele")
        var swipes = 0
        while !row.exists && swipes < 20 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(row.waitForExistence(timeout: 10),
                      "the catalog must list Thiele (scrolled \(swipes) times)")
        row.tap()

        XCTAssertTrue(any(app, "result.thiele").waitForExistence(timeout: 15),
                      "tapping a catalog row must open that tool")
    }
}

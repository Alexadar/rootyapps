import XCTest

/// The trade-grouped catalog, and getting from it to any of the 20 tools.
///
/// Mirrors `overtonelab.swift/overtonelabWatchUITests/WatchNavigationChecks.swift`. A 20-row list that
/// only ever gets tapped near the top is untested navigation: the rows furthest down are exactly the
/// ones a `Section` layout change, a `.listStyle` change or a scroll-offset bug would strand, and none
/// of that shows up in a screenshot.
final class WatchNavigationChecks: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    /// Launch on the catalog (no deep link) and wait for it.
    private func catalog() -> XCUIApplication {
        let app = launchWatch()
        XCTAssertTrue(any(app, "tool.rafter").waitForExistence(timeout: 15),
                      "the catalog did not appear — no tool rows on screen")
        return app
    }

    /// The catalog lists every one of the 20 calculators.
    ///
    /// This is the test that would have caught the watch shipping 6 of the phone's 20 tools: the app
    /// built, ran and passed its own suite while missing 14 calculators, because nothing asserted the
    /// list was complete.
    func testTheCatalogListsAllTwentyTools() {
        let app = catalog()
        let tools = ["rafter", "stairs", "pitch",
                     "concrete", "footing", "rebar", "aggregate", "pavers",
                     "area", "volume",
                     "roofing", "estimate", "miter", "lumber", "mortar",
                     "offset", "rollingOffset", "cutLength", "grade",
                     "units"]
        for tool in tools {
            // `.exists` rather than `.isHittable`: a row far down the list is in the accessibility tree
            // but below the fold, and this asserts the CATALOG is complete, not that it is scrolled.
            XCTAssertTrue(any(app, "tool.\(tool)").waitForExistence(timeout: 10),
                          "the catalog is missing '\(tool)'")
        }
    }

    /// A row in the LAST section must open its tool. Convert is the final section and `units` its only
    /// row, so this is the furthest reach in the list.
    func testTheCatalogOpensAToolInTheLastSection() {
        let app = catalog()
        let row = any(app, "tool.units")
        XCTAssertTrue(row.waitForExistence(timeout: 10), "the catalog must list Convert")
        row.tap()
        XCTAssertTrue(any(app, "result.units.hero").waitForExistence(timeout: 15),
                      "tapping the last section's row did not open that tool")
    }

    /// …and one in the middle, from a different trade, so a single working row does not stand in for
    /// the whole list.
    func testTheCatalogOpensAToolInTheMiddle() {
        let app = catalog()
        let row = any(app, "tool.miter")
        XCTAssertTrue(row.waitForExistence(timeout: 10), "the catalog must list Miter")
        row.tap()
        assertShows(app, "result.miter.hero", "31.62")
    }

    /// Back from a tool returns to the catalog, and a second, distant tool is reachable without a
    /// relaunch. A `NavigationStack` that fails to pop leaves the wrist app on one tool forever.
    func testBackFromAToolReachesTheCatalogAndAnotherTool() {
        let app = catalog()
        any(app, "tool.rafter").tap()
        XCTAssertTrue(any(app, "result.rafter.hero").waitForExistence(timeout: 15), "Rafter did not open")

        // watchOS pops with a left-to-right swipe as well as the system chevron.
        app.swipeRight()
        XCTAssertTrue(any(app, "tool.grade").waitForExistence(timeout: 10),
                      "swiping back did not reach the catalog")

        any(app, "tool.grade").tap()
        assertShows(app, "result.grade.hero", "2.08")
    }

    /// The deep link opens a tool DIRECTLY, skipping the catalog — the screenshot and UI-test path.
    func testTheDeepLinkOpensAToolWithoutTheCatalog() {
        let app = launchWatch(tool: "roofing")
        assertShows(app, "result.roofing.hero", "22.36")
        // If the deep link merely selected a row we would still be looking at the list.
        XCTAssertFalse(any(app, "tool.rafter").exists,
                       "KERFCALC_TOOL landed on the catalog instead of the tool")
    }

    /// An unknown deep-link value must fall back to the catalog rather than a blank screen.
    func testAnUnknownDeepLinkFallsBackToTheCatalog() {
        let app = launchWatch(tool: "notatool")
        XCTAssertTrue(any(app, "tool.rafter").waitForExistence(timeout: 15),
                      "an unrecognised KERFCALC_TOOL left the app on nothing")
    }
}

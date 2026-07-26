import XCTest

/// Screen-level smoke tour: open every one of the 16 tools from the Formulas grid and assert each
/// (a) loads its detail nav bar, (b) renders its cited FormulaCard, and — for the marquee tools —
/// (c) shows its known default hero value. This is the per-screen coverage the unit tests can't give:
/// it catches a view-wiring or crash regression on any tool, across the whole app.
final class ToolTourTests: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    /// (tile title == nav-bar title, optional known default hero value rendered on the screen).
    private let tools: [(title: String, hero: String?)] = [
        ("Rafter", "173.57"), ("Stairs", "14"), ("Right Angle", nil),
        ("Concrete", "1.235"), ("Footing", nil), ("Rebar", nil), ("Aggregate", nil), ("Pavers", nil),
        ("Area", nil), ("Volume", nil),
        ("Roofing", "22.36"), ("Estimate", nil), ("Miter", nil), ("Lumber", nil), ("Mortar", nil),
        ("Convert", "0.3048"),
    ]

    func testEveryToolLoadsAndShowsFormulaCard() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["Formulas"].waitForExistence(timeout: 8), "no tab bar")
        app.tabBars.buttons["Formulas"].tap()
        XCTAssertTrue(app.staticTexts["Formulas"].waitForExistence(timeout: 5), "Formulas title missing")

        for tool in tools {
            resetToTop(app)
            openTile(app, tool.title)

            XCTAssertTrue(app.navigationBars[tool.title].waitForExistence(timeout: 6),
                          "\(tool.title) detail did not load")
            XCTAssertTrue(app.staticTexts["FORMULA"].waitForExistence(timeout: 6),
                          "FormulaCard missing on \(tool.title)")
            if let hero = tool.hero {
                XCTAssertTrue(app.staticTexts[hero].waitForExistence(timeout: 5),
                              "\(tool.title) hero \(hero) not rendered")
            }

            // Back to the grid.
            app.navigationBars[tool.title].buttons.element(boundBy: 0).tap()
            XCTAssertTrue(app.staticTexts["Formulas"].waitForExistence(timeout: 5),
                          "did not return to Formulas from \(tool.title)")
        }
    }

    // MARK: helpers
    private func resetToTop(_ app: XCUIApplication) {
        let header = app.staticTexts["Formulas"]
        var tries = 0
        while !header.isHittable && tries < 10 { app.swipeDown(velocity: 1500); tries += 1 }
    }

    private func openTile(_ app: XCUIApplication, _ title: String) {
        let tile = app.staticTexts[title].firstMatch
        var tries = 0
        while !tile.isHittable && tries < 14 { app.swipeUp(velocity: 700); tries += 1 }
        XCTAssertTrue(tile.isHittable, "tile \(title) not reachable by scrolling")
        tile.tap()
    }
}

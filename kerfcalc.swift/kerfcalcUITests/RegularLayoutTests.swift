import XCTest

/// Regular-size (iPad / Mac) layout smoke — covers the new rail + category sidebar + side-by-side
/// content shell. Run on an iPad destination for a true regular horizontal size class; the tab-or-rail
/// and deep-link approach keeps every assertion valid on compact too, so it's safe in the shared suite.
final class RegularLayoutTests: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    /// Deep-link straight to Rafter, assert the side-by-side detail (hero + cited FormulaCard), then
    /// switch surfaces via the rail/tab to Reference and back to Spec.
    func testRailSidebarAndSideBySideDetail() {
        let app = XCUIApplication()
        app.launchEnvironment["KERFCALC_TOOL"] = "rafter"   // Formulas surface → Rafter detail
        app.launch()

        // Side-by-side detail: the hero readout and the cited formula card both render.
        XCTAssertTrue(app.staticTexts["Rafter"].firstMatch.waitForExistence(timeout: 8), "Rafter detail did not load")
        XCTAssertTrue(app.staticTexts["173.57"].waitForExistence(timeout: 6), "rafter hero (173.57) missing")
        XCTAssertTrue(app.staticTexts["FORMULA"].waitForExistence(timeout: 4), "FormulaCard missing on Rafter")

        // Rail (regular) / tab (compact) switches to Reference.
        surface(app, "Reference")
        XCTAssertTrue(app.staticTexts["Stair code limits"].waitForExistence(timeout: 5)
                      || app.navigationBars["Reference"].waitForExistence(timeout: 5),
                      "Reference surface did not show")

        // Back to Spec — the keypad's signature "=" key proves the Spec surface mounted.
        surface(app, "Spec")
        XCTAssertTrue(app.buttons["="].firstMatch.waitForExistence(timeout: 5), "Spec keypad did not show")
    }

    /// Opening a tool from the Formulas grid lands on its detail with the FormulaCard. Uses "Footing"
    /// — unambiguous (not a favorite, not a trade name), so it can only be the grid tile.
    func testGridTileOpensDetail() {
        let app = XCUIApplication()
        app.launchEnvironment["KERFCALC_TAB"] = "1"         // Formulas surface
        app.launch()

        let footing = app.staticTexts["Footing"].firstMatch
        var tries = 0
        while !footing.isHittable && tries < 12 { app.swipeUp(velocity: 500); tries += 1 }
        XCTAssertTrue(footing.exists, "Footing tile not found on Formulas")
        footing.tap()
        XCTAssertTrue(app.navigationBars["Footing"].waitForExistence(timeout: 6)
                      || app.staticTexts["FORMULA"].waitForExistence(timeout: 6),
                      "Footing detail did not open")
    }

    // MARK: helper — surface switch works on both size classes
    private func surface(_ app: XCUIApplication, _ label: String) {
        let tab = app.tabBars.buttons[label].firstMatch
        if tab.waitForExistence(timeout: 2) { tab.tap(); return }
        let rail = app.buttons[label].firstMatch
        if rail.waitForExistence(timeout: 2) { rail.tap() }
    }
}

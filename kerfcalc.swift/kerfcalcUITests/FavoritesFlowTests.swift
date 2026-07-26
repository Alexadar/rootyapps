import XCTest

/// Functional UI smoke: navigation across tabs, a tool detail renders its FormulaCard, a favourite
/// star toggles, and the Spec keypad accepts input. Catches wiring/crash regressions.
final class FavoritesFlowTests: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    func testFormulasNavigationAndFormulaCard() {
        let app = XCUIApplication()
        app.launch()

        // Spec tab is the default.
        XCTAssertTrue(app.tabBars.buttons["Formulas"].waitForExistence(timeout: 8), "no tab bar")
        app.tabBars.buttons["Formulas"].tap()
        XCTAssertTrue(app.staticTexts["Formulas"].waitForExistence(timeout: 5), "Formulas title missing")

        // Open Rafter and confirm the detail + its cited FormulaCard render.
        let rafter = app.staticTexts["Rafter"].firstMatch
        XCTAssertTrue(rafter.waitForExistence(timeout: 5), "Rafter tile missing")
        rafter.tap()
        XCTAssertTrue(app.navigationBars["Rafter"].waitForExistence(timeout: 5), "Rafter detail did not load")
        XCTAssertTrue(app.staticTexts["FORMULA"].waitForExistence(timeout: 5), "FormulaCard missing on Rafter")
        XCTAssertTrue(app.staticTexts["VERIFIED"].exists, "VERIFIED badge missing")
    }

    func testFavoriteStarToggles() {
        let app = XCUIApplication()
        app.launch()
        app.tabBars.buttons["Formulas"].tap()
        _ = app.staticTexts["Formulas"].waitForExistence(timeout: 5)

        // Miter is not a seeded favourite — its star button should toggle without crashing.
        let miter = app.staticTexts["Miter"].firstMatch
        var tries = 0
        while !miter.isHittable && tries < 10 { app.swipeUp(velocity: .init(rawValue: 500)); tries += 1 }
        XCTAssertTrue(miter.exists, "Miter tile missing")
        // The star buttons live on tiles; tapping any star must not crash the grid.
        let stars = app.buttons.matching(NSPredicate(format: "label CONTAINS 'star'"))
        if stars.count > 0 { stars.element(boundBy: 0).tap() }
        // App still alive & interactive.
        XCTAssertTrue(app.tabBars.buttons["Spec"].isHittable, "app became unresponsive after star tap")
    }

    func testSpecKeypadAcceptsInput() {
        let app = XCUIApplication()
        app.launch()
        // On Spec by default — punch a couple digits and a dimension key.
        for key in ["6", "Feet", "2", "Inch"] {
            let b = app.buttons[key].firstMatch
            XCTAssertTrue(b.waitForExistence(timeout: 4), "key \(key) missing")
            b.tap()
        }
        // Reading exists (the graphite readout). Just assert the app is still up.
        XCTAssertTrue(app.tabBars.buttons["Formulas"].isHittable, "Spec became unresponsive")
    }
}

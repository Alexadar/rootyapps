import XCTest

/// Proves the feet-inch keypad sheet on a tool dimension field: tap the field, punch a new value on
/// the glove keypad, Done → the field updates and the hero recomputes.
final class KeypadSheetTests: XCTestCase {

    func testRafterRunKeypad() {
        let app = XCUIApplication(); app.launch()
        app.tabBars.buttons["Formulas"].tap()
        let rafter = app.staticTexts["Rafter"].firstMatch
        XCTAssertTrue(rafter.waitForExistence(timeout: 5))
        rafter.tap()
        XCTAssertTrue(app.navigationBars["Rafter"].waitForExistence(timeout: 5))

        // Tap the Run feet-inch field (a Button whose label contains "Run").
        let run = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Run'")).firstMatch
        XCTAssertTrue(run.waitForExistence(timeout: 3), "Run field missing")
        run.tap()

        // Keypad sheet: punch 20 Feet, then Done.
        for k in ["2", "0", "Feet"] {
            let b = app.buttons[k].firstMatch
            XCTAssertTrue(b.waitForExistence(timeout: 3), "sheet key \(k) missing")
            b.tap()
        }
        app.buttons["Done"].firstMatch.tap()

        // Field reads 20' and the hero recomputes (13.4164"/ft × 20 = 268.33").
        XCTAssertTrue(app.staticTexts["20'"].waitForExistence(timeout: 3), "field did not update to 20'")
        XCTAssertTrue(app.staticTexts["268.33"].waitForExistence(timeout: 3), "hero did not recompute")
    }
}

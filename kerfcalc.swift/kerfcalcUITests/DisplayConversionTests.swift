import XCTest

/// Proves the imperial feet-inch-fraction DISPLAY and the metric CONVERSION are correct, by driving
/// the real running app and reading the on-screen strings (not just the unit math).
final class DisplayConversionTests: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    private func key(_ app: XCUIApplication, _ label: String) {
        let b = app.buttons[label].firstMatch
        XCTAssertTrue(b.waitForExistence(timeout: 3), "keypad key '\(label)' missing")
        b.tap()
    }

    /// 6'2½" + 2'7¾" must READ OUT as 8'10¼" (74.5" + 31.75" = 106.25" = 8'10¼").
    func testFeetInchFractionDisplay() {
        let app = XCUIApplication(); app.launch()
        for k in ["6", "Feet", "2", "Inch", "1", "⁄", "2"] { key(app, k) }
        XCTAssertTrue(app.staticTexts["6' 2-1/2\""].waitForExistence(timeout: 3),
                      "entry did not display as feet-inch-fraction")
        for k in ["+", "2", "Feet", "7", "Inch", "3", "⁄", "4", "="] { key(app, k) }
        XCTAssertTrue(app.staticTexts["8' 10-1/4\""].waitForExistence(timeout: 3),
                      "feet-inch-fraction addition displayed wrong")
    }

    /// The EXACT calculation shown in the reel: 8'4½" × 3 − 2'6" ÷ 2 must read out as 11'3¾".
    /// (Left-to-right tape math: 100.5"×3 = 301.5" − 30" = 271.5" ÷ 2 = 135.75" = 11'3¾".)
    func testReelCalculationResult() {
        let app = XCUIApplication(); app.launch()
        // enter 8'4½"
        for k in ["8", "Feet", "4", "Inch", "1", "⁄", "2"] { key(app, k) }
        XCTAssertTrue(app.staticTexts["8' 4-1/2\""].waitForExistence(timeout: 3), "8'4½\" entry wrong")
        // × 3
        for k in ["×", "3"] { key(app, k) }
        // − 2'6"
        for k in ["−", "2", "Feet", "6", "Inch"] { key(app, k) }
        // ÷ 2  =
        for k in ["÷", "2", "="] { key(app, k) }
        XCTAssertTrue(app.staticTexts["11' 3-3/4\""].waitForExistence(timeout: 3),
                      "reel calc did not equal 11'3¾\"")
    }

    /// CM-Pro dimension math on the tape: 10' × 8' must read out as area, 80 sq ft.
    func testTapeAreaMath() {
        let app = XCUIApplication(); app.launch()
        for k in ["1", "0", "Feet", "×", "8", "Feet", "="] { key(app, k) }
        XCTAssertTrue(app.staticTexts["80 sq ft"].waitForExistence(timeout: 3),
                      "10' × 8' should display as 80 sq ft")
    }

    /// The Convert tool must show metric correctly — the NIST default 1 ft = 0.3048 m.
    func testMetricConversionDisplay() {
        let app = XCUIApplication(); app.launch()
        app.tabBars.buttons["Formulas"].tap()
        let convert = app.staticTexts["Convert"].firstMatch
        var tries = 0
        while !convert.isHittable && tries < 14 { app.swipeUp(velocity: .init(rawValue: 500)); tries += 1 }
        XCTAssertTrue(convert.exists, "Convert tool tile missing")
        convert.tap()
        XCTAssertTrue(app.navigationBars["Convert"].waitForExistence(timeout: 5), "Convert detail did not load")
        // Default is 1 foot → metre.
        XCTAssertTrue(app.staticTexts["0.3048"].waitForExistence(timeout: 3),
                      "1 ft should convert to 0.3048 m (NIST)")
    }
}

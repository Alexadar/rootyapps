import XCTest

/// # The crown is testable, so it is tested
///
/// Everything here reads `fieldValue`, never `text`. Each watch control carries an explicit
/// `accessibilityLabel` ("Dry bulb") and puts its number in `accessibilityValue`, so the shared
/// label-first `text` helper returns the same constant name before and after the crown moves —
/// and three crown tests reported "the crown did not move the focused field" about a crown that
/// was working perfectly.
///
/// `XCUIDevice.rotateDigitalCrown(delta:)` has existed since Xcode 13. The crown being "hard to
/// test" is a myth that turns the single most important input on the watch into a manual check
/// nobody performs — so the crown-focus behaviour is a regression test here.
///
/// What can go wrong and would otherwise ship silently: the view loses focusability, the crown
/// binding is attached to a subview that is not focused, or tapping the other field fails to move
/// what the crown drives. Each of those leaves a watch app whose only input does nothing.
final class CrownUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    func testCrownChangesTheFocusedValue() throws {
        let dewPoint = app.staticTexts["watch.dewPoint"]
        XCTAssertTrue(dewPoint.waitForExistence(timeout: 15))

        let humidity = app.buttons["watch.field.relativeHumidity"]
        XCTAssertTrue(humidity.waitForExistence(timeout: 5))
        let before = humidity.fieldValue

        XCUIDevice.shared.rotateDigitalCrown(delta: 0.5)

        XCTAssertNotEqual(app.buttons["watch.field.relativeHumidity"].fieldValue, before,
                          "the crown did not move the focused field")
    }

    /// The crown must follow focus. If it always drove humidity, tapping dry bulb would look like
    /// it worked and then do nothing.
    func testCrownFollowsTheSelectedField() throws {
        let dryBulbField = app.buttons["watch.field.dryBulb"]
        XCTAssertTrue(dryBulbField.waitForExistence(timeout: 15))

        let humidityBefore = app.buttons["watch.field.relativeHumidity"].fieldValue
        dryBulbField.tap()
        let dryBulbBefore = dryBulbField.fieldValue

        XCUIDevice.shared.rotateDigitalCrown(delta: 0.4)

        XCTAssertNotEqual(app.buttons["watch.field.dryBulb"].fieldValue, dryBulbBefore,
                          "the crown did not move dry bulb after it was selected")
        XCTAssertEqual(app.buttons["watch.field.relativeHumidity"].fieldValue, humidityBefore,
                       "the crown moved the field that was not selected")
    }

    /// Whatever the crown does, the readout must keep up — a frozen dew point with a moving input
    /// is the bug this catches.
    func testTheReadoutFollowsTheCrown() throws {
        let dewPoint = app.staticTexts["watch.dewPoint"]
        XCTAssertTrue(dewPoint.waitForExistence(timeout: 15))
        let before = dewPoint.fieldValue

        XCUIDevice.shared.rotateDigitalCrown(delta: -0.6)

        XCTAssertNotEqual(app.staticTexts["watch.dewPoint"].fieldValue, before,
                          "the dew point did not follow the crown")
    }
}

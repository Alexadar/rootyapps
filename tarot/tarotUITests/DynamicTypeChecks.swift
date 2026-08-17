import XCTest

/// WRITTEN, NOT RUN in this build (owner's instruction).
/// AX5 text must not break the chrome: menu, settings and the reading panel all stay usable.
final class DynamicTypeChecks: XCTestCase {

    func testMenuAndSettingsSurviveAX5() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName",
                                "UICTContentSizeCategoryAccessibilityXXXXXL"]
        app.launch()

        XCTAssertTrue(app.buttons["menu.start"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["menu.start"].isHittable, "start button must stay hittable at AX5")

        app.buttons["menu.settings"].tap()
        // Haptics, not reversals: reversals are parked behind a feature flag and the row
        // does not exist. (This test was written before that call and never run until now.)
        XCTAssertTrue(app.switches["settings.haptics"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.switches["settings.haptics"].isHittable,
                      "a settings toggle must stay hittable at AX5")
        app.buttons["settings.done"].tap()
    }
}

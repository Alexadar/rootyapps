import XCTest

/// One test per defect this app has actually had. Each quotes the defect so nobody deletes it as
/// redundant with a Kit test — none of these are catchable below the UI.
final class DefectChecks: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    /// End the app the way a user does, so whatever it saves on the way out actually runs.
    ///
    /// The two platforms need genuinely different gestures, and getting this wrong made the test
    /// accuse the app of losing data when the app was fine.
    private func sendToBackground(_ app: XCUIApplication) {
        #if os(iOS)
        XCUIDevice.shared.press(.home)      // fires scenePhase, then kill
        app.terminate()
        #else
        // ⌘Q, not `terminate()`. XCUIApplication.terminate() kills the process, so AppKit never
        // sends `willTerminate` and nothing gets the chance to save — which made this test report
        // "persistence is broken" when what was broken was the way the test ended the app. No app
        // can save through a kill; ⌘Q is the quit a user actually performs.
        app.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 15), "the app did not quit on ⌘Q")
        #endif
    }

    // MARK: - The dead toggle

    /// **Defect: the duct material picker did nothing.** The design scaffold declared four
    /// materials with published roughness values and never passed them to the sizing routine, so
    /// the picker moved and the diameter did not. `DuctKit` proves the five roughness categories
    /// give five different diameters; only the UI proves the picker is wired to them.
    func testDuctRoughnessReachesTheAnswer() {
        let app = launchApp(tool: "duct")
        assertShows(app, "duct.hero", "Diameter")
        let before = any(app, "duct.hero").text + (any(app, "duct.hero").value as? String ?? "")

        tap(app, "duct.roughness")
        let rough = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == 'Rough' OR title == 'Rough'")).firstMatch
        XCTAssertTrue(rough.waitForExistence(timeout: 5))
        rough.tap()

        let after = any(app, "duct.hero").text + (any(app, "duct.hero").value as? String ?? "")
        XCTAssertNotEqual(before, after,
                          "the duct surface picker changed nothing — the dead toggle is back")
    }

    // MARK: - Stale text under a changed unit

    /// **Defect: changing a field's *quantity* left the old string in it.** Switching the second
    /// known from relative humidity to wet bulb re-used the field, and its text — "50" — was then
    /// parsed as 50 °F… except the value carried across was 1697 (50 % expressed in the old unit),
    /// which parsed as 1697 °F, went out of range, and the screen stopped solving.
    ///
    /// Caught on iPad only, because the layouts differ in when the field is rebuilt.
    func testChangingAKnownKeepsTheScreenSolvable() {
        let app = launchApp(tool: "psychrometrics")
        XCTAssertTrue(any(app, "psychro.known.second").waitForExistence(timeout: 10))

        tap(app, "psychro.known.second")
        let option = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == 'Wet bulb' OR title == 'Wet bulb'")).firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 5))
        option.tap()

        XCTAssertTrue(any(app, "psychrometrics.hero").waitForExistence(timeout: 5),
                      "the screen stopped solving: \(any(app, "psychro.error").text)")
        XCTAssertFalse(any(app, "psychro.error").exists)
        XCTAssertEqual(app.state, .runningForeground)
    }

    // MARK: - State surviving backgrounding

    /// **Requirement, not a defect — and the one thing model tests cannot prove.**
    /// `PersistenceTests` shows every model round-trips through `UserDefaults`. It cannot show
    /// `saveAll()` is ever *called*: that wiring is `scenePhase` in the App, and if it breaks every
    /// model test stays green while every real user loses their work to a phone call.
    func testAValueSurvivesBackgroundingAndRelaunch() {
        let app = launchApp(tool: "psychrometrics")
        let field = app.textFields["psychro.value.first"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))

        field.tap()
        field.replaceText(with: "81.5")
        XCTAssertTrue(field.waitForText(containing: "81"),
                      "the field never took the typed value: \(field.fieldValue)")
        let typed = field.fieldValue

        sendToBackground(app)

        // The one launch in the suite that inherits state on purpose.
        let relaunched = launchApp(tool: "psychrometrics", reset: false)
        let restored = relaunched.textFields["psychro.value.first"]
        XCTAssertTrue(restored.waitForExistence(timeout: 10))
        XCTAssertEqual(restored.fieldValue, typed,
                       "the value did not survive backgrounding — scenePhase saving is not wired")
    }

    /// Settings are app-wide and persist separately from the tools.
    func testElevationAndUnitsSurviveRelaunch() {
        let app = launchApp(tool: "psychrometrics")
        app.buttons["settings.elevation"].tap()
        XCTAssertTrue(any(app, "elevation.preset.Denver").waitForExistence(timeout: 5))
        tap(app, "elevation.preset.Denver")
        tap(app, "elevation.done")
        app.buttons["settings.units"].tap()

        // These chips announce their NAME in `label` ("Site elevation") and their state in
        // `value` ("5,280 feet"), so comparing `text` compares two identical names and would pass
        // however badly the setting was restored.
        let elevation = app.buttons["settings.elevation"].fieldValue
        let units = app.buttons["settings.units"].fieldValue

        sendToBackground(app)

        let relaunched = launchApp(tool: "psychrometrics", reset: false)
        XCTAssertTrue(relaunched.buttons["settings.elevation"].waitForExistence(timeout: 10))
        XCTAssertEqual(relaunched.buttons["settings.elevation"].fieldValue, elevation,
                       "elevation was not restored")
        XCTAssertEqual(relaunched.buttons["settings.units"].fieldValue, units,
                       "unit system was not restored")
    }

    // MARK: - The chart, both directions

    /// **The brief's requirement: neither direction may be second-class.** Typing-moves-the-point
    /// is exercised by every other test. Dragging-moves-the-values is a gesture on a `Canvas` and
    /// has no model-level equivalent at all.
    func testDraggingTheChartRewritesTheValues() {
        let app = launchApp(tool: "psychrometrics")
        let chart = any(app, "psychro.chart")
        XCTAssertTrue(chart.waitForExistence(timeout: 10))
        let before = signature(app, "psychrometrics.hero")

        let from = chart.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.45))
        let to = chart.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.65))
        from.press(forDuration: 0.05, thenDragTo: to)

        XCTAssertNotEqual(signature(app, "psychrometrics.hero"), before,
                          "dragging the chart changed nothing — the point is decorative")
        XCTAssertEqual(app.state, .runningForeground)
    }

    /// Above the saturation curve is not air. A drag there must clamp to the curve, not throw the
    /// screen into an error state.
    func testDraggingAboveSaturationClampsRatherThanBreaks() {
        let app = launchApp(tool: "psychrometrics")
        let chart = any(app, "psychro.chart")
        XCTAssertTrue(chart.waitForExistence(timeout: 10))

        let from = chart.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let to = chart.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.02))
        from.press(forDuration: 0.05, thenDragTo: to)

        XCTAssertTrue(any(app, "psychrometrics.hero").exists,
                      "dragging above saturation broke the screen instead of clamping")
        XCTAssertFalse(any(app, "psychro.error").exists)
    }

    // MARK: - Refusals must be visible

    /// Invalid input must produce an explanation, never a plausible number. 250 % relative
    /// humidity is the fastest way to reach that path from the keyboard.
    func testImpossibleInputShowsAnErrorNotANumber() {
        let app = launchApp(tool: "psychrometrics")
        let field = app.textFields["psychro.value.second"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))

        field.tap()
        field.replaceText(with: "250")

        XCTAssertTrue(any(app, "psychro.error").waitForExistence(timeout: 5),
                      "250 % relative humidity produced no error")
        XCTAssertFalse(any(app, "psychrometrics.hero").exists,
                       "a result stayed on screen for an impossible input")
        XCTAssertEqual(app.state, .runningForeground)
    }

    // MARK: - Altitude reaches the screen

    /// **The app's whole differentiator.** Every Kit is tested at three elevations; this proves the
    /// elevation the chip shows is the one the numbers were computed at.
    func testElevationChangesTheResults() {
        let app = launchApp(tool: "psychrometrics")
        XCTAssertTrue(any(app, "psychrometrics.hero").waitForExistence(timeout: 10))
        let atSeaLevel = signature(app, "psychrometrics.hero")

        app.buttons["settings.elevation"].tap()
        XCTAssertTrue(any(app, "elevation.preset.Denver").waitForExistence(timeout: 5))
        tap(app, "elevation.preset.Denver")
        tap(app, "elevation.done")

        XCTAssertNotEqual(signature(app, "psychrometrics.hero"), atSeaLevel,
                          "moving to Denver changed nothing on screen")
    }

    /// The elevation sheet has to say what the elevation *does*, not just what it is.
    func testElevationSheetShowsTheCorrectedConstant() {
        let app = launchApp(tool: "psychrometrics")
        app.buttons["settings.elevation"].tap()
        XCTAssertTrue(any(app, "elevation.preset.Denver").waitForExistence(timeout: 5))
        tap(app, "elevation.preset.Denver")

        let banner = any(app, "elevation.constantBanner")
        XCTAssertTrue(banner.waitForExistence(timeout: 5))
        // 0.889 — the constant is shown to three places, and the sheet also quotes the 1.08 it
        // corrects and the percentage it differs by, so the digits are matched rather than the
        // formatted string (this machine is in a comma-decimal locale).
        XCTAssertTrue(banner.text.normalisedDigits.contains("0889"),
                      "expected the Denver constant near 0.889, got: \(banner.text)")
    }

    // MARK: - Fan density

    /// The fan tool exists because flow does not scale with density and pressure and power do.
    /// Move the fan to altitude and the warning has to appear.
    func testFanDensityWarningAppearsAtAltitude() {
        let app = launchApp(tool: "fan")
        XCTAssertTrue(any(app, "fan.hero").waitForExistence(timeout: 10))
        XCTAssertFalse(any(app, "fan.densityBanner").exists,
                       "no density correction is due when both elevations are sea level")

        let field = app.textFields["fan.installedElevation"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.replaceText(with: "5280")

        XCTAssertTrue(any(app, "fan.densityBanner").waitForExistence(timeout: 5),
                      "moving the fan to 5,280 ft produced no density warning")
    }

    // MARK: - Pipe method

    /// Darcy and Hazen–Williams disagree by 2–20 %, and the app promises to say by how much. If
    /// the picker did nothing the banner would be stating a difference that isn't there.
    func testPipeMethodChangesTheAnswerAndTheBannerQuantifiesIt() {
        let app = launchApp(tool: "pipe")
        XCTAssertTrue(any(app, "pipe.hero").waitForExistence(timeout: 10))
        let darcy = signature(app, "pipe.headLoss")

        // A `.segmented` Picker is a row of buttons on iOS and a radio group on macOS, so its
        // options are not reachable as `.buttons` on both. Select by the option's own label.
        XCTAssertTrue(any(app, "pipe.method").waitForExistence(timeout: 5))
        // Scoped to the picker. An unscoped search for "Hazen" also matches the banner below it
        // ("Darcy and Hazen–Williams differ by …"), and tapping a banner does nothing at all —
        // so the test reported that the picker changed nothing when the picker was never touched.
        let hazen = any(app, "pipe.method").descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS 'Hazen' OR title CONTAINS 'Hazen'"))
            .firstMatch
        XCTAssertTrue(hazen.waitForExistence(timeout: 5), "the method picker offers no Hazen–Williams")
        hazen.tap()

        XCTAssertNotEqual(signature(app, "pipe.headLoss"), darcy,
                          "the head-loss method picker changed nothing")
        let banner = any(app, "pipe.methodBanner")
        XCTAssertTrue(banner.waitForExistence(timeout: 5))
        XCTAssertTrue(banner.text.contains("%"),
                      "the banner must quantify the gap: \(banner.text)")
    }
}

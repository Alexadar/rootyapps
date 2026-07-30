import XCTest

/// Live-pipeline, safety, and interaction checks: type real inputs and assert the app
/// recomputes correctly, that out-of-range entries are clamped (so nonsense can't reach the
/// math), that negatives work, and that theme choice persists.
final class InteractionChecks: XCTestCase {

    // MARK: helpers

    private func launch(_ tool: String? = nil, screen: Int = 0) -> XCUIApplication {
        let app = XCUIApplication()
        if let tool { app.launchEnvironment["TRUECOURSE_TOOL"] = tool }
        app.launchEnvironment["TRUECOURSE_SCREEN"] = String(screen)
        app.launch()
        return app
    }

    private func set(_ app: XCUIApplication, field id: String, to text: String) {
        let f = app.textFields[id].firstMatch
        XCTAssertTrue(f.waitForExistence(timeout: 8), "field ‘\(id)’ not found")
        f.tap()
        // Move the caret to the end (handles right-aligned fields) before clearing.
        f.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        if let cur = f.value as? String, !cur.isEmpty {
            f.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: cur.count + 3))
        }
        f.typeText(text)
    }

    /// Dismiss the keyboard / commit the field by tapping the top of the window.
    private func commit(_ app: XCUIApplication) {
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.06)).tap()
    }

    private func readout(_ app: XCUIApplication, _ label: String) -> String? {
        let el = app.descendants(matching: .any).matching(identifier: "result.\(label)").firstMatch
        guard el.waitForExistence(timeout: 8) else { return nil }
        return el.value as? String
    }

    // MARK: clamp safety ("worry-zero")

    func testAltimeterClampsToKollsmanRange() {
        let app = launch("altitude", screen: 1)   // altimeter setting field, range 28…31 inHg
        // Commit by moving focus to the sibling field (reliable on both platforms).
        set(app, field: "field.Altimeter setting", to: "99")
        app.textFields["field.Indicated altitude"].firstMatch.tap()
        XCTAssertEqual(app.textFields["field.Altimeter setting"].firstMatch.value as? String, "31",
                       "over-range altimeter should clamp to 31 inHg")
        set(app, field: "field.Altimeter setting", to: "10")
        app.textFields["field.Indicated altitude"].firstMatch.tap()
        XCTAssertEqual(app.textFields["field.Altimeter setting"].firstMatch.value as? String, "28",
                       "under-range altimeter should clamp to 28 inHg")
        app.terminate()
    }

    // MARK: live recompute — ISA identity cases

    func testSeaLevelStandardTasEqualsCas() {
        let app = launch("airspeed", screen: 0)
        set(app, field: "field.Calibrated airspeed", to: "150")
        set(app, field: "field.Pressure altitude", to: "0")
        set(app, field: "field.Outside air temp", to: "15")
        commit(app)
        XCTAssertEqual(readout(app, "True airspeed"), "150 kt",
                       "at ISA sea level TAS must equal CAS")
        app.terminate()
    }

    func testDensityAltitudeZeroAtStandardSeaLevel() {
        let app = launch("altitude", screen: 0)
        set(app, field: "field.Pressure altitude", to: "0")
        set(app, field: "field.Outside air temp", to: "15")
        commit(app)
        XCTAssertEqual(readout(app, "Density altitude"), "0 ft",
                       "standard-day sea level → DA 0")
        app.terminate()
    }

    func testColdNegativeTemperatureGivesNegativeDensityAltitude() {
        // Also proves the sign-capable keyboard: −15 °C must be enterable.
        let app = launch("altitude", screen: 0)
        set(app, field: "field.Pressure altitude", to: "0")
        set(app, field: "field.Outside air temp", to: "-15")
        commit(app)
        XCTAssertEqual(readout(app, "Density altitude"), "-3806 ft",
                       "cold day at sea level → negative DA")
        app.terminate()
    }

    func testDirectHeadwindSolution() {
        let app = launch("wind", screen: 0)
        set(app, field: "field.Course", to: "360")
        set(app, field: "field.True airspeed", to: "100")
        set(app, field: "field.Wind from", to: "360")
        set(app, field: "field.Wind speed", to: "20")
        commit(app)
        XCTAssertEqual(readout(app, "Heading"), "000°", "direct headwind → no crab")
        XCTAssertEqual(readout(app, "Groundspeed"), "80 kt", "GS = TAS − wind = 80")
        app.terminate()
    }

    // MARK: W&B out-of-envelope

    func testOverweightLoadingIsFlaggedOut() {
        let app = launch("wb", screen: 0)
        // The W&B station cells are right-aligned raw fields — select the number and replace it.
        let bag = app.textFields["station.Baggage"].firstMatch
        XCTAssertTrue(bag.waitForExistence(timeout: 8), "baggage field not found")
        bag.doubleTap()                                   // selects the existing value
        bag.typeText("500")                               // replaces the selection
        app.textFields["station.Fuel"].firstMatch.tap()   // commit baggage
        XCTAssertEqual(readout(app, "Gross weight"), "2020 lb", "1540 + 480 = 2020")
        // Read the verdict by its stable id via `.text` (raw `staticTexts["OUT"]` pins the type and
        // is empty-labelled on macOS). Loading-screen verdict is "IN ENVELOPE" / "OUT".
        let verdict = app.any("verdict.loading")
        XCTAssertTrue(verdict.waitForExistence(timeout: 4), "loading verdict not found")
        XCTAssertEqual(verdict.text, "OUT", "an overweight/aft load must read OUT")
        app.terminate()
    }

    // MARK: theme persistence

    func testNightModePersists() throws {
#if os(macOS)
        // The night toggle is a `.primaryAction` toolbar item; on macOS a non-key test window
        // disables the toolbar and collapses it into the "more toolbar items" overflow, where
        // XCUITest can't reach it by identifier (verified via app.debugDescription). This is a
        // toolbar/window-focus quirk, not an app bug — the ThemeStore @AppStorage persistence is
        // platform-independent and is exercised on iOS. (Parallels FavoritesChecks' regular-width skip.)
        throw XCTSkip("Night toggle sits in the macOS toolbar overflow; persistence is proven on iOS.")
#endif
        let app = launch()                          // root catalog — toolbar has the toggle
        // Query by identifier alone (trap 2): the toolbar toggle is a Button on iOS but publishes as
        // a different type on macOS, so `app.buttons["nightToggle"]` matches nothing on the Mac. Its
        // "on"/"off" string is set via .accessibilityValue, so `.value` is readable whatever the type.
        let toggle = app.any("nightToggle")
        XCTAssertTrue(toggle.waitForExistence(timeout: 8))
        if (toggle.value as? String) == "on" { toggle.tap() }   // normalize to off first
        app.any("nightToggle").tap()                             // → on
        XCTAssertEqual(app.any("nightToggle").value as? String, "on")
        app.terminate()

        let app2 = launch()                         // relaunch: choice persisted
        XCTAssertEqual(app2.any("nightToggle").value as? String, "on",
                       "night mode must survive relaunch")
        app2.any("nightToggle").tap()               // reset to off
        XCTAssertEqual(app2.any("nightToggle").value as? String, "off")
        app2.terminate()
    }
}

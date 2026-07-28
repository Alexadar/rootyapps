import XCTest

/// Asserts that every accessibility identifier the app promises actually resolves.
///
/// This exists because `ReelTour` has **no assertions** — it falls through
/// `buttons` → `otherElements` → `staticTexts` and taps whatever it finds, so a
/// broken identifier yields a subtly wrong marketing video rather than a red test.
/// `ReelTour` is a metronome and should stay one; this is the test.
///
/// Two rules learned the hard way, both encoded below:
///  * Query **type-agnostically**. The design system attaches identifiers to
///    `HStack` containers as well as `Text`, so `app.staticTexts[id]` misses them.
///  * Assert **existence, not string equality**. The label behind an identifier is
///    a design decision and changes freely (e.g. "0.42" became "0.42 ft/h").
///
/// NOTE: once this class exists, the reel capture must be invoked with
/// `ONLY_TESTING=marinenavUITests/ReelTour`, or this test runs inside the recording.
final class IdentifierChecks: XCTestCase {

    override func setUp() { continueAfterFailure = true }

    // MARK: - Per-tool identifier contracts

    func testTidesIdentifiers() {
        let app = launch(tool: "tides")
        expect(app, ["input.station", "input.day", "input.units",
                     "result.nowHeight", "result.nowSlope",
                     "chart.tideCurve", "result.extreme.0"])
    }

    func testCurrentsIdentifiers() {
        let app = launch(tool: "currents")
        expect(app, ["input.currentStation", "input.currentDay",
                     "result.nowVelocity", "result.nowSet",
                     "chart.currentCurve", "result.currentEvent.0"])
    }

    func testDeclinationIdentifiers() {
        let app = launch(tool: "declination")
        expect(app, ["input.latitude", "input.longitude", "input.altitude",
                     "input.trueHeading", "result.declination", "result.inclination",
                     "result.horizontal", "result.totalIntensity",
                     "result.magneticHeading", "chart.variationDial"])
    }

    func testDistanceBearingIdentifiers() {
        let app = launch(tool: "distanceBearing")
        expect(app, ["input.fromLat", "input.fromLon", "input.toLat", "input.toLon",
                     "input.course", "input.runDistance",
                     "result.distanceNM", "result.distanceKM",
                     "result.initialCourse", "result.finalCourse",
                     "result.arrivalLat", "result.arrivalLon", "result.arrivalCourse"])
    }

    func testSightReductionIdentifiers() {
        let app = launch(tool: "sightReduction")
        expect(app, ["input.hsDeg", "input.hsMin", "input.indexError", "input.indexSide",
                     "input.heightOfEye", "input.ghaDeg", "input.ghaMin",
                     "input.decDeg", "input.decMin",
                     "input.assumedLat", "input.assumedLon",
                     "result.dip", "result.ha", "result.refraction", "result.ho",
                     "result.lha", "result.hc", "result.zn", "result.intercept"])
    }

    // MARK: - The ReelTour contract
    //
    // ReelTour taps `buttons["tool.<raw>"]`, then the navigation-bar back button,
    // then swipes a scroll view. Each is asserted here on the element KIND the tour
    // actually queries — a redesign that turned the sidebar into a tab bar, or that
    // let a toolbar item become `navigationBars.buttons.firstMatch` on the detail
    // screen, would break the capture without breaking any other test.

    func testReelTourContract() {
        let app = XCUIApplication()
        app.launch()
        goToCatalog(app)

        for tool in ["tides", "currents", "declination", "distanceBearing", "sightReduction"] {
            XCTAssertTrue(app.buttons["tool.\(tool)"].firstMatch.waitForExistence(timeout: 5),
                          "ReelTour taps buttons[\"tool.\(tool)\"] — sidebar rows must stay buttons")
        }

        app.buttons["tool.currents"].firstMatch.tap()
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 5),
                      "ReelTour swipes app.scrollViews.firstMatch")

        let back = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 5),
                      "ReelTour taps navigationBars.buttons.firstMatch to go back")
        back.tap()
        XCTAssertTrue(app.buttons["tool.tides"].firstMatch.waitForExistence(timeout: 5),
                      "back() must return to the catalog, not somewhere else")
    }

    /// The catalog labels are ReelTour's last-resort fallback, so they are part of
    /// the contract too and must keep matching `Tool.title`.
    func testCatalogLabelsMatchToolTitles() {
        let app = XCUIApplication()
        app.launch()
        goToCatalog(app)
        for title in ["Tides", "Currents", "Declination", "Distance & Bearing", "Sight Reduction"] {
            XCTAssertTrue(app.staticTexts[title].firstMatch.waitForExistence(timeout: 5),
                          "ReelTour falls back to staticTexts[\"\(title)\"]")
        }
    }

    // MARK: - Helpers

    /// Deep-links straight to one tool via the `-tool` launch argument the capture
    /// scripts already use — far more reliable than driving the catalog.
    private func launch(tool: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-tool", tool]
        app.launch()
        return app
    }

    /// On iPhone the split view pushes straight to the initial tool, so the catalog
    /// sits behind the navigation-bar back button. On iPad/Mac the sidebar is already
    /// visible and this is a no-op.
    private func goToCatalog(_ app: XCUIApplication) {
        if app.buttons["tool.tides"].firstMatch.waitForExistence(timeout: 3) { return }
        let back = app.navigationBars.buttons.firstMatch
        if back.waitForExistence(timeout: 3) { back.tap() }
        _ = app.buttons["tool.tides"].firstMatch.waitForExistence(timeout: 5)
    }

    private func expect(_ app: XCUIApplication, _ identifiers: [String],
                        file: StaticString = #filePath, line: UInt = #line) {
        for id in identifiers {
            let element = app.descendants(matching: .any).matching(identifier: id).firstMatch
            XCTAssertTrue(element.waitForExistence(timeout: 5),
                          "identifier '\(id)' does not resolve", file: file, line: line)
        }
    }
}

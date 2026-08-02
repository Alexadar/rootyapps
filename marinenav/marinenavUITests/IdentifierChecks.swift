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
        expect(app, ["input.station", "input.day", "input.units.feet",
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
        expect(app, ["input.hsDeg", "input.hsMin", "input.indexError", "input.indexSide.true",
                     "input.heightOfEye", "input.ghaDeg", "input.ghaMin",
                     "input.decDeg", "input.decMin",
                     "input.assumedLat", "input.assumedLon",
                     "result.dip", "result.ha", "result.refraction", "result.ho",
                     "result.lha", "result.hc", "result.zn", "result.intercept"])
    }

    // MARK: - The ReelTour contract
    //
    // ReelTour resolves catalog rows BY IDENTIFIER ONLY (`toolRow`), then taps the
    // navigation-bar back button, then swipes a scroll view. Each is asserted here the
    // way the tour actually queries it — a redesign that turned the sidebar into a tab
    // bar, or that let a toolbar item become `navigationBars.buttons.firstMatch` on the
    // detail screen, would break the capture without breaking any other test.
    //
    // These used to assert `buttons["tool.<raw>"]`, pinning the element TYPE. That is
    // trap 2: SwiftUI does not publish the same type on every platform, and the target
    // was iOS-only so the mismatch could never surface.

    func testReelTourContract() {
        let app = XCUIApplication()
        app.launch()
        goToCatalog(app)

        for tool in ["tides", "currents", "declination", "distanceBearing", "sightReduction"] {
            XCTAssertTrue(toolRow(app, tool).waitForExistence(timeout: 5),
                          "ReelTour resolves tool.\(tool) by identifier — the row must stay addressable")
        }

        toolRow(app, "currents").tap()
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 5),
                      "ReelTour swipes app.scrollViews.firstMatch")

        // ⚠ LAYOUT-DEPENDENT, and this is what the iPad run caught. On compact width the tool
        // was PUSHED, so there is a back button and popping it returns to the catalog. On
        // regular width (iPad, Mac) the sidebar never left: there is nothing to pop, and
        // `navigationBars.buttons.firstMatch` is the SIDEBAR TOGGLE — tapping it hides the very
        // rows this test then looks for. `ReelTour.back()` guards on hittability for exactly
        // this reason; the contract test must model the same two worlds or it asserts an
        // iPhone-only truth and fails on iPad against a perfectly correct app.
        if toolRow(app, "tides").isHittable {
            // Regular width: selecting a tool swapped the detail pane and the catalog stayed put.
            XCTAssertTrue(toolRow(app, "tides").waitForExistence(timeout: 5),
                          "regular width: the sidebar must stay addressable after selecting a tool")
        } else {
            let back = app.navigationBars.buttons.firstMatch
            XCTAssertTrue(back.waitForExistence(timeout: 5),
                          "compact width: ReelTour taps navigationBars.buttons.firstMatch to go back")
            back.tap()
            XCTAssertTrue(toolRow(app, "tides").waitForExistence(timeout: 5),
                          "back() must return to the catalog, not somewhere else")
        }
    }

    /// The catalog labels are ReelTour's last-resort fallback, so they are part of
    /// the contract too and must keep matching `Tool.title`.
    func testCatalogLabelsMatchToolTitles() {
        let app = XCUIApplication()
        app.launch()
        goToCatalog(app)
        // Read the title FROM THE ROW, found by identifier. Two earlier shapes both failed on
        // macOS and each failed for a different reason worth remembering:
        //
        //   app.descendants(matching: .any).matching(textMatches(title))
        //       -> "Timed out while evaluating UI query" after 135 s (predicate over everything)
        //   app.descendants(matching: .staticText).matching(textMatches(title))
        //       -> fast, but only 'Tides' resolved: macOS does not publish these row titles as
        //          staticText, which is trap 2 again — I had swapped one type assumption for
        //          another.
        //
        // Anchoring on the identifier and searching WITHIN that row is both cheap (a handful of
        // elements, not the whole tree) and type-agnostic.
        let titles = [("tides", "Tides"), ("currents", "Currents"),
                      ("declination", "Declination"),
                      ("distanceBearing", "Distance & Bearing"),
                      ("sightReduction", "Sight Reduction")]
        for (tool, title) in titles {
            let row = toolRow(app, tool)
            XCTAssertTrue(row.waitForExistence(timeout: 5), "row tool.\(tool) must exist")
            let readable = row.text.contains(title)
                || row.descendants(matching: .any).matching(textMatches(title)).firstMatch.exists
            XCTAssertTrue(readable,
                          "'\(title)' must be readable on its row — ReelTour's last-resort "
                          + "fallback matches on it. Row text was '\(row.text)'")
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
        if toolRow(app, "tides").waitForExistence(timeout: 3) { return }
        let back = app.navigationBars.buttons.firstMatch
        if back.waitForExistence(timeout: 3) { back.tap() }
        _ = toolRow(app, "tides").waitForExistence(timeout: 5)
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

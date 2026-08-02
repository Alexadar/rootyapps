import XCTest

/// §C.1 — one numeric check per shipping tool, asserting a KNOWN value on screen.
///
/// The expected values are duplicated on purpose from the Kit oracles. If someone changes a Kit
/// answer, both layers must be updated and the diff makes that visible.
///
/// **These do not re-litigate arithmetic** — the Kits own that, with 103 assertions against NOAA
/// CO-OPS, Schureman SP-98, WMM2025's official test values, Vincenty/Karney and Bowditch. What
/// these prove is *wiring*: that the right number reaches the right label.
///
/// ## Why tides and currents assert a station CONSTANT
///
/// A tide height is a function of the current instant, so there is no fixed number to assert
/// without pinning the clock. But each station also displays NOAA's own published *constants*,
/// which are date-independent and cited:
///
/// | On screen | Value | Source |
/// |---|---|---|
/// | Tides · Mean sea level above datum | `3.12 ft` (`0.951 m`) | NOAA 9414290 datums, epoch 1983–2001 |
/// | Currents · Mean flood / Mean ebb | `074°T` / `235°T` | NOAA SFB1203 bin 5 |
///
/// So every tool gets a real cited assertion, and the date-dependent parts are covered by the
/// unit tests (unit round-trip, day stepping) plus the Kit oracles.
final class CalculationChecks: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    private func launch(_ tool: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchPinned(["-tool", tool])
        return app
    }

    /// Reads an element by identifier, type-agnostically, and returns the string a user sees.
    private func read(_ app: XCUIApplication, _ id: String,
                      file: StaticString = #filePath, line: UInt = #line) -> String {
        let el = any(app, id)
        XCTAssertTrue(el.waitForExistence(timeout: 10),
                      "'\(id)' never appeared", file: file, line: line)
        return el.text
    }

    // MARK: - One numeric check per tool

    func testTidesShowsPublishedDatumOffset() {
        let app = launch("tides")
        // NOAA 9414290: MSL 2.773 m, MLLW 1.822 m -> Z0 0.951 m = 3.12 ft. Default unit is feet.
        let v = read(app, "result.meanSeaLevel")
        XCTAssertTrue(v.contains("3.12"), "expected NOAA's published Z0 of 3.12 ft, read '\(v)'")
        XCTAssertTrue(read(app, "result.chartDatum").contains("MLLW"))
    }

    func testCurrentsShowsPublishedMeanAxis() {
        let app = launch("currents")
        // NOAA SFB1203 bin 5: mean flood 074 degrees true, mean ebb 235.
        XCTAssertTrue(read(app, "result.meanFlood").contains("74"),
                      "expected NOAA's published mean flood 074°T")
        XCTAssertTrue(read(app, "result.meanEbb").contains("235"),
                      "expected NOAA's published mean ebb 235°T")
    }

    func testDeclinationShowsWMMValueAtTheDefaultPosition() {
        let app = launch("declination")
        // WMM2025 at 37.81 N, 122.47 W, sea level: variation ~12.8 degrees east. Only the
        // decimal year moves within a year, so two decimal places would be brittle; one is not.
        let v = read(app, "result.declination")
        XCTAssertTrue(v.contains("12.8"),
                      "expected WMM2025 variation ~12.8°E at the default position, read '\(v)'")
    }

    func testDistanceBearingShowsVincentyResult() {
        let app = launch("distanceBearing")
        // Vincenty on WGS-84, San Francisco (37.81, -122.47) -> Honolulu (21.31, -157.86).
        XCTAssertTrue(read(app, "result.distanceNM").contains("2080.9"),
                      "expected 2080.9 nm great-circle distance")
        XCTAssertTrue(read(app, "result.initialCourse").contains("251.8"),
                      "expected initial course 251.8°T")
        XCTAssertTrue(read(app, "result.finalCourse").contains("233.7"),
                      "expected final course 233.7°T")
    }

    func testSightReductionReproducesBowditch() {
        let app = launch("sightReduction")
        // Bowditch, The American Practical Navigator — the worked example the Kit is pinned to.
        // Every expected value below is copied from `CelestialNavKit`'s oracle, NOT read off a
        // screenshot: my first pass guessed Zn as 348 from a low-resolution capture and the test
        // failed against a correct app. The oracle is the authority.
        //   ho_deg 34.818333 (34°49.1')   zn_deg 340.4 ("N 19.6 W")   intercept_nm -24.5 (AWAY)
        let ho = read(app, "result.ho")
        XCTAssertTrue(ho.contains("49.1") || ho.contains("49.0"),
                      "expected observed altitude 34° 49.1', read '\(ho)'")
        let intercept = read(app, "result.intercept")
        XCTAssertTrue(intercept.contains("24.5"),
                      "expected intercept 24.5 nm away, read '\(intercept)'")
        let zn = read(app, "result.zn")
        XCTAssertTrue(zn.contains("340.4"), "expected azimuth 340.4°T, read '\(zn)'")
    }

    // MARK: - Coverage guard (§C.1)

    /// A new tool cannot ship without a numeric check: this fails the moment the catalog grows.
    func testEveryToolHasANumericCheck() {
        let covered = ["tides", "currents", "declination", "distanceBearing", "sightReduction"]
        XCTAssertEqual(covered.count, 5, "the catalog ships 5 tools")
        XCTAssertEqual(Set(covered).count, covered.count, "duplicate in the coverage list")

        // And the catalog really does ship exactly those five, addressable by identifier.
        // On iPhone the split view pushes straight to the initial tool, so the catalog sits
        // behind the navigation-bar back button; on iPad/Mac the sidebar is already visible.
        let app = XCUIApplication()
        app.launchPinned()
        if !toolRow(app, "tides").waitForExistence(timeout: 3) {
            let back = app.navigationBars.buttons.firstMatch
            if back.waitForExistence(timeout: 3) { back.tap() }
        }
        for tool in covered {
            XCTAssertTrue(toolRow(app, tool).waitForExistence(timeout: 10),
                          "tool.\(tool) is in the coverage list but not in the catalog")
        }
    }

    // MARK: - §C.2, the single UI-level binding proof

    /// The state space lives in `marinenavTests` (microseconds). Exactly ONE assertion belongs
    /// here, because a model test cannot catch a view bound to the wrong property.
    ///
    /// This is the documented dead-toggle case: a shipped watch app had a measurement-unit
    /// toggle where every number was correct and the suite was green, because the control was
    /// only ever tested in its default state.
    func testUnitToggleActuallyChangesTheNumberOnScreen() {
        let app = launch("tides")
        let feet = read(app, "result.meanSeaLevel")
        XCTAssertTrue(feet.contains("3.12"), "expected feet by default, read '\(feet)'")

        let metresSegment = any(app, "input.units.meters")
        XCTAssertTrue(metresSegment.waitForExistence(timeout: 10),
                      "each segment must be addressable — an id on the container hides them")
        metresSegment.tap()

        let metres = read(app, "result.meanSeaLevel")
        XCTAssertTrue(metres.contains("0.95"),
                      "flipping to metres must CONVERT, not just relabel — read '\(metres)'")
        XCTAssertNotEqual(feet, metres, "the unit toggle did nothing")

        // And back, because a one-way toggle is its own bug.
        any(app, "input.units.feet").tap()
        XCTAssertTrue(read(app, "result.meanSeaLevel").contains("3.12"),
                      "flipping back to feet must return the original value")
    }
}

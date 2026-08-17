import XCTest

/// The surfaces added by the coverage redesign: the two Sky destinations, gate-0, export and the
/// astrocartography map.
///
/// Run on an iPhone 17 Pro simulator, iOS 26.5. Writing them was not enough — the first run failed
/// two of six, and both failures were real:
///
/// - `sky.moon.row` did not exist. The card's `.accessibilityIdentifier` on the enclosing `VStack`
///   propagated down and **overwrote** the rows' own, so both buttons answered to
///   `card.skyDestinations`. The feature worked perfectly; only the handle was wrong.
///   `.accessibilityElement(children: .contain)` before the identifier fixes it.
/// - `toolbar.export` matched twice. SwiftUI publishes a toolbar item as BOTH an `Other` and a
///   `Button` at the same frame, so `descendants(matching: .any)` is ambiguous and `tap()` throws.
///   Query `.buttons[...]`.
///
/// A third defect fell out of reading the accessibility dump rather than any assertion: the Hours
/// row read "No sunrise today" for **Los Angeles**. See `HourRingTests.aZoneMismatchIsNotReported…`.
final class CoverageChecks: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    // MARK: - Sky destinations

    /// The rows exist and carry a real value, not just a label. A row reading only "Moon" would
    /// pass a naive existence check while telling the user nothing.
    func testSkyShowsBothDestinationRows() {
        let app = XCUIApplication().launchPinned(tab: 0)
        app.launch()

        let moon = app.descendants(matching: .any)["sky.moon.row"]
        let hours = app.descendants(matching: .any)["sky.hours.row"]
        XCTAssertTrue(moon.waitForExistence(timeout: 10), "Sky must offer the Moon row")
        XCTAssertTrue(hours.exists, "Sky must offer the Hours row")

        // The label carries a percentage — proof the row is reading the engine, not a placeholder.
        XCTAssertTrue(moon.label.contains("%"),
                      "the Moon row should show illumination, got '\(moon.label)'")
    }

    /// `EPHEMERIS_LENS=moon` used to select a segment and now pushes a screen. The capture pipeline
    /// sets it, so the value must still land on the calendar.
    func testMoonDeepLinkPushesTheCalendar() {
        let app = XCUIApplication().launchPinned(tab: 0, lens: "moon")
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["card.moonCalendar"].waitForExistence(timeout: 10),
                      "EPHEMERIS_LENS=moon must open the moon calendar")
    }

    func testHoursDeepLinkPushesTheRing() {
        let app = XCUIApplication().launchPinned(tab: 0, lens: "hours")
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["card.planetaryHours"].waitForExistence(timeout: 10),
                      "EPHEMERIS_LENS=hours must open the hours ring")
    }

    /// The picker went back to four. Six segments do not fit an iPhone in sixteen languages, and a
    /// fifth reappearing is the regression this catches on a device rather than in a unit test.
    func testTheSkyLensPickerHasFourSegments() {
        let app = XCUIApplication().launchPinned(tab: 0)
        app.launch()
        let picker = app.descendants(matching: .any)["input.lens"]
        XCTAssertTrue(picker.waitForExistence(timeout: 10))
        XCTAssertEqual(picker.buttons.count, 4,
                       "the lens control must offer exactly four readings of the moment")
    }

    // MARK: - Export

    /// The sheet states the count BEFORE the share control. An export that silently produced the
    /// wrong window would look identical to one that worked.
    func testExportStatesItsCountBeforeActing() {
        let app = XCUIApplication().launchPinned(tab: 4)   // Cycles · Timeline
        app.launch()

        // `.buttons[...]`, not `descendants(matching: .any)`: SwiftUI publishes a toolbar item as
        // BOTH an Other and a Button at the same frame, so the looser query is ambiguous and
        // `tap()` fails with "Multiple matching elements" on a perfectly good toolbar.
        let button = app.buttons["toolbar.export"]
        XCTAssertTrue(button.waitForExistence(timeout: 10), "the timeline must offer export")
        button.tap()

        let count = app.descendants(matching: .any)["export.count"]
        XCTAssertTrue(count.waitForExistence(timeout: 5), "the sheet must state a count")
        XCTAssertTrue(app.descendants(matching: .any)["export.range"].exists,
                      "the sheet must state a range")
        XCTAssertFalse(count.label.isEmpty)
        // And the file name is visible before anything is written.
        XCTAssertTrue(app.descendants(matching: .any)["export.filename"].exists)
    }

    // MARK: - Astrocartography

    /// Per-chart, so it lives in the chart detail. Reached by opening the library's first chart.
    func testAstrocartographyRowIsPresentInAChart() {
        let app = XCUIApplication().launchPinned(tab: 5)   // Charts
        app.launch()

        // The library is empty on a fresh install; this check is meaningful only with a chart, so
        // skip rather than assert a false negative.
        let firstChart = app.cells.firstMatch
        guard firstChart.waitForExistence(timeout: 10) else {
            XCTSkip("no saved charts on this device — astrocartography is per-chart")
            return
        }
        firstChart.tap()

        let row = app.descendants(matching: .any)["chart.astrocartography"]
        let unavailable = app.descendants(matching: .any)["chart.astrocartography.unavailable"]
        XCTAssertTrue(row.waitForExistence(timeout: 10) || unavailable.exists,
                      "a chart must either offer the map or say why it cannot")
    }
}

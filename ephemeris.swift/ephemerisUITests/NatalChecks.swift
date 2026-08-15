import XCTest

/// The natal section, end to end through the UI.
///
/// The Kit proves the numbers and `NatalViewModelTests` proves the library's state machine. This
/// proves the **wiring** — that a saved chart's computed values reach the right labels on the right
/// lens, which no model test can catch because a view bound to the wrong property still compiles.
///
/// The library is seeded via `EPHEMERIS_SEED_CHARTS` rather than by driving the entry form. Creating
/// a chart through the form on every test would be slow and would make each of these a test of the
/// form instead of the thing under test. The fixtures carry **fixed UUIDs** so rows are addressable.
///
/// Expected values are the same fixture the Kit asserts (Olena, 1990-03-15 14:30 UTC, Berlin), so if
/// the Kit and the UI ever disagree, one of these two suites fails.
final class NatalChecks: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    private static let olena = "chart.11111111-1111-4111-8111-111111111111"
    private static let untimed = "chart.44444444-4444-4444-8444-444444444444"

    /// Charts is section 5 in the legacy deep-link map.
    private func library() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["EPHEMERIS_SEED_CHARTS"] = "1"
        return app.launchPinned(tab: 5)
    }

    private func openOlena() -> XCUIApplication {
        let app = library()
        let row = any(app, Self.olena)
        XCTAssertTrue(row.waitForExistence(timeout: 20), "the seeded library must list Olena")
        row.tap()
        return app
    }

    // MARK: - Library

    func testLibraryListsSavedCharts() {
        let app = library()
        XCTAssertTrue(any(app, "screen.natal").waitForExistence(timeout: 20))
        XCTAssertTrue(any(app, Self.olena).exists)
        XCTAssertTrue(any(app, Self.untimed).exists)
        // Where the data lives is a claim the app makes to the user; it must be on screen.
        XCTAssertTrue(any(app, "state.storageKind").exists)
    }

    // MARK: - Opening a chart

    func testOpeningAChartShowsItsBirthData() {
        let app = openOlena()
        let heading = any(app, "heading.readout")
        XCTAssertTrue(heading.waitForExistence(timeout: 20),
                      "an opened chart is headed 'Natal chart', not just 'Chart'")
        XCTAssertTrue(any(app, "input.comparison").exists, "the Natal/Transits control")
        XCTAssertTrue(any(app, "chart.wheel").exists, "opens on the wheel")
    }

    // MARK: - The four lenses

    /// Positions for the seeded chart, against the values `NatalChartTests` pins in the Kit.
    func testPositionsLensShowsKnownNatalValues() {
        let app = openOlena()
        XCTAssertTrue(any(app, "chart.wheel").waitForExistence(timeout: 20))

        selectLens(app, "Positions")
        XCTAssertTrue(any(app, "card.positions").waitForExistence(timeout: 10))
        XCTAssertEqual(any(app, "pos.sun.degrees").text, "24° 45′", "Sun, natal")
        XCTAssertEqual(any(app, "pos.moon.degrees").text, "10° 59′", "Moon, natal")
        XCTAssertEqual(any(app, "pos.saturn.degrees").text, "23° 19′", "Saturn, natal")
    }

    func testHousesLensShowsKnownAngles() {
        let app = openOlena()
        XCTAssertTrue(any(app, "chart.wheel").waitForExistence(timeout: 20))

        selectLens(app, "Houses")
        XCTAssertTrue(any(app, "card.houses").waitForExistence(timeout: 10))
        XCTAssertEqual(any(app, "angle.ac.degrees").text, "28° 00′", "Ascendant, natal")
        XCTAssertEqual(any(app, "angle.mc.degrees").text, "16° 18′", "Midheaven, natal")
    }

    func testAspectsLensListsNatalAspects() {
        let app = openOlena()
        XCTAssertTrue(any(app, "chart.wheel").waitForExistence(timeout: 20))

        selectLens(app, "Aspects")
        XCTAssertTrue(any(app, "card.aspects").waitForExistence(timeout: 10))
        // Sun sextile Saturn, orb 1.43° — the tightest aspect in this chart.
        XCTAssertTrue(any(app, "aspect.sun.saturn.orb").text.contains("1.4"),
                      "expected Sun–Saturn ≈1.43°, got '\(any(app, "aspect.sun.saturn.orb").text)'")
    }

    // MARK: - Transits

    /// The comparison control turns the wheel into a bi-wheel. Asserted through the cross-aspect
    /// list, which only exists while comparing — the outer ring itself is drawn in a `Canvas` and
    /// publishes no separate element.
    func testTransitsComparisonAddsTheCrossAspectList() {
        let app = openOlena()
        XCTAssertTrue(any(app, "chart.wheel").waitForExistence(timeout: 20))
        XCTAssertFalse(any(app, "card.transits").exists, "not comparing by default")

        let transits = segment(app, in: "input.comparison", titled: "Transits")
        guard transits.exists else { return XCTFail("the Transits segment must be addressable") }
        transits.tap()
        XCTAssertTrue(any(app, "card.transits").waitForExistence(timeout: 10),
                      "comparing against the current sky lists the cross-aspects")
    }

    // MARK: - Unknown birth time

    /// Houses are undefined without a birth time. The app must say so rather than draw cusps from an
    /// assumed noon — a chart that looks precise and is wrong is worse than one that admits a gap.
    func testUntimedChartExplainsWhyHousesAreMissing() {
        let app = library()
        let row = any(app, Self.untimed)
        XCTAssertTrue(row.waitForExistence(timeout: 20))
        row.tap()

        XCTAssertTrue(any(app, "state.timeUnknown").waitForExistence(timeout: 15),
                      "the missing birth time is explained, not silently ignored")

        selectLens(app, "Houses")
        XCTAssertTrue(any(app, "card.houses").waitForExistence(timeout: 10))
        XCTAssertFalse(any(app, "angle.ac.degrees").exists,
                       "no Ascendant is drawn for a chart with no birth time")
    }

    // MARK: - Helper

    /// Taps a lens in the readout's segmented control.
    ///
    /// By visible title rather than by index: a segmented control's children differ in type between
    /// iOS and macOS, and an index is not the visual order on either.
    private func selectLens(_ app: XCUIApplication, _ title: String) {
        let seg = segment(app, in: "input.lens", titled: title)
        guard seg.exists else { return XCTFail("lens '\(title)' must be addressable") }
        seg.tap()
    }
}

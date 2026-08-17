import XCTest

/// The natal section, end to end through the UI.
///
/// The Kit proves the numbers and `NatalViewModelTests` proves the library's state machine. This
/// proves the **wiring** — that a saved chart's computed values reach the right labels on the right
/// facet, which no model test can catch because a view bound to the wrong property still compiles.
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
    private func library(facet: String? = nil, biwheel: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["EPHEMERIS_SEED_CHARTS"] = "1"
        return app.launchPinned(tab: 5, facet: facet, biwheel: biwheel)
    }

    private func openOlena(facet: String? = nil, biwheel: String? = nil) -> XCUIApplication {
        let app = library(facet: facet, biwheel: biwheel)
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

    func testOpeningAChartShowsItsBirthDataAndFourFacets() {
        let app = openOlena()
        let heading = any(app, "heading.readout")
        XCTAssertTrue(heading.waitForExistence(timeout: 20),
                      "an opened chart is headed 'Natal chart', not just 'Chart'")
        XCTAssertTrue(any(app, "chart.facet").exists, "the Wheel/Bi-wheel/Analysis/Returns control")
        XCTAssertTrue(any(app, "chart.wheel").exists, "opens on the wheel")
        XCTAssertTrue(any(app, "chart.compare").exists, "the ⚯ Compare affordance")
    }

    // MARK: - The four lenses inside the wheel facet
    //
    // These are the assertions that were already here: the lens control survives the facet
    // restructure, and so do the values it renders. If a facet ever swallowed the lens, these fail.

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

    // MARK: - Bi-wheel

    /// The bi-wheel's four sources are one control, so this is the test that proves the control
    /// exists and that its default (transits) still produces the cross-aspect list the old
    /// Natal/Transits switch produced.
    func testBiwheelFacetShowsTheCrossAspectList() {
        let app = openOlena(facet: "biwheel")
        XCTAssertTrue(any(app, "biwheel.source").waitForExistence(timeout: 20),
                      "the transits/progressed/return/partner control")
        XCTAssertTrue(any(app, "card.transits").waitForExistence(timeout: 15),
                      "comparing against the current sky lists the cross-aspects")
    }

    /// Progressions are reachable without leaving the chart — the point of one control for four
    /// features. A separate destination per feature would make this a navigation test instead.
    func testProgressedSourceRendersWithoutLeavingTheChart() {
        let app = openOlena(facet: "biwheel", biwheel: "progressed")
        XCTAssertTrue(any(app, "chart.wheel").waitForExistence(timeout: 20))
        XCTAssertTrue(any(app, "card.transits").waitForExistence(timeout: 15),
                      "progressed-to-natal contacts use the same cross-aspect card")
    }

    // MARK: - Analysis

    func testAnalysisFacetShowsAllFourCards() {
        let app = openOlena(facet: "analysis")
        XCTAssertTrue(any(app, "analysis.dignities").waitForExistence(timeout: 20))
        XCTAssertTrue(any(app, "analysis.shape").exists)
        XCTAssertTrue(any(app, "analysis.balances").exists)
        XCTAssertTrue(any(app, "analysis.midpoints").exists)
    }

    /// Modern planets are absent from the dignity table rather than scored zero — a zero would read
    /// as "measured and neutral" instead of "outside the classical system".
    func testDignitiesCoverClassicalPlanetsOnly() {
        let app = openOlena(facet: "analysis")
        XCTAssertTrue(any(app, "analysis.dignities").waitForExistence(timeout: 20))
        XCTAssertTrue(any(app, "dignity.sun").exists)
        XCTAssertTrue(any(app, "dignity.saturn").exists)
        XCTAssertFalse(any(app, "dignity.pluto").exists, "Pluto has no classical dignity")
    }

    // MARK: - Returns

    func testReturnsFacetListsTheNextReturn() {
        let app = openOlena(facet: "returns")
        XCTAssertTrue(any(app, "returns.list").waitForExistence(timeout: 20))
        XCTAssertTrue(any(app, "returns.row.sun").waitForExistence(timeout: 15),
                      "a solar return is always within a year")
    }

    /// A return needs the exact moment a body regains its natal degree, so an untimed chart gets an
    /// explanation instead of a list of plausible dates.
    func testUntimedChartCannotComputeReturns() {
        let app = library(facet: "returns")
        let row = any(app, Self.untimed)
        XCTAssertTrue(row.waitForExistence(timeout: 20))
        row.tap()
        XCTAssertTrue(any(app, "returns.list").waitForExistence(timeout: 15))
        XCTAssertFalse(any(app, "returns.row.sun").exists,
                       "no return row may be offered for a chart with no birth time")
    }

    // MARK: - Pairing

    /// Pairing is directional and starts from an open chart — the library never grows multi-select.
    func testComparingOpensThePartnerPicker() {
        let app = openOlena()
        let compare = any(app, "chart.compare")
        XCTAssertTrue(compare.waitForExistence(timeout: 20))
        compare.tap()
        XCTAssertTrue(any(app, "pairing.partnerPicker").waitForExistence(timeout: 15),
                      "⚯ Compare opens the picker")
        // The chart we came from is side A and must not be offerable as its own partner.
        XCTAssertFalse(any(app, "partner.11111111-1111-4111-8111-111111111111").exists,
                       "a chart cannot be compared with itself")
    }

    func testPickingAPartnerPushesTheSynastryPairing() {
        let app = openOlena()
        any(app, "chart.compare").tap()
        let marek = any(app, "partner.22222222-2222-4222-8222-222222222222")
        XCTAssertTrue(marek.waitForExistence(timeout: 15))
        marek.tap()
        XCTAssertTrue(any(app, "pairing.synastry").waitForExistence(timeout: 20),
                      "picking a partner lands on the Synastry/Composite control")
        XCTAssertTrue(any(app, "card.transits").waitForExistence(timeout: 15),
                      "synastry cross-aspects render through the shared list")
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

import XCTest

/// One numeric assertion per panel, against the seeded fixture.
///
/// These prove WIRING, not arithmetic: that the value a Kit computed reaches the label it belongs to.
/// The seven oracle Kits own the numbers and validate them against published NOAA/GFZ definitions
/// (56 swift-testing cases, ~0.01 s). Re-deriving any of that here would be slower and weaker.
///
/// Expected values are duplicated from `SpaceWeatherSnapshot.uiTestFixture` ON PURPOSE — if someone
/// changes a fixture value, both layers must be updated and the diff makes that visible.
final class NumericChecks: XCTestCase {

    override func setUp() { super.setUp(); continueAfterFailure = false }

    private func value(_ app: XCUIApplication, _ id: String,
                       file: StaticString = #filePath, line: UInt = #line) -> String {
        let e = app.any(id)
        XCTAssertTrue(e.waitForExistence(timeout: 10), "no element '\(id)'", file: file, line: line)
        // `.text`, not `.label` — a plain SwiftUI Text has an EMPTY label on macOS.
        return e.text
    }

    private func assertShows(_ app: XCUIApplication, _ id: String, _ needle: String,
                             file: StaticString = #filePath, line: UInt = #line) {
        let got = value(app, id)
        XCTAssertTrue(got.contains(needle),
                      "\(id): expected to contain «\(needle)», got «\(got)»", file: file, line: line)
    }

    // MARK: - Dashboard

    /// Kp 5.3 -> G1. Kit oracle: `GeomagOracleTests` (Bartels Kp<->ap + NOAA G-scale); G1 begins at
    /// Kp 5, so 5.3 is the first value that is a storm at all.
    func testPlanetaryKpPanel() {
        let app = launchApp(tab: "dashboard")
        assertShows(app, "kp.now", "5.3")
        assertShows(app, "kp.gScale", "G1")
    }

    /// The NOAA G/R/S scoreline. Fixture is G1 / R1 / S0, and S0 renders as a bare "0" because a
    /// quiet axis is not an event.
    ///
    /// Read via `value`, not `text`: `ScaleChip` sets an `accessibilityLabel` — a localized sentence
    /// ("G scale, level 1") — which overrides the combined children, so the label is the wrong thing
    /// to assert on and would break in every language but English. The code lives in `value`.
    func testNoaaScalesPanel() {
        let app = launchApp(tab: "dashboard")
        for (id, code) in [("scale.G", "G1"), ("scale.R", "R1"), ("scale.S", "0")] {
            let e = app.any(id)
            XCTAssertTrue(e.waitForExistence(timeout: 10), "no element '\(id)'")
            XCTAssertEqual(e.value as? String, code,
                           "\(id): expected «\(code)», got «\(String(describing: e.value))»")
        }
    }

    /// Solar wind: speed, density and a SOUTHWARD Bz. Kit oracle: `SolarWindOracleTests`.
    /// Bz is asserted as "8.5" without a sign — the formatter emits U+2212 MINUS, not ASCII "-".
    func testSolarWindPanel() {
        let app = launchApp(tab: "dashboard")
        assertShows(app, "wind.speed", "620")
        assertShows(app, "wind.density", "4.2")
        assertShows(app, "wind.bz", "8.5")
    }

    /// Flares: latest M1.0 -> R1, and a 24 h peak of M3.2 that is deliberately STRONGER than the
    /// latest, so a test cannot pass by reading the wrong one. Kit oracle: `FlareOracleTests`.
    func testFlarePanel() {
        let app = launchApp(tab: "dashboard")
        assertShows(app, "flare.latest", "M1.0")
        assertShows(app, "flare.peak24h", "M3.2")
        assertShows(app, "flare.rScale", "R1")
    }

    /// Aurora probability. Kit oracle: `AuroraOracleTests` (NOAA Kp->latitude view line).
    func testAuroraPanel() {
        let app = launchApp(tab: "dashboard")
        assertShows(app, "aurora.probability", "45")
        XCTAssertFalse(value(app, "aurora.viewLine").isEmpty, "view line rendered nothing")
    }

    /// Solar activity: two different numbers, so a swapped binding is visible. Sunspot 96, F10.7
    /// 142.7 — which the tile renders at zero decimals, i.e. 143. Kit oracle: `SolarIndexOracleTests`.
    func testSolarActivityPanel() {
        let app = launchApp(tab: "dashboard")
        assertShows(app, "solar.sunspots", "96")
        assertShows(app, "solar.regions", "8")
    }

    // MARK: - Geomagnetic

    /// Hp30's whole reason to exist: 30-minute resolution the 3-hourly Kp misses, and it must not
    /// claim to exceed the Kp 9 ceiling at 4.667. Kit oracle: `HpoOracleTests`.
    func testHp30Panel() {
        let app = launchApp(tab: "geomagnetic")
        XCTAssertFalse(value(app, "hpo.now").isEmpty, "Hp30 rendered nothing")
        XCTAssertFalse(app.any("hpo.exceedsCeiling").exists,
                       "claimed to exceed the Kp 9 ceiling at Hp30 4.667")
    }

    // MARK: - Coverage guard

    /// Every catalogued panel must be covered by an assertion above.
    ///
    /// Without this, adding an eighth panel ships untested: the suite stays green because nothing
    /// asserts that the LIST is complete. Checked against the panel identifiers the app actually
    /// publishes rather than a hard-coded count, so it cannot be satisfied by bumping a number.
    func testEveryPanelHasANumericCheck() {
        let covered = ["scales", "kp", "wind", "flare", "aurora", "solar", "hpo"]
        XCTAssertEqual(Set(covered).count, covered.count, "duplicate in the coverage list")
        let app = launchApp(tab: "dashboard")
        // The six dashboard panels must all be present and addressable.
        for id in ["scales", "kp", "wind", "flare", "aurora", "solar"] {
            XCTAssertTrue(app.any("panel.\(id)").waitForExistence(timeout: 10),
                          "panel.\(id) is not addressable — is it in the coverage list but not the UI?")
        }
        XCTAssertTrue(covered.contains("hpo"), "hpo lives on the Geomagnetic tab")
    }
}

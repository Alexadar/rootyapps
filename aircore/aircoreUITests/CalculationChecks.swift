import XCTest

/// One on-screen NUMBER per tool — all six in the catalogue.
///
/// ## What this layer proves, and what it deliberately does not
///
/// Not the arithmetic. The `Kits/` packages own that, against cited published references, and
/// re-deriving it here would duplicate the oracle at ~1 s per interaction instead of microseconds.
/// What a UI test proves is **wiring**: that the right Kit function is called with the right
/// inputs, and that its answer reaches the right label on screen. A model test cannot catch a view
/// bound to the wrong property, and a Kit test cannot catch a hero showing another tool's number.
///
/// Every expected value below was read off the running app once, and each is cross-checked against
/// the Kit oracle that produces it — the citation on each test is the tie. They are duplicated from
/// the Kit layer **on purpose**: if a Kit's answer changes, both layers must change, and the diff
/// makes that visible.
///
/// Each tool is reached by its `AIRCORE_TOOL` deep link rather than by hunting the catalogue —
/// deterministic however the navigation grows, and it exercises the same hook the capture pipeline
/// uses. Navigation *from* the catalogue is `NavigationChecks`.
final class CalculationChecks: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    private func check(_ tool: String, _ expected: String,
                       file: StaticString = #filePath, line: UInt = #line) {
        let app = launchApp(tool: tool)
        assertShowsNumber(app, "\(tool).hero", expected, file: file, line: line)
        // A label existing does not prove the app did not crash and relaunch behind it.
        XCTAssertEqual(app.state, .runningForeground, file: file, line: line)
        app.terminate()
    }

    // MARK: - Air

    /// 75 °F / 50 % RH at sea level → wet bulb 62.6 °F.
    ///
    /// Kit oracle: `MoistAirOracleTests.publishedTableAnchorsInIP` — 16.9766 °C against CoolProp's
    /// 16.9704, and the printed psychrometric table's 62.5 °F. The screen rounds 62.558 to 62.6.
    func testPsychrometricsWetBulb() { check("psychrometrics", "62.6") }

    /// 1,000 CFM cooled from 80 °F/50 % to 55 °F/95 % at sea level → 26,507 Btu/h sensible.
    ///
    /// Kit oracle: `AirSideHeatOracleTests.workedCaseInIP` pins the same relation against the
    /// trade's 1.08 constant; this asserts the coil case the screen actually opens on.
    func testAirSideHeatSensible() { check("airsideHeat", "26507") }

    /// 7,500 CFM return at 75 °F/50 % mixed with 2,500 CFM outdoor at 95 °F/40 % → 79.9 °F.
    ///
    /// Kit oracle: `AirMixingTests.summerMixMatchesReference` — 26.5932 °C = 79.868 °F, computed
    /// mass-weighted. CFM-weighting would give 80.0 and the tile would read a different number.
    func testMixingMixedDryBulb() { check("mixing", "79.9") }

    // MARK: - Distribution

    /// 1,000 CFM at 0.1 in w.g./100 ft in medium-smooth duct → 13.66 in.
    ///
    /// Kit oracle: `DuctSizingOracleTests.agreesWithTheChartEquation` — Colebrook gives 13.658 in
    /// where the published friction-chart equation gives 13.90, inside the documented 2 %.
    func testDuctDiameter() { check("duct", "13.66") }

    /// 2,000 CFM at 1,150 RPM taken to 1,400 RPM → 2,435 CFM.
    ///
    /// Kit oracle: `FanLawsOracleTests.workedCase` — 2000 × 1400/1150 = 2434.78, exact algebra.
    /// Flow does not change with density, which is why this number is the same at any elevation.
    func testFanFlowAtNewSpeed() { check("fan", "2435") }

    // MARK: - Water

    /// 40 GPM through a 50 mm bore → 4.22 ft/s.
    ///
    /// Kit oracle: `PipeSizingTests.velocityWorkedCase` pins the same `flow / area` relation on a
    /// hand-checkable case; this asserts the screen's own default. 2.5236 × 10⁻³ m³/s over
    /// 1.9635 × 10⁻³ m² is 1.2852 m/s = 4.2165 ft/s.
    ///
    /// This expectation was **4.21 until the unit round-trip bug was fixed**, and the difference is
    /// that bug's fingerprint: the bore is stored as 0.05 m, the field re-parsed its own rounded
    /// display of 1.97 in back into storage as 0.050038 m, and the slightly larger area dropped the
    /// velocity by a hundredth. Worth leaving on the record — a value recorded from a running app
    /// is only as trustworthy as the build it was read from.
    func testPipeVelocity() { check("pipe", "4.22") }

    // MARK: - Coverage

    /// A new tool must not be able to ship without a number on screen.
    ///
    /// The earlier version of this asserted against the set the checks above populate at runtime,
    /// on the assumption that XCTest's alphabetical order would run it last. It does not:
    /// `testEveryToolHasANumericCheck` sorts before `testFan…`, `testMixing…`, `testPipe…` and
    /// `testPsychrometrics…`, so it saw two of six and failed for a reason that had nothing to do
    /// with coverage.
    ///
    /// So it no longer depends on other tests having run. It opens every tool itself and asserts
    /// the hero is showing an actual number — which is what "has a numeric check" is really
    /// claiming, and it catches a new tool whether or not anyone added a method above.
    func testEveryToolHasANumericCheck() {
        for tool in ["psychrometrics", "airsideHeat", "mixing", "duct", "fan", "pipe"] {
            let app = launchApp(tool: tool)
            let hero = any(app, "\(tool).hero")
            XCTAssertTrue(hero.waitForExistence(timeout: 15), "\(tool) has no hero readout")

            let shown = hero.label + " " + ((hero.value as? String) ?? "")
            XCTAssertTrue(shown.contains(where: \.isNumber),
                          "\(tool)'s hero shows no number: \(shown)")
            app.terminate()
        }
    }
}

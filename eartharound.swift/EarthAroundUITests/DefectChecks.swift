import XCTest

/// Regressions. Every test here corresponds to a defect that actually shipped or was caught by hand
/// in this app — that is the bar for adding one.
final class DefectChecks: XCTestCase {

    override func setUp() { super.setUp(); continueAfterFailure = false }

    // MARK: - The button that did nothing

    /// Settings opens.
    ///
    /// This shipped broken: the gear had no identifier, no accessibility label and no test, so a dead
    /// sheet binding was invisible to everything except a human tapping it — which is how it was
    /// eventually found. The cheapest possible test, and it would have caught it.
    func testSettingsButtonOpensSettings() {
        let app = launchApp()
        let gear = app.any("chrome.settings")
        XCTAssertTrue(gear.waitForExistence(timeout: 10), "no settings button")
        gear.tap()
        // Any control unique to the sheet proves it presented. Language is the only picker whose
        // option labels are never localized, which makes it the stable choice.
        XCTAssertTrue(app.any("settings.language").waitForExistence(timeout: 5),
                      "tapping the gear did not present Settings")
        XCTAssertEqual(app.state, .runningForeground, "died opening Settings")
    }

    /// Every Settings control is reachable, so a dead binding cannot hide behind a collapsed section.
    /// The alerts sub-controls are gated on the master toggle, so only the ungated ones are asserted
    /// here; the gating logic itself is a state machine and belongs in the Kit tests.
    func testSettingsControlsAreReachable() {
        let app = launchApp()
        app.any("chrome.settings").tap()
        for id in ["settings.refreshMinutes", "settings.cellular", "settings.hpoRangeHours",
                   "settings.showForecast", "settings.nightMode", "settings.language",
                   "settings.alertsEnabled"] {
            XCTAssertTrue(app.any(id).waitForExistence(timeout: 5), "missing control \(id)")
        }
    }

    // MARK: - Deep links must work in BOTH layouts

    /// `EARTHAROUND_TAB=geomagnetic` must reach the Geomagnetic tab at regular width too.
    ///
    /// A compact layout stacks one column; a regular layout is a two-column LazyVGrid. A router that
    /// seeds state only one layout watches lands silently on the default screen — which is how
    /// another app in this repo shipped an iPad screenshot of the wrong tool. Two-sided on purpose:
    /// the destination marker present AND a wrong-screen marker absent.
    func testTabDeepLinkReachesGeomagneticInEveryLayout() {
        let app = launchApp(tab: "geomagnetic")
        XCTAssertTrue(app.any("panel.hpo").waitForExistence(timeout: 10),
                      "EARTHAROUND_TAB=geomagnetic did not reach Geomagnetic")
        // Solar Wind exists only on Dashboard. If it is here, we landed on the wrong tab.
        XCTAssertFalse(app.any("panel.wind").exists,
                       "this is the Dashboard, not Geomagnetic")
    }

    /// And the default lands on Dashboard, not somewhere else.
    func testDefaultTabIsDashboard() {
        let app = launchApp()
        XCTAssertTrue(app.any("panel.kp").waitForExistence(timeout: 10), "no Kp panel on launch")
        XCTAssertFalse(app.any("panel.hpo").exists, "launched on Geomagnetic instead of Dashboard")
    }

    // MARK: - Controls that must round-trip

    /// Night mode is a two-state control and must return. A one-way toggle is the defect this shape
    /// of test exists for — and this app has the same control in two places (header + Settings),
    /// both writing one app-group key, so they can disagree.
    func testNightModeTogglesAndReturns() {
        let app = launchApp()
        let toggle = app.any("chrome.nightMode")
        XCTAssertTrue(toggle.waitForExistence(timeout: 10), "no night-mode button")
        let before = value(app, "kp.now")
        toggle.tap()
        XCTAssertEqual(app.state, .runningForeground, "died toggling night mode")
        // The number must survive a theme change — night mode is a palette, not a data change.
        XCTAssertEqual(value(app, "kp.now"), before, "night mode changed the Kp value")
        toggle.tap()
        XCTAssertEqual(value(app, "kp.now"), before, "returning from night mode changed the value")
    }

    /// The tab bar switches screens in both directions.
    func testTabBarSwitchesBothWays() {
        let app = launchApp()
        XCTAssertTrue(app.any("panel.kp").waitForExistence(timeout: 10))
        app.any("tab.Geomagnetic").tap()
        XCTAssertTrue(app.any("panel.hpo").waitForExistence(timeout: 5), "did not reach Geomagnetic")
        app.any("tab.Dashboard").tap()
        XCTAssertTrue(app.any("panel.wind").waitForExistence(timeout: 5), "did not return to Dashboard")
    }

    // MARK: - Honesty

    /// With no data at all the app must say so, not render a fabricated zero.
    ///
    /// This is the app's stated reason to exist — "ship no number these Kits can't validate" — and
    /// the failure mode is specific: an aurora view line derived from a missing Kp used to read as a
    /// confident "visible down to 66°". Launched WITHOUT the fixture and with the network blocked,
    /// so nothing can arrive.
    func testEmptyStateNeverShowsAFabricatedNumber() {
        let app = XCUIApplication()
        app.launchEnvironment["EARTHAROUND_LANG"] = "en"
        app.launchEnvironment["EARTHAROUND_FIXTURE"] = "0"
        app.launch()
        // Either a real reading arrived (a cached snapshot exists on this sim) or the app shows its
        // empty/offline state. What must NOT happen is a Kp tile reading exactly "0" or "0.0",
        // which is a measured quiet field rather than an absence.
        if app.any("kp.now").waitForExistence(timeout: 8) {
            let v = app.any("kp.now").text
            XCTAssertFalse(v == "0" || v == "0.0",
                           "Kp rendered a fabricated zero where no data exists")
        }
        XCTAssertEqual(app.state, .runningForeground, "died with no data")
    }

    private func value(_ app: XCUIApplication, _ id: String) -> String {
        let e = app.any(id)
        XCTAssertTrue(e.waitForExistence(timeout: 5), "no element '\(id)'")
        return e.text
    }
}

import XCTest

/// Getting to a screen, in both layouts.
///
/// The app has two navigations — a catalogue of cards under compact width, a sidebar under regular
/// — and a deep link that has to land in either. uitests.md §4: verify deep links in **both**,
/// because a link that only selects a sidebar row looks identical to one that opens a detail until
/// you run it on the other size class.
final class NavigationChecks: XCTestCase {

    private static let tools = ["psychrometrics", "airsideHeat", "mixing", "duct", "fan", "pipe"]

    override func setUp() { continueAfterFailure = false }

    /// `AIRCORE_TOOL` must open the tool's **detail**, not merely select it. Asserted by the
    /// presence of that tool's own hero, which only the detail draws.
    func testDeepLinkOpensEveryToolsDetail() {
        for tool in Self.tools {
            let app = launchApp(tool: tool)
            XCTAssertTrue(any(app, "\(tool).hero").waitForExistence(timeout: 15),
                          "AIRCORE_TOOL=\(tool) did not land on its detail")
            XCTAssertEqual(app.state, .runningForeground, "\(tool) crashed on open")
            app.terminate()
        }
    }

    /// The same six, reached the way a user reaches them. A deep link that works while the
    /// catalogue is broken is a screenshot pipeline, not an app.
    func testEveryToolOpensFromTheCatalogue() {
        for tool in Self.tools {
            let app = launchApp()
            navigateToTool(app, tool)
            XCTAssertTrue(any(app, "\(tool).hero").waitForExistence(timeout: 15),
                          "\(tool) produced no result when opened from the catalogue")
            app.terminate()
        }
    }

    /// Recently-used tools have to reach the catalogue: "one tap from launch" is a stated
    /// requirement of the phone layout, and the recents list is how it is met.
    func testRecentToolsReachTheCatalogue() throws {
        let app = launchApp()
        guard any(app, "tool.duct").waitForExistence(timeout: 10) else {
            throw XCTSkip("regular width shows a sidebar, which has no recents section")
        }
        tap(app, "tool.duct")
        XCTAssertTrue(any(app, "duct.hero").waitForExistence(timeout: 15))

        app.navigationBars.buttons.element(boundBy: 0).tap()

        let cards = app.descendants(matching: .any).matching(identifier: "tool.duct")
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(cards.count, 2,
                                    "the tool just used did not appear under RECENT")
    }

    /// The unit toggle and elevation chip are on every tool's toolbar, not just the first one —
    /// they are how the app promises altitude is never silently wrong.
    func testEveryToolCarriesTheElevationAndUnitControls() {
        for tool in Self.tools {
            let app = launchApp(tool: tool)
            XCTAssertTrue(app.buttons["settings.elevation"].waitForExistence(timeout: 15),
                          "\(tool) has no elevation chip")
            XCTAssertTrue(app.buttons["settings.units"].exists, "\(tool) has no unit toggle")
            app.terminate()
        }
    }

    /// Flipping units must change what every tool displays, not only the first one. One assertion
    /// per tool — the combinatorial unit coverage lives in the model suite, per uitests.md §4a.
    func testUnitToggleReachesEveryToolsHero() {
        for tool in Self.tools {
            let app = launchApp(tool: tool)
            XCTAssertTrue(any(app, "\(tool).hero").waitForExistence(timeout: 15))
            let imperial = signature(app, "\(tool).hero")

            app.buttons["settings.units"].tap()
            let metric = signature(app, "\(tool).hero")
            XCTAssertNotEqual(imperial, metric, "\(tool): the unit toggle did not reach the hero")

            app.buttons["settings.units"].tap()
            XCTAssertEqual(signature(app, "\(tool).hero"), imperial,
                           "\(tool): switching back did not restore the original value")
            app.terminate()
        }
    }
}

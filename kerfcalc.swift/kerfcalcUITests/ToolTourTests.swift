import XCTest

/// Screen-level smoke tour: open every one of the 20 tools and assert each (a) loads its detail nav
/// bar, (b) renders its cited FormulaCard, and — for the marquee tools — (c) shows its known default
/// hero value. This is the per-screen coverage the unit tests can't give: it catches a view-wiring or
/// crash regression on any tool, across the whole app.
///
/// Each tool is reached by its `KERFCALC_TOOL` deep link rather than by scroll-hunting the grid. That
/// is deterministic regardless of how long the catalog grows (scroll-hunting broke once the Liquid
/// Glass bar pinned the "Formulas" title, since the old scroll-to-top sentinel became always-visible),
/// and it exercises the same deep link the reel and screenshot pipelines depend on. Navigation *from*
/// the grid stays covered by `FavoritesFlowTests` and `RegularLayoutTests`.
final class ToolTourTests: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    /// (Tool.rawValue, nav-bar title, optional known default hero value rendered on the screen).
    private let tools: [(deepLink: String, title: String, hero: String?)] = [
        ("rafter", "Rafter", "173.57"), ("stairs", "Stairs", "14"), ("pitch", "Right Angle", nil),
        ("concrete", "Concrete", "1.235"), ("footing", "Footing", nil), ("rebar", "Rebar", nil),
        ("aggregate", "Aggregate", nil), ("pavers", "Pavers", nil),
        ("area", "Area", nil), ("volume", "Volume", nil),
        ("roofing", "Roofing", "22.36"), ("estimate", "Estimate", nil), ("miter", "Miter", nil),
        ("lumber", "Lumber", nil), ("mortar", "Mortar", nil),
        ("offset", "Offset", "14.14"), ("rollingOffset", "Rolling Offset", "14.14"),
        ("cutLength", "Cut Length", "21.00"), ("grade", "Grade", "10.00"),
        ("units", "Convert", "0.3048"),
    ]

    func testEveryToolLoadsAndShowsFormulaCard() {
        for tool in tools {
            let app = XCUIApplication()
            app.launchEnvironment["KERFCALC_TOOL"] = tool.deepLink
            app.launch()

            // The detail is on screen: its title (nav bar on compact, inline header on regular).
            let titled = app.navigationBars[tool.title].waitForExistence(timeout: 8)
                || app.staticTexts[tool.title].firstMatch.waitForExistence(timeout: 4)
            XCTAssertTrue(titled, "\(tool.title) detail did not load")

            // Its cited FormulaCard rendered — proves the screen wired up and didn't crash.
            XCTAssertTrue(app.staticTexts["FORMULA"].waitForExistence(timeout: 6),
                          "FormulaCard missing on \(tool.title)")

            if let hero = tool.hero {
                XCTAssertTrue(app.staticTexts[hero].waitForExistence(timeout: 5),
                              "\(tool.title) hero \(hero) not rendered")
            }
            app.terminate()
        }
    }
}

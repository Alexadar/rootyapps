import XCTest

/// §C.2 wiring proof for the sub-screen pickers. A model test can't catch a `SubScreenPicker` bound
/// to the wrong index, or a view that renders the wrong sub-screen for a selection — only a real tap
/// can. One assertion per pill: after tapping `seg.<i>`, an element unique to that sub-screen is
/// present. (Per-screen numeric *accuracy* is covered by AccuracyChecks via deep links; this proves
/// the tap actually switches.)
final class StateSpaceChecks: XCTestCase {

    /// tool → each pill index and an identifier that only that sub-screen publishes.
    private let matrix: [(tool: String, pills: [(seg: Int, marker: String)])] = [
        ("wind",     [(0, "result.Heading"), (1, "result.Crosswind (from right)"), (2, "result.Wind from")]),
        ("airspeed", [(0, "result.True airspeed"), (1, "result.Mach number")]),
        ("altitude", [(0, "result.Density altitude"), (1, "result.Pressure altitude"), (2, "result.Freezing level")]),
        ("nav",      [(0, "result.Time enroute"), (1, "result.Distance flown"), (2, "result.Groundspeed")]),
        ("fuel",     [(0, "result.Fuel burned"), (1, "result.Endurance"), (2, "result.Specific range")]),
        ("climb",    [(0, "result.Descent rate"), (1, "result.Required climb rate"), (2, "result.Glide distance")]),
        ("wb",       [(0, "result.Centre of gravity"), (1, "verdict.envelope")]),
    ]

    func testEverySubScreenPillSwitches() {
        for m in matrix {
            let app = launchTrueCourse(tool: m.tool, screen: 0)
            for p in m.pills {
                let pill = app.any("seg.\(p.seg)")
                XCTAssertTrue(pill.waitForExistence(timeout: 8), "[\(m.tool)] pill seg.\(p.seg) missing")
                pill.tap()
                let marker = app.any(p.marker)
                XCTAssertTrue(marker.waitForExistence(timeout: 8),
                              "[\(m.tool)] tapping seg.\(p.seg) should reveal ‘\(p.marker)’")
            }
            app.terminate()
        }
    }
}

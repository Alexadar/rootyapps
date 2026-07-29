import XCTest

/// The guardrail that keeps the media pipeline from rotting.
///
/// `make_sim_shots.sh` and the reel both depend on `PAR_TOOL=<slug>` opening the right screen. Nothing
/// else in the app exercises that path, so without this test a renamed case or a typo'd slug would be
/// discovered as a folder of screenshots all showing the same tool — after the capture, not before it.
///
/// It asserts, unlike `ReelTour`: this one is allowed to fail the build.
final class DeepLinkTests: XCTestCase {

    /// Every slug the capture scripts use, with an identifier that only exists on that screen.
    private static let tools: [(slug: String, marker: String)] = [
        ("tvm", "tvm.hero"),
        ("amortization", "amort.hero"),
        ("cashflow", "cashflow.provenance"),
        ("bond", "bond.provenance"),
        ("rate", "rate.hero"),
        ("depreciation", "dep.hero"),
        ("dates", "daycount.provenance"),
        ("percent", "percent.hero"),
        ("statistics", "stat.provenance"),
        ("realestate", "realestate.hero"),
    ]

    func testEveryDeepLinkOpensItsOwnScreen() {
        for tool in Self.tools {
            let app = XCUIApplication()
            app.launchEnvironment["PAR_TOOL"] = tool.slug
            app.launch()

            let marker = app.descendants(matching: .any)[tool.marker].firstMatch
            XCTAssertTrue(
                marker.waitForExistence(timeout: 8),
                "PAR_TOOL=\(tool.slug) did not open the screen carrying \(tool.marker)"
            )
            app.terminate()
        }
    }

    /// An unrecognised slug must fall back to the default screen rather than showing something
    /// arbitrary — a capture script with a typo should produce an obviously wrong folder, not a
    /// subtly wrong one.
    func testUnknownDeepLinkFallsBackToTheDefaultScreen() {
        let app = XCUIApplication()
        app.launchEnvironment["PAR_TOOL"] = "not-a-tool"
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["tvm.hero"].firstMatch.waitForExistence(timeout: 8))
    }
}

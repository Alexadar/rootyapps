import XCTest

/// Deep-link driven, never scroll-hunting. `BIGPINKCAT_DEMO=<n>` puts the app straight into a demo,
/// which is the same door the capture pipeline uses. Simulator only — see ../uitests.md §3 for the
/// macOS accessibility traps that turn an iOS-green suite red.
final class DemoNavigationChecks: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    func testLaunchesIntoTheHeroDemo() {
        let app = XCUIApplication()
        app.launchEnvironment["BIGPINKCAT_DEMO"] = "5"   // warp bubble wall
        app.launchEnvironment["BIGPINKCAT_TIME"] = "2.0" // frozen clock, reproducible frame
        app.launch()
        XCTAssertTrue(app.otherElements["readout"].waitForExistence(timeout: 10),
                      "the readout must be on screen — a blank Metal view is the failure mode")
    }

    func testEveryDemoInTheCatalogIsReachable() {
        let app = XCUIApplication()
        app.launch()
        for raw in 1...18 {
            let button = app.buttons["demo.\(raw)"]
            XCTAssertTrue(button.waitForExistence(timeout: 5), "demo \(raw) missing from the catalog")
        }
    }
}

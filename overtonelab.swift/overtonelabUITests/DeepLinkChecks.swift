import XCTest

/// Deep links have to land in BOTH layouts.
///
/// The trap: a compact layout pushes onto a `NavigationStack`, a regular one selects in a
/// `NavigationSplitView`, and they are driven by *different* state. A router that seeds only the stack
/// path leaves every deep link at regular width sitting on the placeholder screen — which is how an
/// iPad screenshot of a calculator ends up captioned as something it never showed.
///
/// `RootView` seeds both `selection` and `path` from the same `deepLinkTool()`, so this is a guard
/// against that regression rather than a hunt for it. It must run on an iPhone sim **and** an iPad
/// sim: passing on one proves nothing about the other, and on macOS the split view is the only layout.
final class DeepLinkChecks: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    /// The tool deep link reaches the tool's own screen, not the catalog and not the placeholder.
    func testToolDeepLinkReachesItsScreenInThisLayout() {
        let app = XCUIApplication()
        app.launchEnvironment["OVERTONELAB_TOOL"] = "sabine"
        app.launchEnvironment["OVERTONELAB_LANG"] = "en"
        app.launch()

        // Sabine's own hero. The placeholder ("Select a tool") publishes no such identifier, so this
        // fails rather than passing on a screen that merely rendered.
        XCTAssertTrue(any(app, "result.sabine").waitForExistence(timeout: 15),
                      "the tool deep link landed somewhere other than Sabine")
    }

    /// The sub-screen deep link, which the screenshot pipeline depends on: `OVERTONELAB_SCREEN`
    /// selects a tool's second tab, so a capture can frame a screen that isn't the first one.
    func testSubScreenDeepLinkSelectsThatSubScreen() {
        let app = XCUIApplication()
        app.launchEnvironment["OVERTONELAB_TOOL"] = "spl"
        app.launchEnvironment["OVERTONELAB_SCREEN"] = "1"      // SPL → Summation
        app.launchEnvironment["OVERTONELAB_LANG"] = "en"
        app.launch()

        // Summation's own text; the Distance screen (screen 0) never shows it.
        let marker = app.descendants(matching: .any)
            .containing(textMatches("Combined (incoherent)")).firstMatch
        XCTAssertTrue(marker.waitForExistence(timeout: 15),
                      "OVERTONELAB_SCREEN=1 did not select the second sub-screen")

        // And the first screen's hero must NOT be the thing on display.
        XCTAssertFalse(any(app, "result.spl").exists,
                       "the sub-screen link left the first screen on show")
    }
}

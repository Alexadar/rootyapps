import XCTest

/// The regression for the crown-focus defect that shipped in build 8.
///
/// ## The bug
///
/// `.digitalCrownRotation(…)` only delivers to the view that currently HOLDS FOCUS, and `Button` is
/// focusable by default — `.focusable()` makes focus *possible*, it never keeps it. So on the Tempo
/// screen, tapping **Tap tempo** — which is the entire reason that screen exists on a wrist — moved
/// focus off the tempo field and the crown went dead. Nothing crashed, nothing looked wrong: the
/// number simply stopped responding, and every later tap re-applied a stale value.
///
/// ## Why this is a test and not a note asking someone to remember
///
/// `XCUIDevice.rotateDigitalCrown(delta:)` has existed since Xcode 13 — `XCUIDevice.h`, gated on
/// `TARGET_OS_WATCH`, surfaced to Swift by apinotes from `rotateDigitalCrownByDelta:`. The whole
/// interaction is scriptable. Only *rendering* (does the icon look right inside the watch's circular
/// mask) still needs eyes.
///
/// `testCrownStillWorksAfterTappingTapTempo` is the point of this file: before the fix, the second
/// rotation changed nothing at all.
final class CrownFocusChecks: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    private func tempoScreen() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-otl.watch.lastTool", "tempo"]
        app.launch()
        return app
    }

    private func hero(_ app: XCUIApplication) -> XCUIElement { any(app, "result.tempo") }

    func testCrownChangesTheTempo() {
        let app = tempoScreen()
        let readout = hero(app)
        XCTAssertTrue(readout.waitForExistence(timeout: 30), "the Tempo hero must appear")

        let atDefault = readout.readoutValue
        XCTAssertFalse(atDefault.isEmpty, "the hero must publish a readable value")

        XCUIDevice.shared.rotateDigitalCrown(delta: 5)
        XCTAssertNotEqual(readout.readoutValue, atDefault,
                          "turning the crown must change the note length")
    }

    /// ⚠ THE REGRESSION. Scrub, tap the focus thief, scrub again.
    func testCrownStillWorksAfterTappingTapTempo() {
        let app = tempoScreen()
        let readout = hero(app)
        XCTAssertTrue(readout.waitForExistence(timeout: 30))

        // 1 — move the value, proving the crown starts out live.
        let atDefault = readout.readoutValue
        XCUIDevice.shared.rotateDigitalCrown(delta: 5)
        let afterFirstScrub = readout.readoutValue
        XCTAssertNotEqual(afterFirstScrub, atDefault,
                          "precondition: the crown works before anything is tapped")

        // 2 — tap the button that steals focus. One tap does not itself set a tempo (the tap-tempo
        //     estimator needs four), so any change from here on is the crown's doing.
        let tapTempo = any(app, "input.tapTempo")
        XCTAssertTrue(tapTempo.waitForExistence(timeout: 10), "the tap-tempo button must be present")
        tapTempo.tap()

        // 3 — the crown must still be live. This is what failed before `CrownFocus.reclaim()`.
        XCUIDevice.shared.rotateDigitalCrown(delta: 5)
        XCTAssertNotEqual(readout.readoutValue, afterFirstScrub,
                          "the crown died after tapping a button — focus was never reclaimed")
    }

    /// The same theft applies to a Toggle, which is why Bernoulli reclaims too.
    func testCrownStillWorksAfterFlippingTheBernoulliToggle() {
        let app = XCUIApplication()
        app.launchArguments += ["-otl.watch.lastTool", "bernoulli"]
        app.launch()

        let readout = any(app, "result.bernoulli")
        XCTAssertTrue(readout.waitForExistence(timeout: 30))

        let toggle = app.switches.firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 10), "the open/closed pipe toggle must exist")
        toggle.tap()
        let afterToggle = readout.readoutValue

        XCUIDevice.shared.rotateDigitalCrown(delta: 5)
        XCTAssertNotEqual(readout.readoutValue, afterToggle,
                          "the crown died after flipping the toggle")
    }
}

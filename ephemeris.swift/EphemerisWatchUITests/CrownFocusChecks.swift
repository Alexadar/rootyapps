import XCTest

/// The regression test for the watchOS crown-focus defect **that shipped in this app**.
///
/// ## The bug
///
/// `.digitalCrownRotation(…)` only delivers to the view that currently HOLDS FOCUS, and `Button` is
/// focusable by default. `.focusable()` alone is not enough. So on the wheel screen, tapping the
/// grain button (6h / 1d / 5d) — which is exactly what you press while scrubbing — moved focus off
/// the wheel and the Crown went dead. Nothing crashed, nothing looked wrong: the grain label even
/// changed as expected. Only the scrubbing stopped, which reads as "that button does nothing".
///
/// It reached build 6 and had to be recalled from review.
///
/// ## Why this is a test and not a manual check
///
/// I claimed the Crown could not be driven by XCUITest and that this needed a real wrist. That was
/// wrong. `XCUIDevice.rotateDigitalCrown(delta:)` has existed since Xcode 13 — in `XCUIAutomation`'s
/// `XCUIDevice.h` as `rotateDigitalCrownByDelta:`, gated on `TARGET_OS_WATCH`, surfaced to Swift by
/// apinotes. The interaction is fully scriptable; only *rendering* (whether a complication looks
/// right on a face) still needs eyes.
///
/// ## What the assertions read
///
/// The amber scrub date in the top bar. It is published only while `detents != 0`, so its *presence*
/// proves the Crown moved at all and its *value* proves it moved again. Note each "after" value is
/// read **after** the tap: changing the grain re-scales the offset and therefore changes the date on
/// its own, and comparing against a pre-tap value would let that spurious change pass for a working
/// Crown.
final class CrownFocusChecks: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    private func wheelApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["EPHEMERIS_SCREEN"] = "wheel"
        app.launchEnvironment["EPHEMERIS_DATE"] = pinnedInstant
        app.launchEnvironment["EPHEMERIS_LANG"] = "en"
        app.launch()
        return app
    }

    /// Precondition for everything below: the Crown scrubs at all.
    func testCrownScrubsTheChart() {
        let app = wheelApp()
        XCTAssertTrue(any(app, "watch.wheel").waitForExistence(timeout: 30),
                      "the wheel must publish an element to focus")

        XCTAssertFalse(any(app, "watch.scrubDate").exists,
                       "precondition: nothing is scrubbed at launch, so no date is shown")

        XCUIDevice.shared.rotateDigitalCrown(delta: 10)

        let date = any(app, "watch.scrubDate")
        XCTAssertTrue(date.waitForExistence(timeout: 10),
                      "turning the Crown must move the chart off 'now' and reveal the scrub date")
        XCTAssertFalse(date.text.isEmpty, "the scrub date must publish a readable value")
    }

    /// ⚠ THE REGRESSION. Scrub, tap the grain button, scrub again.
    func testCrownStillWorksAfterTappingTheGrainButton() {
        let app = wheelApp()
        XCTAssertTrue(any(app, "watch.wheel").waitForExistence(timeout: 30))

        // 1 — scrub away from now.
        XCUIDevice.shared.rotateDigitalCrown(delta: 10)
        let date = any(app, "watch.scrubDate")
        XCTAssertTrue(date.waitForExistence(timeout: 10),
                      "precondition: the Crown scrubs before any tap")

        // 2 — tap the grain button. This is the focus thief.
        let grain = any(app, "watch.grain")
        XCTAssertTrue(grain.waitForExistence(timeout: 10), "the grain button must be addressable")
        grain.tap()

        // 3 — read AFTER the tap. Changing the grain re-scales days-per-detent, so the date moves on
        //     its own here; anchoring on a pre-tap value would make step 4 pass for the wrong reason.
        let afterTap = any(app, "watch.scrubDate").text

        // 4 — scrub again. Before the fix this changed NOTHING: focus sat on the button.
        XCUIDevice.shared.rotateDigitalCrown(delta: 10)
        XCTAssertNotEqual(any(app, "watch.scrubDate").text, afterTap,
                          "THE BUG: the Crown is dead after tapping the grain button. Focus has to "
                          + "be reclaimed in the button's action (crownFocused = true), not merely "
                          + "declared once with .focusable() and an onAppear claim.")
    }

    /// The same defect by the other route — the reset button, which is the one you press to come back
    /// to now and therefore the one most likely to be pressed mid-scrub.
    func testCrownStillWorksAfterTappingReset() {
        let app = wheelApp()
        XCTAssertTrue(any(app, "watch.wheel").waitForExistence(timeout: 30))

        XCUIDevice.shared.rotateDigitalCrown(delta: 10)
        XCTAssertTrue(any(app, "watch.scrubDate").waitForExistence(timeout: 10),
                      "precondition: the Crown scrubs before any tap")

        let reset = any(app, "watch.reset")
        XCTAssertTrue(reset.waitForExistence(timeout: 10),
                      "the reset button appears only while scrubbed — so the scrub above worked")
        reset.tap()

        // Reset returns to now, which hides the date again. So the assertion is that scrubbing can
        // bring it BACK: if focus stayed on the button, it never reappears.
        XCTAssertFalse(any(app, "watch.scrubDate").waitForExistence(timeout: 3),
                       "reset must return the chart to now and hide the scrub date")

        XCUIDevice.shared.rotateDigitalCrown(delta: 10)
        XCTAssertTrue(any(app, "watch.scrubDate").waitForExistence(timeout: 10),
                      "THE BUG, second route: the Crown is dead after tapping reset. Focus must be "
                      + "reclaimed in that button's action too.")
    }
}

import XCTest

/// The regression test for the watchOS crown-focus defect.
///
/// ## The bug
///
/// `.digitalCrownRotation(…)` only delivers to the view that currently HOLDS FOCUS, and `Button`
/// is focusable by default. `.focusable()` alone is not enough. So on the Tides screen, tapping
/// **NOW** — which is precisely what you press after scrubbing — moved focus off the scroll view
/// and the crown went dead. Nothing crashed, nothing looked wrong: the day just stopped scrubbing,
/// and any action reading the scrub position kept re-applying a stale value.
///
/// ## Why this is a test and not a manual check
///
/// I claimed XCUITest could not drive the crown and that this had to be verified by hand. That was
/// wrong. `XCUIDevice.rotateDigitalCrown(delta:)` has existed since Xcode 13 — in
/// `XCUIAutomation`'s `XCUIDevice.h`, gated on `TARGET_OS_WATCH`, surfaced to Swift by apinotes
/// from `rotateDigitalCrownByDelta:`. The interaction is scriptable; only *rendering* (does a
/// complication look right on a face) still needs eyes.
///
/// Step 4 below is the whole point: before the fix, the second rotation changed nothing.
final class CrownFocusChecks: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    private func tidesApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-page", "tides"]
        app.launch()
        return app
    }

    /// The hero height readout — queried by identifier only, never by element type.
    private func hero(_ app: XCUIApplication) -> XCUIElement {
        any(app, "result.nowHeight")
    }

    func testCrownScrubsTheDay() {
        let app = tidesApp()
        let readout = hero(app)
        XCTAssertTrue(readout.waitForExistence(timeout: 30),
                      "the Tides hero readout must appear")

        let atNow = readout.text
        XCTAssertFalse(atNow.isEmpty, "the hero must publish a readable value")

        XCUIDevice.shared.rotateDigitalCrown(delta: 10)
        XCTAssertNotEqual(readout.text, atNow,
                          "turning the crown must move the readout across the station's day")
    }

    /// ⚠ THE REGRESSION. Scrub, tap NOW, scrub again.
    func testCrownStillWorksAfterTappingNOW() {
        let app = tidesApp()
        let readout = hero(app)
        XCTAssertTrue(readout.waitForExistence(timeout: 30))

        // 1 — establish the live reading.
        let atNow = readout.text

        // 2 — scrub away from it.
        XCUIDevice.shared.rotateDigitalCrown(delta: 10)
        let scrubbed = readout.text
        XCTAssertNotEqual(scrubbed, atNow, "precondition: the crown scrubs before any tap")

        // 3 — tap NOW to come back. This is the focus thief.
        let nowButton = any(app, "input.scrubReset")
        XCTAssertTrue(nowButton.waitForExistence(timeout: 10),
                      "the NOW button appears only while scrubbing — so step 2 must have worked")
        nowButton.tap()
        let returned = readout.text

        // 4 — scrub again. Before the fix this changed NOTHING: focus sat on the button.
        XCUIDevice.shared.rotateDigitalCrown(delta: 10)
        XCTAssertNotEqual(readout.text, returned,
                          "THE BUG: the crown is dead after tapping NOW. Focus must be reclaimed "
                          + "in the button's action (@FocusState + .focused), not merely declared "
                          + "with .focusable().")
    }

    /// The station picker is a sheet, which takes focus away with it — a different route to the
    /// same dead crown, and the reason focus is also reclaimed on dismiss.
    func testCrownStillWorksAfterOpeningAndClosingTheStationPicker() {
        let app = tidesApp()
        let readout = hero(app)
        XCTAssertTrue(readout.waitForExistence(timeout: 30))

        let station = any(app, "input.station")
        guard station.waitForExistence(timeout: 10) else {
            return XCTFail("the station line must be addressable to open the picker")
        }
        station.tap()

        let picker = any(app, "tool.stationPicker")
        XCTAssertTrue(picker.waitForExistence(timeout: 15), "the station picker should present")

        // Dismiss by RE-SELECTING the station already in use. `XCUIDevice.Button.back` does not
        // exist on watchOS, and choosing a different station would change the readout — which
        // would make the crown assertion below prove nothing.
        let sameStation = any(app, "input.station.9414290")
        XCTAssertTrue(sameStation.waitForExistence(timeout: 10),
                      "the picker's rows must be addressable per station")
        sameStation.tap()

        XCTAssertTrue(readout.waitForExistence(timeout: 15), "back on the Tides screen")
        let before = readout.text
        XCUIDevice.shared.rotateDigitalCrown(delta: 10)
        XCTAssertNotEqual(readout.text, before,
                          "the crown must survive a sheet: the picker takes focus with it, so it "
                          + "has to be reclaimed on dismiss")
    }
}

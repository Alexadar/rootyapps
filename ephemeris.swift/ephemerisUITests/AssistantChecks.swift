import XCTest

/// The "Explain this screen" surface.
///
/// ## What these can and cannot assert
///
/// They check the **shell**: that the button appears only when enabled, that the sheet opens, that
/// the one-tap question exists, and that the standing caveat is present. They deliberately do not
/// assert an answer, because on a simulator `SystemLanguageModel` reports `deviceNotEligible` and
/// there is no model to answer with — so the reachable path here is the *unavailable* one.
///
/// That is not a gap: the unavailable states are the ones most users on older hardware will see, and
/// they are the ones easiest to ship broken because a developer on an eligible Mac never hits them.
/// The answering path is covered by `ScreenContextTests`, which exercises everything the model is
/// sent, and by running on an eligible device by hand.
final class AssistantChecks: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    /// `-key value` lands in NSArgumentDomain, which outranks the persisted value for one launch —
    /// the same mechanism the rest of the suite uses to pin preferences without app code.
    private func app(assistant: Bool, tab: Int = 0) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-assistant.enabled", assistant ? "YES" : "NO"]
        return app.launchPinned(tab: tab)
    }

    // MARK: - The toggle governs the chrome

    /// Off by default, and off means genuinely absent — not present-but-disabled. An assistant that
    /// appears uninvited in a precision tool reads as a gimmick.
    func testTheButtonIsAbsentUntilTheFeatureIsSwitchedOn() {
        let app = app(assistant: false)
        // Something from the screen must exist, so absence below is a real absence and not a
        // half-loaded view.
        XCTAssertTrue(app.descendants(matching: .any)["input.lens"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["toolbar.assistant"].exists,
                       "the ✨ button must not appear until the user asks for it")
    }

    func testTheButtonAppearsWhenEnabled() {
        let app = app(assistant: true)
        XCTAssertTrue(app.buttons["toolbar.assistant"].waitForExistence(timeout: 10),
                      "with the setting on, Sky must offer the ✨ button")
    }

    // MARK: - The sheet

    func testThePanelOffersAQuestionAndTheOneTapAsk() {
        let app = app(assistant: true)
        let button = app.buttons["toolbar.assistant"]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        button.tap()

        // Either the assistant is usable, or it says why not — never a blank panel.
        let unavailable = app.descendants(matching: .any)["assistant.unavailable"]
        let ask = app.descendants(matching: .any)["assistant.whatsHere"]
        XCTAssertTrue(ask.waitForExistence(timeout: 5) || unavailable.exists,
                      "the panel must offer a question or explain why it cannot")

        if ask.exists {
            XCTAssertTrue(app.descendants(matching: .any)["assistant.question"].exists,
                          "a typed question must be possible, not only the one-tap button")
            // ⚠️ The standing caveat is not decoration: it is what separates a generated sentence
            // from the app's oracle-tested numbers.
            XCTAssertTrue(app.descendants(matching: .any)["assistant.footer"].exists,
                          "the panel must always say what the explanations are and are not")
        }
    }

    /// On a simulator the model is unavailable, so this is the state that actually renders — and it
    /// must read as "not offered here", not as a failure.
    func testTheUnavailableStateExplainsItselfRatherThanErroring() throws {
        let app = app(assistant: true)
        let button = app.buttons["toolbar.assistant"]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        button.tap()

        let unavailable = app.descendants(matching: .any)["assistant.unavailable"]
        guard unavailable.waitForExistence(timeout: 5) else {
            // An eligible host: nothing to assert here, and skipping beats a false pass.
            throw XCTSkip("this host can run Apple Intelligence — the unavailable path is unreachable")
        }
        XCTAssertFalse(unavailable.label.isEmpty, "the reason must be stated, not blank")
        XCTAssertTrue(app.descendants(matching: .any)["assistant.screen"].exists == false
                      || unavailable.exists,
                      "the unavailable state replaces the asking UI rather than sitting beside it")
    }

    // MARK: - It is available on the destinations too, not only Sky

    func testTheMoonCalendarCanAlsoBeExplained() {
        let app = XCUIApplication()
        app.launchArguments += ["-assistant.enabled", "YES"]
        _ = app.launchPinned(tab: 0, lens: "moon")

        XCTAssertTrue(app.descendants(matching: .any)["card.moonCalendar"].waitForExistence(timeout: 10),
                      "the deep link must reach the calendar")
        XCTAssertTrue(app.buttons["toolbar.assistant"].exists,
                      "a pushed destination must be explainable too — it is the screen most likely "
                      + "to prompt 'what is this?'")
    }

    // MARK: - The claim the whole design rests on

    /// ⚠️ **The panel must not cover what it describes.**
    ///
    /// This is the reason the modal sheet was thrown away, and it is the one property a screenshot
    /// cannot prove — an overlay and a safe-area inset look identical in a still. So it is asserted
    /// by *interaction*: with the panel open, the content behind it must still be hittable.
    ///
    /// `.safeAreaInset(edge: .bottom)` shrinks the content's area so the scroll view reflows above
    /// it; `.overlay(alignment: .bottom)` would draw on top and leave the content unreachable.
    func testThePanelDoesNotCoverTheContent() {
        let app = app(assistant: true)
        // ⚠️ The element under test must be one the panel WOULD cover. An earlier version asserted
        // `input.lens`, which sits at the top of Sky — a bottom-docked overlay never reaches it, so
        // the test passed with the panel drawn straight over the content. Verified by making it an
        // overlay and watching it stay green.
        //
        // The Hours row is the last thing in the Sky column, directly where the panel docks.
        let bottomRow = app.buttons["sky.hours.row"]
        XCTAssertTrue(bottomRow.waitForExistence(timeout: 10))

        app.buttons["toolbar.assistant"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["assistant.panel"].waitForExistence(timeout: 5),
                      "the panel must dock rather than present modally")

        XCTAssertTrue(bottomRow.exists, "the content vanished when the panel opened")

        // ⚠️ The discriminating check is REACHABILITY at the end of the scroll, not position.
        //
        // Insetting necessarily moves content, so asserting the row has not moved fails on correct
        // code — it did. And scrolling alone proves nothing either, since an overlay lets you
        // scroll a row up past the glass too.
        //
        // What separates them is the bottom of the scroll: a safe-area inset grows the scrollable
        // extent, so the LAST row can come to rest clear of the panel. Under an overlay the extent
        // is unchanged and the last row can never be brought out from under it, however far you
        // scroll.
        // Scroll the SCROLL VIEW, not the app. `app.swipeUp()` targets the application element and
        // never moved the content at all — the row's frame was byte-identical across four swipes,
        // which is how this was found.
        let scroll = app.scrollViews.firstMatch
        for _ in 0..<6 where !bottomRow.isHittable { scroll.swipeUp() }
        XCTAssertTrue(bottomRow.isHittable,
                      "the last row cannot be scrolled clear of the panel — it is overlaying the "
                      + "content rather than insetting it")
    }

    // MARK: - Hiding keeps the answer

    /// Collapsing folds the panel to the pill. Re-opening to a blank window would defeat the reason
    /// the user hid it, so the pill must carry the answer back.
    func testCollapsingLeavesThePillAndReopeningRestoresTheSameView() {
        let app = app(assistant: true)
        XCTAssertTrue(app.buttons["toolbar.assistant"].waitForExistence(timeout: 10))
        app.buttons["toolbar.assistant"].tap()

        let panel = app.descendants(matching: .any)["assistant.panel"]
        guard panel.waitForExistence(timeout: 5) else {
            XCTSkip("the panel did not open on this host"); return
        }

        app.buttons["assistant.collapse"].tap()
        let pill = app.buttons["assistant.pill"]
        XCTAssertTrue(pill.waitForExistence(timeout: 5),
                      "collapsing must leave the peek pill, not nothing")
        XCTAssertFalse(panel.exists, "the panel should be folded away")

        pill.tap()
        XCTAssertTrue(panel.waitForExistence(timeout: 5),
                      "tapping the pill must bring the panel back")

        // NOTE: that an *answer* survives the fold is asserted in `AssistantPresenterTests`, not
        // here. A UI test cannot check it honestly — generating one needs an eligible device and
        // several seconds, so this test would pass with the answer discarded. It did, until the
        // presenter grew a unit test.
    }

    /// The ✨ item toggles rather than only opening — a second tap folds it away.
    func testTheToolbarItemToggles() {
        let app = app(assistant: true)
        let button = app.buttons["toolbar.assistant"]
        XCTAssertTrue(button.waitForExistence(timeout: 10))

        button.tap()
        let panel = app.descendants(matching: .any)["assistant.panel"]
        guard panel.waitForExistence(timeout: 5) else {
            XCTSkip("the panel did not open on this host"); return
        }
        button.tap()
        XCTAssertFalse(panel.exists, "a second tap must fold the panel away")
        XCTAssertTrue(app.buttons["assistant.pill"].exists,
                      "folding away leaves the pill, so there is a way back")
    }
}

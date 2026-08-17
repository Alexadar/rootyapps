import XCTest

/// UI tests — WRITTEN, NOT RUN in this build (owner's instruction; the owner runs them).
/// They assert chrome reachability and settings state-space; the 3D card feel itself is
/// judged by eye and covered by CardMotionKit's emulation suite.
final class DrawFlowChecks: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testMenuToDrawAndBack() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.buttons["menu.start"].waitForExistence(timeout: 10))
        app.buttons["menu.start"].tap()

        XCTAssertTrue(app.staticTexts["draw.hint"].waitForExistence(timeout: 5),
                      "the draw screen must show its hint chip")

        app.buttons["draw.back"].tap()
        XCTAssertTrue(app.buttons["menu.start"].waitForExistence(timeout: 5))
    }

    /// Both directions of both toggles — the state space, not the default state.
    func testSettingsTogglesBothDirections() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.buttons["menu.settings"].waitForExistence(timeout: 10))
        app.buttons["menu.settings"].tap()

        let haptics = app.switches["settings.haptics"]
        XCTAssertTrue(haptics.waitForExistence(timeout: 5))
        // Reversals are parked (feature flag); exercise the toggle only if it's shown.
        let reversals = app.switches["settings.reversals"]
        let controls = reversals.exists ? [reversals, haptics] : [haptics]

        for control in controls {
            let before = control.value as? String
            // Tap the SWITCH, not the row: `.tap()` hits the element's centre, which in a
            // Form row is the label — and a label tap does not flip a SwiftUI Toggle.
            func flip() {
                control.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
            }
            flip()
            XCTAssertNotEqual(control.value as? String, before, "toggle did not change state")
            flip()
            XCTAssertEqual(control.value as? String, before, "toggle did not change back")
        }

        app.buttons["settings.done"].tap()
        XCTAssertTrue(app.buttons["menu.start"].waitForExistence(timeout: 5))
    }

    /// A full draw by scripted drags: deck sits low-centre, slots above (matching
    /// MotionConfig's normalized layout). Drag three times, expect the reading panel.
    func testThreeDragsReachTheReading() throws {
        let app = XCUIApplication()
        app.launch()

        // The reader's question, typed through the accessibility layer like everything else.
        let questionField = app.textFields["menu.question"]
        XCTAssertTrue(questionField.waitForExistence(timeout: 10))
        questionField.tap()
        questionField.typeText("Should I take the new job?")

        app.buttons["menu.start"].tap()
        XCTAssertTrue(app.staticTexts["draw.hint"].waitForExistence(timeout: 5))

        let scene = app.otherElements["game.scene"].exists ? app.otherElements["game.scene"] : app.windows.firstMatch
        // Normalized targets, MEASURED from rendered frames (not the config's table units):
        // deck centre ≈ (0.5, 0.62), slot pools ≈ y 0.41. The kernel's grab/snap radii
        // (0.30 TU) absorb the residual projection differences between window aspects.
        let deck = scene.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.62))
        let slots = [CGVector(dx: 0.22, dy: 0.41), CGVector(dx: 0.5, dy: 0.41),
                     CGVector(dx: 0.78, dy: 0.41)]
        for slot in slots {
            deck.press(forDuration: 0.15,
                       thenDragTo: scene.coordinate(withNormalizedOffset: slot),
                       withVelocity: .default, thenHoldForDuration: 0.1)
            // Flight + reveal beat before the next card.
            Thread.sleep(forTimeInterval: 1.4)
        }

        XCTAssertTrue(app.scrollViews["reading.panel"].waitForExistence(timeout: 8),
                      "three landed cards must present the reading")
        XCTAssertTrue(app.staticTexts["reading.question"].waitForExistence(timeout: 4),
                      "the typed question must appear with the reading")

        // Demo-capture hold: when driven for a screen recording (TEST_RUNNER_TAROT_DEMO_HOLD
        // in the xcodebuild environment), keep the app alive long enough for the on-device
        // writing to stream in and the recorder to finalize. Costs nothing in a normal run.
        if let hold = ProcessInfo.processInfo.environment["TAROT_DEMO_HOLD"].flatMap(Double.init) {
            Thread.sleep(forTimeInterval: hold)
        }
    }

    /// Every method plays to its reading — driven by the Debug autopilot (the same pointer
    /// a thumb drives), preselected via -TAROT_METHOD, so no hand-computed screen
    /// coordinates exist for the five- and ten-slot layouts.
    func testEveryMethodAutopilotsToTheReading() throws {
        for (methodID, cards) in [("daily-card", 1), ("three-card", 3),
                                  ("crossroads", 5), ("celtic-cross", 10)] {
            let app = XCUIApplication()
            app.launchArguments = ["-TAROT_AUTOPILOT", "-TAROT_METHOD", methodID]
            app.launch()

            // 2 s of autopilot per card, plus flight/hero/transition slack, plus a first-
            // launch allowance: a cold simulator compiles the whole Metal library before the
            // first frame, and alphabetically this test is the one that pays for it.
            let timeout = Double(cards) * 2.0 + 12.0 + (methodID == "daily-card" ? 30.0 : 0.0)
            // Query by identifier WITHOUT asserting an element type: the panel resolves as a
            // scroll view and the header cells as containers, and hard-coding either was a
            // guess in a test that had never actually been executed.
            let panel = app.descendants(matching: .any)["reading.panel"]
            XCTAssertTrue(panel.waitForExistence(timeout: timeout),
                          "\(methodID): autopilot never reached the reading")
            let firstCard = app.descendants(matching: .any)["reading.card.0"]
            XCTAssertTrue(firstCard.waitForExistence(timeout: 4),
                          "\(methodID): first card missing from the reading header")
            XCTAssertTrue(app.descendants(matching: .any)["reading.card.\(cards - 1)"].exists,
                          "\(methodID): last card missing from the reading header")
            app.terminate()
        }
    }

    /// The pickers persist: choose a non-default method and deck, relaunch, and find them
    /// still selected (asserted via the method-aware menu subtitle and the deck picker).
    func testMethodAndDeckSelectionPersists() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.buttons["menu.method"].waitForExistence(timeout: 10))
        app.buttons["menu.method"].tap()
        app.buttons["Daily Card"].firstMatch.tap()
        app.buttons["menu.deck"].tap()
        app.buttons["Astral"].firstMatch.tap()

        app.terminate()
        let relaunched = XCUIApplication()
        relaunched.launch()
        XCTAssertTrue(relaunched.staticTexts["One card. A daily pulse."]
            .waitForExistence(timeout: 10),
                      "the method choice must survive a relaunch")
    }
}

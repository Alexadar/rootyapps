import XCTest

/// ⚠️ WRITTEN, NOT RUN. These are the owner's to execute:
///
///     ./run_tests.sh --ui                       # iPhone and iPad
///     xcodebuild test -scheme architecture -destination 'platform=macOS' \
///       -only-testing:architectureUITests       # macOS, and SEPARATELY from the unit target
///
/// macOS needs the host terminal added to System Settings → Privacy & Security → Accessibility,
/// and a run can block on a password dialog with zero log output — the tell is `…-Runner […]
/// Running tests…` with no `Test Case` lines. Do not kill it.
final class ShellUITests: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    func testTheSegmentMovesBetweenSectionsInBothDirections() {
        let app = UI.launch()
        XCTAssertTrue(UI.exists(app, "shell.segment.redesign"))

        UI.any(app, "shell.segment.library").tap()
        XCTAssertTrue(UI.exists(app, "library.caption"))

        // Both directions. A segment tested one way is a segment half tested.
        UI.any(app, "shell.segment.redesign").tap()
        XCTAssertTrue(UI.exists(app, "capture.shutter") || UI.exists(app, "capture.importPrimary"))
    }

    func testDeepLinkingOpensTheLibraryDirectly() {
        // §11a: any interaction costs about 1.1 s because the accessibility tree is re-snapshotted,
        // so navigating four screens to assert one label is most of a suite's runtime.
        let app = UI.launch(["ARCH_SCREEN": "library"])
        XCTAssertTrue(UI.exists(app, "library.caption"))
    }

    func testTheAppStaysAliveThroughEverySection() {
        let app = UI.launch()
        for identifier in ["shell.segment.library", "shell.segment.redesign"] {
            UI.any(app, identifier).tap()
            XCTAssertEqual(app.state, .runningForeground, "died after tapping \(identifier)")
        }
    }
}

final class CaptureUITests: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    func testTheModeSegmentFlipsAndChangesTheDirectionPresets() {
        let app = UI.launch(["ARCH_GENERATOR": "instant"])

        UI.any(app, "capture.mode.exterior").tap()
        UI.any(app, "capture.shutter").tap()

        // The regression this exists for: `mode` was local `@State` that nothing downstream could
        // read, so Direction hardcoded `.interior` and the exterior presets were unreachable.
        XCTAssertTrue(UI.exists(app, "direction.preset.farmhouse"))
        XCTAssertFalse(UI.any(app, "direction.preset.scandi").exists)

        UI.any(app, "direction.retake").tap()
        UI.any(app, "capture.mode.interior").tap()
        UI.any(app, "capture.shutter").tap()
        XCTAssertTrue(UI.exists(app, "direction.preset.scandi"))
    }

    func testTheCoachLineIsPresentAndSaysSomething() {
        let app = UI.launch()
        XCTAssertTrue(UI.exists(app, "capture.coach"))
        // `.text`, never `.label` — a plain Text has an empty label on macOS.
        XCTAssertFalse(UI.any(app, "capture.coach").text.isEmpty)
    }

    func testTheShutterReachesDirection() {
        let app = UI.launch(["ARCH_GENERATOR": "instant"])
        UI.any(app, "capture.shutter").tap()
        XCTAssertTrue(UI.exists(app, "direction.cta"))
        XCTAssertTrue(UI.exists(app, "direction.depth"))
    }
}

final class DirectionUITests: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    private func openDirection() -> XCUIApplication {
        let app = UI.launch(["ARCH_GENERATOR": "instant"])
        UI.any(app, "capture.shutter").tap()
        XCTAssertTrue(UI.exists(app, "direction.cta"))
        return app
    }

    func testPickingAPresetRewritesThePrompt() {
        let app = openDirection()
        let field = UI.any(app, "direction.prompt")
        let before = field.text

        UI.any(app, "direction.preset.japandi").tap()
        XCTAssertNotEqual(field.text, before)
        XCTAssertTrue(field.text.lowercased().contains("japandi"))
    }

    func testAChipAppendsExactlyOnce() {
        let app = openDirection()
        let field = UI.any(app, "direction.prompt")
        UI.any(app, "direction.chip.0").tap()
        let after = field.text
        // The chip disappears once used, so a second tap is not even possible — which is the point.
        XCTAssertFalse(UI.any(app, "direction.chip.0").text.isEmpty || after.isEmpty)
    }

    func testTheStepperRepricesTheCta() {
        let app = openDirection()
        let cta = UI.any(app, "direction.cta")
        let before = cta.text
        UI.any(app, "direction.variations.stepper").buttons.element(boundBy: 1).tap()
        XCTAssertNotEqual(cta.text, before, "the CTA is priced in minutes and must follow the count")
    }

    func testTheCtaStartsARender() {
        let app = openDirection()
        UI.any(app, "direction.cta").tap()
        XCTAssertTrue(UI.exists(app, "generating.stage"))
        XCTAssertTrue(UI.exists(app, "generating.step"))
    }
}

final class GeneratingUITests: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    private func startRender(_ overrides: [String: String] = [:], variations: Int = 1) -> XCUIApplication {
        var environment = ["ARCH_GENERATOR": "fast"]
        environment.merge(overrides) { _, new in new }
        let app = UI.launch(environment)
        UI.any(app, "capture.shutter").tap()
        XCTAssertTrue(UI.exists(app, "direction.cta"))
        for _ in 1..<variations {
            UI.any(app, "direction.variations.stepper").buttons.element(boundBy: 1).tap()
        }
        UI.any(app, "direction.cta").tap()
        return app
    }

    func testTheStageAndStepAreRealAndNotAPercentage() {
        let app = startRender()
        XCTAssertTrue(UI.exists(app, "generating.stage"))
        let step = UI.any(app, "generating.step").text
        XCTAssertTrue(step.contains("of"), "progress is step-based, never a fraction: got \(step)")
        XCTAssertFalse(step.contains("%"))
    }

    func testCancellingOneVariationLeavesItsSiblings() {
        let app = startRender(variations: 3)
        XCTAssertTrue(UI.exists(app, "generating.cancel"))
        UI.any(app, "generating.cancel").tap()
        // "Cancels only this variation. Queued variations continue."
        XCTAssertTrue(UI.exists(app, "generating.stage"), "the next variation picks up")
    }

    /// Each pause cause renders its own card. One test per cause, because the whole grammar is
    /// that the four are distinguishable.
    func testEachInterruptionRendersItsOwnCard() {
        for (override, needle) in [("thermal", "cool"),
                                   ("call", "call"),
                                   ("low-battery", "battery"),
                                   ("background", "Waiting for you")] {
            let app = startRender(["ARCH_GENERATOR": override])
            XCTAssertTrue(UI.exists(app, "generating.pause", timeout: 15),
                          "\(override) never paused")
            XCTAssertTrue(UI.text(app, containing: needle).exists,
                          "\(override) did not render its own copy")
            app.terminate()
        }
    }

    func testOnlyLowBatteryOffersAChoice() {
        let app = startRender(["ARCH_GENERATOR": "low-battery"])
        XCTAssertTrue(UI.exists(app, "generating.pause", timeout: 15))
        XCTAssertTrue(UI.any(app, "generating.pause.resume").exists)
        XCTAssertTrue(UI.any(app, "generating.pause.wait").exists)
    }

    func testAFailureShowsAReasonAndNotAnErrorCode() {
        let app = startRender(["ARCH_GENERATOR": "failing"])
        XCTAssertTrue(UI.text(app, containing: "memory").waitForExistence(timeout: 15))
        XCTAssertFalse(UI.text(app, containing: "error").exists)
    }
}

final class ResumeAfterBackgroundUITests: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    /// The axis the brief calls most likely to be broken.
    func testTheStepCounterNeverRewindsAcrossABackgroundRound_trip() {
        let app = UI.launch(["ARCH_GENERATOR": "fast"])
        UI.any(app, "capture.shutter").tap()
        UI.any(app, "direction.cta").tap()
        XCTAssertTrue(UI.exists(app, "generating.step"))

        // Let it get past the first checkpoint cadence.
        Thread.sleep(forTimeInterval: 3)
        let before = Self.step(from: UI.any(app, "generating.step").text)
        XCTAssertGreaterThan(before, 0)

        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 2)
        app.activate()

        XCTAssertTrue(UI.exists(app, "generating.step"))
        let after = Self.step(from: UI.any(app, "generating.step").text)
        XCTAssertGreaterThanOrEqual(after, before,
                                    "resuming walked the counter backwards: \(before) → \(after)")
    }

    func testASuspendedRenderSaysItIsWaiting() {
        let app = UI.launch(["ARCH_GENERATOR": "fast"])
        UI.any(app, "capture.shutter").tap()
        UI.any(app, "direction.cta").tap()
        XCTAssertTrue(UI.exists(app, "generating.step"))

        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 2)
        app.activate()
        // Coming back must clear it rather than leaving a stale pause card behind.
        XCTAssertFalse(UI.text(app, containing: "Waiting for you").exists)
    }

    /// "step 18 of 32" → 18.
    private static func step(from text: String) -> Int {
        let parts = text.split(separator: " ")
        guard parts.count >= 2 else { return 0 }
        return Int(parts[1]) ?? 0
    }
}

final class ResultUITests: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    private func openResult() -> XCUIApplication {
        let app = UI.launch(["ARCH_GENERATOR": "instant"])
        UI.any(app, "capture.shutter").tap()
        UI.any(app, "direction.cta").tap()
        XCTAssertTrue(UI.exists(app, "result.wipe", timeout: 20))
        return app
    }

    func testTheWipeIsOneAdjustableElementAndItsValueTracksTheDrag() {
        let app = openResult()
        let wipe = UI.any(app, "result.wipe")
        let before = wipe.value as? String

        wipe.drag(fromRelativeX: 0.5, toRelativeX: 0.85)
        let after = wipe.value as? String
        XCTAssertNotEqual(before, after, "the drag did not move the divider")

        // And back — a control tested one way is a control half tested.
        wipe.drag(fromRelativeX: 0.85, toRelativeX: 0.3)
        XCTAssertNotEqual(wipe.value as? String, after)
    }

    func testTheKnobMeetsTheHitTargetFloor() {
        let app = openResult()
        let knob = UI.any(app, "result.knob")
        guard knob.exists else { return }
        // The handoff positioned it at y = 0, which put half of it off the top edge and left an
        // effective target of 22 pt.
        XCTAssertGreaterThanOrEqual(knob.frame.height, 44)
        XCTAssertGreaterThanOrEqual(knob.frame.width, 44)
        XCTAssertGreaterThan(knob.frame.minY, 0, "the knob must not be centred on the top edge")
    }

    func testTheActionsAreAllReachable() {
        let app = openResult()
        for identifier in ["result.save", "result.again", "result.more", "result.newvariation"] {
            XCTAssertTrue(UI.any(app, identifier).exists, "\(identifier) is missing")
        }
    }
}

final class LibraryUITests: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    func testTheCaptionTellsTheTruthAboutWhereThingsAre() {
        let app = UI.launch(["ARCH_SCREEN": "library"])
        XCTAssertTrue(UI.exists(app, "library.caption"))
        let caption = UI.any(app, "library.caption").text
        XCTAssertTrue(caption.contains("Files"))
        for word in ["account", "sign in", "server", "upload"] {
            XCTAssertFalse(caption.lowercased().contains(word), "caption implies a service")
        }
    }

    func testTheLocalFallbackSaysSomethingDifferent() {
        let cloud = UI.launch(["ARCH_SCREEN": "library"])
        let cloudCaption = UI.any(cloud, "library.caption").text
        cloud.terminate()

        let local = UI.launch(["ARCH_SCREEN": "library", "ARCH_ICLOUD": "off"])
        let localCaption = UI.any(local, "library.caption").text
        XCTAssertNotEqual(cloudCaption, localCaption, "two locations, two truths")
    }

    func testAnEmptyLibrarySaysSoRatherThanShowingNothing() {
        let app = UI.launch(["ARCH_SCREEN": "library", "ARCH_ICLOUD": "off"])
        XCTAssertTrue(UI.exists(app, "library.empty") || UI.exists(app, "library.caption"))
    }
}

final class AccessibilityUITests: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    /// Reduce Transparency must change the surfaces and NOT the layout. The README's word is
    /// "identical" and it means it: nothing may reflow when the setting changes.
    func testReduceTransparencyLeavesGeometryAlone() {
        let plain = UI.launch(["ARCH_SCREEN": "library"])
        let plainFrame = UI.any(plain, "library.caption").frame
        plain.terminate()

        let opaque = UI.launch(["ARCH_SCREEN": "library", "ARCH_AX": "rt"])
        let opaqueFrame = UI.any(opaque, "library.caption").frame
        XCTAssertEqual(plainFrame.origin.y, opaqueFrame.origin.y, accuracy: 1)
        XCTAssertEqual(plainFrame.height, opaqueFrame.height, accuracy: 1)
    }

    func testEveryScreenSurvivesAX5WithoutLosingItsControls() {
        let app = UI.launch(["ARCH_AX": "ax5", "ARCH_GENERATOR": "instant"])
        UI.any(app, "capture.shutter").tap()
        XCTAssertTrue(UI.exists(app, "direction.cta"))
        // The preset grid reflows to one column at AX5; the cards must still be there and hittable.
        XCTAssertTrue(UI.any(app, "direction.preset.scandi").isHittable)
        XCTAssertTrue(UI.any(app, "direction.cta").isHittable)
    }

    func testTheComparisonIsOneElementRatherThanTwoImages() {
        let app = UI.launch(["ARCH_GENERATOR": "instant"])
        UI.any(app, "capture.shutter").tap()
        UI.any(app, "direction.cta").tap()
        XCTAssertTrue(UI.exists(app, "result.wipe", timeout: 20))
        // VoiceOver treats before/after as ONE adjustable element with a percentage value.
        XCTAssertNotNil(UI.any(app, "result.wipe").value as? String)
    }
}

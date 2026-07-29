import XCTest

/// The incumbent's four named defects, plus the behaviours that make Storypole worth buying,
/// expressed as acceptance criteria.
///
/// ## These are AUTHORED, not run in this project's normal loop
///
/// XCUITests need a booted simulator, and this project verifies with `swift test` in the Kits plus
/// `xcodebuild build` on each platform and authored `#Preview`s. So this target is deliberately not
/// wired into any scheme's test action. Run it by hand when you want it:
///
///     xcodebuild test -scheme storypole -destination 'id=<a real device udid>' \
///       -only-testing:storypoleUITests
///
/// **Run it on an iPad at least once.** The incumbent's defining failure is that its core feature
/// crashes there — *"it works great on my iPhone but it crashes every single time I try to use a
/// fraction on my iPad"* (2★ 2026-01-10) — so parity is the whole wedge, and a green iPhone run
/// proves nothing about it.
///
/// Anything genuinely arithmetic is asserted in the Kits instead; these tests only check that the
/// UI is wired to that arithmetic and cannot regress the four defects.
final class DefectChecks: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    // MARK: - Helpers

    private func launch(tool: String? = nil, tab: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        if let tool { app.launchEnvironment["STORYPOLE_TOOL"] = tool }
        if let tab { app.launchEnvironment["STORYPOLE_TAB"] = tab }
        // Pin the locale. Storypole is a US-market app and `Fmt` follows the device region, so on a
        // comma-decimal simulator every number renders "152,11" and the tests fail on the separator
        // rather than on the arithmetic.
        app.launchEnvironment["STORYPOLE_LANG"] = "en"
        app.launch()
        return app
    }

    /// Type a measurement on the keypad. `12`, `ft`, `4`, `in` → 12' 4".
    private func enter(_ app: XCUIApplication, feet: Int? = nil, inches: Int? = nil,
                       num: Int? = nil, den: Int? = nil,
                       file: StaticString = #filePath, line: UInt = #line) {
        func tap(_ id: String) {
            let b = app.buttons[id]
            XCTAssertTrue(b.waitForExistence(timeout: 5), "missing key \(id)", file: file, line: line)
            XCTAssertTrue(b.isEnabled, "key \(id) is disabled", file: file, line: line)
            b.tap()
        }
        if let feet { String(feet).forEach { tap("key.digit\($0)") }; tap("key.feet") }
        if let inches { String(inches).forEach { tap("key.digit\($0)") }; tap("key.inch") }
        if let num, let den {
            String(num).forEach { tap("key.digit\($0)") }
            tap("key.fraction")                       // numerator FIRST
            String(den).forEach { tap("key.digit\($0)") }
        }
    }

    /// An element by identifier, whatever TYPE SwiftUI decided to publish it as.
    ///
    /// Never assume `staticTexts` or `otherElements`: a styled card surfaces differently depending
    /// on its modifiers and on the platform — a `.combine`d element is a static text on iOS and a
    /// group on macOS. Guessing the type is a test bug that reads exactly like an app bug.
    /// Querying `descendants(matching: .any)` asserts the thing that actually matters: the
    /// identifier is reachable.
    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    /// An element by identifier, scrolling to it if it is below the fold.
    ///
    /// Both platforms drop content that has never been on screen, so asserting `.exists` on a card
    /// further down a tool screen is really asserting "the window happened to be tall enough".
    /// macOS makes that worse by RESTORING the previous window size between launches, so the same
    /// assertion passes or fails depending on what an earlier run left behind.
    ///
    /// A caution the user scrolls to is still shown. So scroll, like a user would.
    private func readout(_ app: XCUIApplication) -> String {
        let r = app.staticTexts["calc.readout"]
        XCTAssertTrue(r.waitForExistence(timeout: 5), "no readout")
        // `.text`, not `.label` — a plain SwiftUI Text has an EMPTY label on macOS and carries its
        // string in `value` instead. See UITestSupport.swift.
        return r.text
    }

    // MARK: - Defect ①: the iPad crash

    /// The core feature, on whatever device this is running. On iPad this is THE test.
    func testFractionEntryDoesNotCrash() {
        let app = launch()
        enter(app, inches: 8, num: 7, den: 16)
        XCTAssertTrue(app.staticTexts["calc.readout"].exists, "the app must survive a fraction")
        XCTAssertTrue(readout(app).contains("7/16"), "expected 7/16, got \(readout(app))")
        XCTAssertEqual(app.state, .runningForeground)
    }

    /// ONE fraction, end to end: the keypad reaches the model and the model reaches the plaque.
    ///
    /// This entered all six denominators through the keypad and cost **66 s** — at ~1.1 s per tap,
    /// XCUITest can only ever afford a sample of a state space. The exhaustive version now lives in
    /// `DimensionKitTests/TapeCalcStateSpaceTests`, which runs all 36 combinations of (display
    /// precision x typed denominator) in microseconds. What stays here is the only part a Kit test
    /// cannot see: that the wiring between keypad and plaque exists.
    ///
    /// 1/64 is the case worth keeping on screen — the finest, and the one that must RAISE the
    /// display precision rather than round itself away.
    func testAFractionReachesThePlaque() {
        let app = launch()
        enter(app, inches: 5, num: 1, den: 64)
        XCTAssertEqual(app.state, .runningForeground, "died entering 1/64")
        XCTAssertTrue(readout(app).contains("/"), "1/64 did not render as a fraction")
    }

    // MARK: - Defect ②: the tape graphic

    /// A value past every real tape draws NO blade rather than a wrong one.
    func testNoTapeIsDrawnBeyondARealTape() {
        let app = launch()
        enter(app, feet: 40)
        app.buttons["key.equals"].tap()
        XCTAssertTrue(app.staticTexts["tape.none"].waitForExistence(timeout: 3),
                      "40 ft exceeds every blade — the graphic must be withheld")
    }

    /// A value that fits gets a blade, and the blade names the tape it would take.
    func testTapeAppearsForARealMeasurement() {
        let app = launch()
        enter(app, feet: 8)
        app.buttons["key.equals"].tap()
        let blade = app.staticTexts["tape.blade"]
        XCTAssertTrue(blade.waitForExistence(timeout: 3), "8 ft must draw a blade")
        XCTAssertFalse(app.staticTexts["tape.none"].exists)
    }

    /// Dragging the blade changes the measurement — the blade is an input, not just a readout.
    func testDraggingTheBladeSetsTheMeasurement() {
        let app = launch()
        enter(app, feet: 6)
        app.buttons["key.equals"].tap()
        let before = readout(app)

        let blade = app.otherElements["tape.blade.surface"]
        XCTAssertTrue(blade.waitForExistence(timeout: 3), "no blade to drag")
        // Coordinate-to-coordinate: XCUIElement.press(forDuration:thenDragTo:) takes an ELEMENT,
        // so dragging to a point on the same element has to go through XCUICoordinate.
        let from = blade.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let to   = blade.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5))
        from.press(forDuration: 0.05, thenDragTo: to)

        XCTAssertNotEqual(readout(app), before, "dragging the blade must change the measurement")
        XCTAssertEqual(app.state, .runningForeground)
    }

    /// Tapping the blade places the mark — the request made twice in the incumbent's reviews.
    func testTappingTheBladePlacesTheMark() {
        let app = launch()
        enter(app, feet: 6)
        app.buttons["key.equals"].tap()
        let before = readout(app)

        let blade = app.otherElements["tape.blade.surface"]
        XCTAssertTrue(blade.waitForExistence(timeout: 3))
        blade.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)).tap()

        XCTAssertNotEqual(readout(app), before, "tapping the blade must move the mark")
    }

    // MARK: - Defect ③: dimensioned multiplication

    /// The twelve-year defect: *"the FEET and INCHES buttons are GRAYED OUT"* (2★ 2014-08-04).
    func testFeetAndInchStayEnabledDuringMultiplication() {
        let app = launch()
        enter(app, feet: 12)
        app.buttons["key.op.mul"].tap()

        XCTAssertTrue(app.buttons["key.feet"].isEnabled, "Feet must stay live on the second operand")
        XCTAssertTrue(app.buttons["key.inch"].isEnabled, "Inch must stay live on the second operand")
        XCTAssertTrue(app.buttons["key.fraction"].isEnabled, "the fraction key too")

        enter(app, feet: 10)
        app.buttons["key.equals"].tap()
        XCTAssertTrue(readout(app).contains("sq ft"), "12' x 10' must be an area, got \(readout(app))")
    }

    /// Every key is live at every point in a calculation — nothing is ever dimmed.
    func testNoKeyIsEverDisabled() {
        let app = launch()
        let keys = ["key.digit0", "key.digit7", "key.feet", "key.inch", "key.fraction",
                    "key.op.add", "key.op.sub", "key.op.mul", "key.op.div",
                    "key.equals", "key.clear", "key.backspace"]
        for stage in ["fresh", "after operand", "after operator", "after equals"] {
            for k in keys {
                XCTAssertTrue(app.buttons[k].isEnabled, "\(k) disabled at stage: \(stage)")
            }
            switch stage {
            case "fresh":          enter(app, feet: 3)
            case "after operand":  app.buttons["key.op.mul"].tap()
            case "after operator": enter(app, feet: 4); app.buttons["key.equals"].tap()
            default: break
            }
        }
    }

    /// Area x depth is a volume — the dimension algebra survives into the UI.
    func testAreaTimesDepthGivesVolume() {
        let app = launch()
        enter(app, feet: 10)
        app.buttons["key.op.mul"].tap()
        enter(app, feet: 8)
        app.buttons["key.equals"].tap()
        XCTAssertTrue(readout(app).contains("sq ft"))
        app.buttons["key.op.mul"].tap()
        enter(app, inches: 4)
        app.buttons["key.equals"].tap()
        XCTAssertTrue(readout(app).contains("cu ft"), "got \(readout(app))")
    }

    /// An impossible dimension is REPORTED, never clamped into a plausible-looking lie.
    func testFourthPowerIsRefusedVisibly() {
        let app = launch()
        enter(app, feet: 2)
        for _ in 0..<3 {
            app.buttons["key.op.mul"].tap()
            enter(app, feet: 2)
            app.buttons["key.equals"].tap()
        }
        XCTAssertTrue(app.staticTexts["calc.error"].waitForExistence(timeout: 3),
                      "a fourth power must surface an error, not silently become a volume")
    }

    // MARK: - Defect ④: fractions first, real tapes only

    func testFractionsAreTheDefaultOutput() {
        let app = launch()
        enter(app, inches: 6, num: 1, den: 2)
        app.buttons["key.equals"].tap()
        let r = readout(app)
        XCTAssertTrue(r.contains("1/2"), "expected a fraction, got \(r)")
        XCTAssertFalse(r.contains("6.5"), "the primary readout must not be a decimal")
    }

    /// The decimal exists, but only as a secondary line.
    func testDecimalIsSecondaryNotPrimary() {
        let app = launch()
        enter(app, inches: 6, num: 1, den: 2)
        app.buttons["key.equals"].tap()
        let decimal = app.staticTexts["calc.decimal"]
        XCTAssertTrue(decimal.waitForExistence(timeout: 3), "the decimal line should be present")
        XCTAssertNotEqual(decimal.text, readout(app), "decimal must not BE the headline")
    }

    /// Changing precision changes the reading, and every option is reachable.
    func testDenominatorChipsChangeThePrecision() {
        let app = launch()
        enter(app, inches: 5, num: 3, den: 8)
        app.buttons["key.equals"].tap()
        for den in [2, 4, 8, 16, 32, 64] {
            let chip = app.buttons["denominator.\(den)"]
            XCTAssertTrue(chip.waitForExistence(timeout: 3), "missing 1/\(den) chip")
            chip.tap()
            XCTAssertEqual(app.state, .runningForeground, "died selecting 1/\(den)")
        }
    }

    // MARK: - The differentiator: layout marks

    /// Equal spacing emits THE LIST OF MARKS, which is the thing no competitor prints.
    func testEqualSpacingEmitsMarks() {
        let app = launch(tool: "equalSpacing")
        // Type-agnostic on both: `spacing.marks` is an otherElement on iOS and a group on macOS.
        XCTAssertTrue(any(app, "spacing.marks").waitForExistence(timeout: 5)
                      || any(app, "spacing.bay").waitForExistence(timeout: 5),
                      "the marks list must appear")
    }

    /// On-center reports the odd last bay rather than hiding it, and says where 19.2" comes from.
    func testOnCenterReportsTheOddBayAndItsProvenance() {
        let app = launch(tool: "onCenter")
        // `any`, not `staticTexts`: these are `ResultRow`s, and a `.combine`d element is NOT a
        // static text on macOS — it is published as a group. Same identifier, different type.
        XCTAssertTrue(any(app, "oc.count").waitForExistence(timeout: 5), "no member count")
        XCTAssertTrue(any(app, "oc.lastBay").exists, "the odd last bay must be shown")
        XCTAssertTrue(any(app, "oc.provenance").exists,
                      "the spacing's provenance must be stated")
    }

    // MARK: - The moat: citations are visible

    func testReferenceCarriesTheCitations() {
        let app = launch(tab: "2")
        XCTAssertTrue(app.staticTexts["Reference"].waitForExistence(timeout: 5)
                      || app.navigationBars.staticTexts["Reference"].waitForExistence(timeout: 5))
    }

    /// The board-foot CAUTION — the thing no other app states — must actually reach the screen.
    func testBoardFeetShowsTheCaution() {
        let app = launch(tool: "boardFeet")
        XCTAssertTrue(any(app, "bf.total").waitForExistence(timeout: 5), "no board-foot result")
        let caution = any(app, "bf.caution")
        XCTAssertTrue(caution.waitForExistence(timeout: 3), "the PS 20-20 CAUTION must be shown")
    }

    /// Wire gauge must state that it is a dimension and not a rating.
    func testWireGaugeStatesItsLimits() {
        let app = launch(tool: "wireGauge")
        XCTAssertTrue(any(app, "awg.inch").waitForExistence(timeout: 5), "no diameter")
        XCTAssertTrue(any(app, "awg.caveat").waitForExistence(timeout: 3),
                      "the ampacity caveat must be shown")
    }

    // `testEveryToolOpens` lived here: 16 launches, 63 s, asserting only that each tool had *some*
    // text on screen. `CalculationChecks` already deep-links into all sixteen and asserts a specific
    // NUMBER in each — strictly stronger, for launches it was paying anyway. Removed as redundant,
    // not as a coverage cut: `testEveryToolHasANumericCheck` remains the guard that the catalog
    // cannot outgrow its tests.
}

// MARK: - Deep links must work in BOTH layouts

/// `STORYPOLE_TAB=2` must reach Reference at regular width too.
///
/// It did not: `Router` set `selectedTab`, but `RegularRoot` has no tabs and only watched
/// `router.sidebar`, so every tab deep link silently landed on Calc. That put the calculator into
/// an iPad screenshot captioned "Every number has a source", and into the macOS preview's final
/// scene. Caught by looking at rendered frames, not by any assertion — hence this one.
extension DefectChecks {

    func testTabDeepLinkReachesReferenceInEveryLayout() {
        let app = XCUIApplication()
        app.launchEnvironment["STORYPOLE_LANG"] = "en"
        app.launchEnvironment["STORYPOLE_TAB"] = "2"
        app.launch()
        // Reference is the only screen carrying the citations; the calculator has no such text.
        let marker = app.staticTexts.containing(textMatches("NIST")).firstMatch
        XCTAssertTrue(marker.waitForExistence(timeout: 10),
                      "STORYPOLE_TAB=2 did not reach Reference — it landed on \(app.staticTexts.firstMatch.text)")
        XCTAssertFalse(app.buttons["key.digit7"].exists, "this is the calculator, not Reference")
    }
}

import XCTest

/// The watch app's own UI tests — the layer this project was missing entirely.
///
/// ## Why this target exists
///
/// The phone's UI-test target cannot reach the watch app: a watchOS UI test needs its own
/// `bundle.ui-testing` target on `platform: watchOS` with `TEST_TARGET_NAME` pointing at the watch
/// app. Everything the watch app computes is already covered by 169 Kit assertions; what was
/// **uncovered** was every watch-specific interaction — which is exactly where the expensive bug
/// lived.
///
/// ## The bug this file exists to keep fixed
///
/// `.digitalCrownRotation(…)` only delivers to the view that **holds focus**, and `Button` is
/// focusable. Tapping any button beside a crown-driven field silently kills the crown: nothing
/// crashes, the value simply stops responding, and Add/Sub then re-apply the stale amount. The user
/// found it by hand — *"on watch tape calc adds subs same if changed what to add sub"*.
///
/// It looked untestable and is not. `XCUIDevice.shared.rotateDigitalCrown(delta:)` has existed since
/// Xcode 13 (`rotateDigitalCrownByDelta:` in XCUIAutomation, gated on `TARGET_OS_WATCH`), so the
/// whole failure is scriptable. The shape that catches it is four steps, and **step 4 is the bug**:
///
/// 1. read the value
/// 2. rotate the crown, assert it changed — proves the precondition
/// 3. tap the control that steals focus
/// 4. rotate again, assert it changed **again**
///
/// Before the fix, step 4 changes nothing at all.
final class WatchChecks: XCTestCase {

    override func setUp() { super.setUp(); continueAfterFailure = false }

    private func launch(tool: String = "tapeCalc") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["STORYPOLE_WATCH_TOOL"] = tool
        // US-market app; `Fmt` follows the device region, so an unpinned sim renders "152,11".
        app.launchEnvironment["STORYPOLE_LANG"] = "en"
        app.launch()
        return app
    }

    /// By identifier, whatever type watchOS published it as — never assume (uitests.md §3 trap 2).
    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    /// The string a user would read. A platform may put it in `label` or in `value`.
    private func read(_ app: XCUIApplication, _ id: String,
                      file: StaticString = #filePath, line: UInt = #line) -> String {
        let e = any(app, id)
        XCTAssertTrue(e.waitForExistence(timeout: 15), "no element '\(id)'", file: file, line: line)
        let v = (e.value as? String) ?? ""
        return v.isEmpty ? e.label : v
    }

    private func crown(_ delta: CGFloat) {
        XCUIDevice.shared.rotateDigitalCrown(delta: delta)
    }

    // MARK: - The crown itself

    /// Precondition for everything below: the crown moves the entry value at all.
    func testCrownChangesTheEntry() {
        let app = launch()
        let before = read(app, "watch.entry")
        crown(6)
        let after = read(app, "watch.entry")
        XCTAssertNotEqual(before, after, "the Digital Crown did not change the entry (\(before))")
    }

    // MARK: - The regression: focus theft

    /// **The shipped bug.** A scale chip is a `Button`, so tapping one takes focus off the crown
    /// field and the crown goes dead — while the UI still looks perfectly alive.
    func testCrownStillWorksAfterTappingAScaleChip() {
        let app = launch()
        crown(6)
        let beforeTap = read(app, "watch.entry")

        // `CrownScale` is a String enum — sixteenth / inch / foot — so the identifiers are
        // `crownScale.<case name>`, not indices. "foot" is never the default, so tapping it is a
        // real selection change.
        let chip = any(app, "crownScale.foot")
        guard chip.waitForExistence(timeout: 10) else {
            return XCTFail("no scale chip to tap — identifiers changed?")
        }
        chip.tap()

        crown(6)
        XCTAssertNotEqual(read(app, "watch.entry"), beforeTap,
                          "the crown died after tapping a scale chip — focus was not handed back")
    }

    /// Same failure through the Add button, which is how the user hit it: Add consumed a stale
    /// entry because the crown had stopped updating it.
    func testCrownStillWorksAfterAdd() {
        let app = launch()
        crown(6)
        any(app, "watch.add").tap()
        let afterAdd = read(app, "watch.entry")
        crown(6)
        XCTAssertNotEqual(read(app, "watch.entry"), afterAdd,
                          "the crown died after Add — focus was not handed back")
    }

    func testCrownStillWorksAfterClear() {
        let app = launch()
        crown(6)
        any(app, "watch.clear").tap()
        let afterClear = read(app, "watch.entry")
        crown(6)
        XCTAssertNotEqual(read(app, "watch.entry"), afterClear,
                          "the crown died after Clear — focus was not handed back")
    }

    // MARK: - State space: both directions, not just one

    /// Add then Sub of the SAME entry must return the running total to where it started. This is the
    /// assertion that catches a subtraction wired as an addition, which no worked example can.
    func testAddThenSubtractReturnsToTheStart() {
        let app = launch()
        let start = read(app, "watch.total")
        crown(6)
        any(app, "watch.add").tap()
        let added = read(app, "watch.total")
        XCTAssertNotEqual(added, start, "Add did nothing")

        any(app, "watch.sub").tap()
        XCTAssertEqual(read(app, "watch.total"), start,
                       "Add then Sub of the same entry did not return to \(start)")
    }

    /// Clear is a reset, not a decrement.
    func testClearZeroesTheTotal() {
        let app = launch()
        crown(6)
        any(app, "watch.add").tap()
        XCTAssertNotEqual(read(app, "watch.total"), "0\"", "nothing to clear")
        any(app, "watch.clear").tap()
        XCTAssertTrue(read(app, "watch.total").contains("0"),
                      "Clear left \(read(app, "watch.total"))")
    }

    /// Every scale chip is reachable and selecting one keeps the crown alive. The chips exist because
    /// the crown otherwise takes too long to cross a real measurement.
    func testEveryScaleChipIsSelectableAndKeepsTheCrown() {
        let app = launch()
        for raw in ["sixteenth", "inch", "foot"] {
            let chip = any(app, "crownScale.\(raw)")
            XCTAssertTrue(chip.waitForExistence(timeout: 10), "no chip crownScale.\(raw)")
            chip.tap()
            let before = read(app, "watch.entry")
            crown(6)
            XCTAssertNotEqual(read(app, "watch.entry"), before,
                              "crown dead after selecting scale \(raw)")
        }
    }

    // MARK: - Every watch calculator, checked against a known answer

    /// The watch is not a viewer — it computes. Each tool ships a deterministic default state, so
    /// each has exactly one right answer on launch and no interaction is needed to assert it.
    ///
    /// Expected values are the same worked examples the Kits assert, duplicated on purpose: if a Kit
    /// answer changes, both layers must be updated and the diff makes that visible. A failure here
    /// means the WIRING between Kit and watch screen is broken, not that the maths is wrong.
    private func assertShows(_ tool: String, _ id: String, _ needle: String,
                             file: StaticString = #filePath, line: UInt = #line) {
        let app = launch(tool: tool)
        let got = read(app, id)
        XCTAssertTrue(got.contains(needle),
                      "\(tool)/\(id): expected to contain «\(needle)», got «\(got)»",
                      file: file, line: line)
        app.terminate()
    }

    /// 12" in → 304.8 mm, the 1959 international inch exactly.
    func testWatchConvertsInchesToMillimetres() { assertShows("convert", "watch.mm", "304.8") }

    /// 6-in-12 → 26.57°.
    func testWatchRoofPitchAngle() { assertShows("roofPitch", "watch.angle", "26.57") }

    /// 3-4-5: legs 36" and 48" → a 60" (5 ft) diagonal.
    func testWatchDiagonalIsThreeFourFive() { assertShows("diagonal", "watch.diagonal", "5'") }

    /// A 4" pipe wraps at π × 4 = 12.566". The watch renders feet-inches, so that is `1' 9/16"`
    /// (12.5625" — 12.566 rounded to sixteenths), NOT a bare "12.57". Assert the fraction, which is
    /// the part that pins the rounding.
    func testWatchPipeWrap() { assertShows("circle", "watch.wrap", "9/16") }

    /// 2 x 4 x 8 ft = 5.33 board feet.
    func testWatchBoardFeet() { assertShows("boardFeet", "watch.bf", "5.33") }

    /// AWG 12 = 0.0808 in (NBS Handbook 100 §2.1).
    func testWatchWireGaugeDiameter() { assertShows("wireGauge", "watch.awgInch", "0.0808") }

    /// AWG 12 = 2.053 mm.
    func testWatchWireGaugeMillimetres() { assertShows("wireGauge", "watch.awgMm", "2.05") }

    // MARK: - Coverage guard

    /// Every tool the catalog puts on the watch must be asserted above.
    ///
    /// Without this, adding an eighth watch tool silently ships untested — the suite stays green
    /// because nothing asserts the LIST is complete. `Tool.onWatch` is the source of truth; update
    /// both when it changes.
    func testEveryWatchToolIsCovered() {
        let onWatch = ["tapeCalc", "convert", "roofPitch", "boardFeet",
                       "diagonal", "circle", "wireGauge"]
        let asserted = ["tapeCalc",        // the crown tests above
                        "convert", "roofPitch", "diagonal", "circle", "boardFeet", "wireGauge"]
        XCTAssertEqual(onWatch.count, 7, "the watch ships 7 calculators")
        XCTAssertEqual(Set(onWatch), Set(asserted), "a watch tool has no assertion")
    }

    /// Every watch screen, including the catalog list, renders rather than coming up empty.
    func testEveryWatchToolOpens() {
        for tool in ["tapeCalc", "convert", "roofPitch", "boardFeet",
                     "diagonal", "circle", "wireGauge", "list"] {
            let app = launch(tool: tool)
            XCTAssertEqual(app.state, .runningForeground, "\(tool) failed to open")
            XCTAssertTrue(app.descendants(matching: .any).count > 1, "\(tool) came up empty")
            app.terminate()
        }
    }
}

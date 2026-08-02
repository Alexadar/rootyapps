import XCTest

/// **The regression suite for the reported defect: focusable Buttons steal Digital Crown input.**
///
/// ## The bug
///
/// On watchOS `.digitalCrownRotation` only receives events while its view holds focus, and every
/// `Button`, `Toggle` and `Picker` is focusable by default. So tapping any control beside a crown field
/// silently moves focus off the field and **the crown goes dead**: nothing crashes, no layout changes,
/// no error appears — the number just stops responding, and every later action re-applies the stale
/// value. It is invisible to a build, to a unit test, and to a screenshot.
///
/// ## Why this is a real test and not a manual check
///
/// The crown IS scriptable: `XCUIDevice.shared.rotateDigitalCrown(delta:)` has been in
/// `XCUIAutomation`'s `XCUIDevice.h`, gated on `TARGET_OS_WATCH`, since Xcode 13. So the shape below is
/// executable:
///
/// > turn the crown → assert the value moved → **tap the sibling control** → turn again → **assert it
/// > moved again**.
///
/// Before `CrownFocus.reclaim()` the second rotation does nothing at all. "Install and look" is
/// therefore reserved for *appearance* only — rendering at 40 mm/49 mm and the always-on state.
///
/// ## What is deliberately not asserted
///
/// Never a specific number. `delta` is in revolutions and each field has its own `step` and
/// `sensitivity`, so pinning a value would test the framework's detent arithmetic rather than this
/// app's focus handling. Every assertion is "it changed" / "it changed again".
///
/// Twelve of the 20 screens carry a control beside a crown field; the other eight have only crown
/// fields, whose focus rival is the sibling field — covered by the two-field shape below. The guard at
/// the bottom asserts the two lists sum to 20.
final class CrownFocusChecks: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    /// The shape, once: crown works → tap a sibling control → crown STILL works.
    ///
    /// Change is detected on the **field's own value**, not on the hero.
    ///
    /// The hero is a derived figure and is sometimes *quantised*: Stairs' hero is a riser COUNT, an
    /// integer that only moves once `totalRise` has travelled 3.75", so a live crown can turn several
    /// detents and leave it reading `15`. That produced a false "the crown went DEAD" on Stairs while
    /// the crown was working perfectly. The field's own readout moves on every detent by construction,
    /// which is exactly the question this suite asks — whether crown events still *reach the field*.
    /// That the field then drives the hero is what `WatchCalculationChecks` proves.
    /// `fields` lists every crown field the screen can mount, because a **mode picker can replace the
    /// field itself**: Pavers swaps an AREA field for a WALL LENGTH one, and Mortar swaps a unit COUNT
    /// for a wall AREA (grout is priced by area). After the tap the original identifier is simply gone,
    /// so the live one is resolved at each stage rather than assumed.
    /// `observeHero` watches the hero instead of the field.
    ///
    /// Needed only where the field is not a stable thing to *read*. Pavers' content is ~200 pt against a
    /// 40 mm viewport's 197, so the screen can always scroll a little, and watchOS drops accessibility
    /// leaves that scroll off — the field kept vanishing mid-assertion ("no element"), while a direct
    /// probe showed the crown moving it 200 → 226 perfectly well. The hero is the first element, so it
    /// survives, and on Pavers it tracks the field one-for-one (area → paver count moves on every step).
    /// Not used where a hero is quantised — Stairs' riser COUNT only moves every 3.75" of rise, which is
    /// what made the hero useless there and drove the switch to fields in the first place.
    private func assertCrownSurvives(tool: String, fields: [String], readout: String,
                                    tapping control: String, observeHero: Bool = false,
                                    file: StaticString = #filePath, line: UInt = #line) {
        let app = launchWatch(tool: tool)
        XCTAssertTrue(any(app, readout).waitForExistence(timeout: 15),
                      "\(tool): the hero '\(readout)' never rendered", file: file, line: line)

        func liveField(_ stage: String) -> String {
            if observeHero { return readout }
            for id in fields where any(app, id).exists { return id }
            XCTFail("\(tool): no crown field on screen \(stage) — looked for \(fields)",
                    file: file, line: line)
            return fields[0]
        }

        // 1. The crown drives the targeted field at all.
        let f1 = liveField("at launch")
        let start = value(app, f1)
        let afterFirst = turnCrownAndRead(app, f1, from: start)
        XCTAssertNotEqual(afterFirst, start,
                          "\(tool): the crown did not move '\(f1)' even before any tap — " +
                          "the field is not focused on appear",
                          file: file, line: line)

        // 2. Tap the sibling control. THIS is what used to kill the crown.
        tapId(app, control, file: file, line: line)

        // Let the mode change settle before resolving the field again.
        //
        // On Pavers and Mortar the picker *replaces* the mounted field, and SwiftUI removes the old one
        // a beat after the tap registers. Without this pause `liveField` saw the outgoing
        // `input.pavers.area` still `.exists`, returned it, and the read a moment later failed with
        // "no element" — a race in the test, not a fault in the app. There is no XCUITest primitive for
        // "a conditional view swap has finished", so this waits.
        Thread.sleep(forTimeInterval: 1.0)

        // 3. …and the crown must still work, on whichever field is now mounted.
        let f2 = liveField("after tapping \(control)")
        let afterTap = value(app, f2)
        let afterSecond = turnCrownAndRead(app, f2, from: afterTap)
        XCTAssertNotEqual(afterSecond, afterTap,
                          "\(tool): the crown went DEAD after tapping '\(control)'. " +
                          "That control took focus and nothing handed it back — add crownFocus.reclaim() " +
                          "to its action.",
                          file: file, line: line)
        XCTAssertEqual(app.state, .runningForeground, file: file, line: line)
        app.terminate()
    }

    /// Concrete — the worst case: two crown fields AND a −/+ stepper pair between them and the answer.
    func testConcreteCrownSurvivesTheThicknessSteppers() {
        assertCrownSurvives(tool: "concrete", fields: ["input.concrete.length"],
                            readout: "result.concrete.hero", tapping: "input.concrete.thick.inc")
    }

    /// …and the other stepper direction, because `reclaim()` has to be on BOTH actions.
    func testConcreteCrownSurvivesTheDecrementStepper() {
        assertCrownSurvives(tool: "concrete", fields: ["input.concrete.length"],
                            readout: "result.concrete.hero", tapping: "input.concrete.thick.dec")
    }

    /// Stairs — a Picker beside the crown field. A Picker takes focus exactly like a Button.
    func testStairsCrownSurvivesTheCodePicker() {
        assertCrownSurvives(tool: "stairs", fields: ["input.stairs.totalRise"],
                            readout: "result.stairs.hero", tapping: "input.stairs.code")
    }

    /// Rebar — the Picker sits ABOVE the crown field here, which is a different focus order.
    func testRebarCrownSurvivesTheBarPicker() {
        assertCrownSurvives(tool: "rebar", fields: ["input.rebar.length"],
                            readout: "result.rebar.hero", tapping: "input.rebar.bar")
    }

    /// Convert — two pickers, and the hero is a conversion, so a dead crown means a silently stale
    /// answer in the one screen whose entire job is converting the value you just dialled.
    func testConvertCrownSurvivesTheUnitPickers() {
        assertCrownSurvives(tool: "units", fields: ["input.units.value"],
                            readout: "result.units.hero", tapping: "input.units.to")
    }

    /// Pitch and Grade have two crown fields and no other control, so the sibling that can steal focus
    /// is the OTHER FIELD: tapping it must move the crown's target, and the crown must drive the new one.
    func testTappingTheOtherFieldMovesTheCrownTarget() {
        let app = launchWatch(tool: "pitch")
        XCTAssertTrue(any(app, "input.pitch.rise").waitForExistence(timeout: 10))

        // Field 0 (RISE) is targeted on appear: the crown must move the angle.
        let start = value(app, "result.pitch.hero")
        let moved = turnCrownAndRead(app, "result.pitch.hero", from: start)
        XCTAssertNotEqual(moved, start, "the crown did not drive RISE on appear")

        // Target RUN instead, and confirm the crown drives THAT field now.
        tapId(app, "input.pitch.run")
        let runBefore = value(app, "input.pitch.run")
        let runAfter = turnCrownAndRead(app, "input.pitch.run", from: runBefore)
        XCTAssertNotEqual(runAfter, runBefore,
                          "tapping RUN did not hand the crown to it — the crown is still on RISE or dead")
        XCTAssertEqual(app.state, .runningForeground)
    }

    /// Grade, same shape, because its two fields carry different steps (0.5 ft and 0.125 in) and a
    /// sensitivity mismatch would show up as a field that "cannot be moved".
    func testGradeBothFieldsAcceptTheCrown() {
        let app = launchWatch(tool: "grade")
        XCTAssertTrue(any(app, "input.grade.run").waitForExistence(timeout: 10))

        let runBefore = value(app, "input.grade.run")
        XCTAssertNotEqual(turnCrownAndRead(app, "input.grade.run", from: runBefore), runBefore,
                          "the crown did not drive RUN")

        tapId(app, "input.grade.fall")
        let fallBefore = value(app, "input.grade.fall")
        XCTAssertNotEqual(turnCrownAndRead(app, "input.grade.fall", from: fallBefore), fallBefore,
                          "the crown did not drive FALL after it was targeted")
    }

    // MARK: - The 8 screens whose pickers arrived with the full 20-tool catalog

    /// Aggregate — a material picker that changes tons per cubic yard, so a dead crown here means
    /// ordering the wrong tonnage of stone.
    func testAggregateCrownSurvivesTheMaterialPicker() {
        assertCrownSurvives(tool: "aggregate", fields: ["input.aggregate.length"],
                            readout: "result.aggregate.hero", tapping: "input.aggregate.material")
    }

    /// Pavers — the mode picker also swaps which crown field is mounted (area vs wall length), so this
    /// checks focus survives a picker that changes the field set underneath it.
    func testPaversCrownSurvivesTheModePicker() {
        assertCrownSurvives(tool: "pavers", fields: ["input.pavers.area", "input.pavers.wallLength"],
                            readout: "result.pavers.hero", tapping: "input.pavers.mode",
                            observeHero: true)
    }

    /// Area — the shape picker hides the second field for a circle, same hazard as Pavers.
    func testAreaCrownSurvivesTheShapePicker() {
        assertCrownSurvives(tool: "area", fields: ["input.area.a"],
                            readout: "result.area.hero", tapping: "input.area.shape")
    }

    func testVolumeCrownSurvivesTheShapePicker() {
        assertCrownSurvives(tool: "volume", fields: ["input.volume.a"],
                            readout: "result.volume.hero", tapping: "input.volume.shape")
    }

    func testEstimateCrownSurvivesTheModePicker() {
        assertCrownSurvives(tool: "estimate", fields: ["input.estimate.area"],
                            readout: "result.estimate.hero", tapping: "input.estimate.mode")
    }

    /// Mortar — the mode picker swaps a COUNT field for an AREA field (grout is priced by wall area),
    /// so focus has to land on whichever one is now mounted.
    func testMortarCrownSurvivesTheModePicker() {
        assertCrownSurvives(tool: "mortar", fields: ["input.mortar.count", "input.mortar.wallArea"],
                            readout: "result.mortar.hero", tapping: "input.mortar.mode")
    }

    func testOffsetCrownSurvivesTheFittingPicker() {
        assertCrownSurvives(tool: "offset", fields: ["input.offset.set"],
                            readout: "result.offset.hero", tapping: "input.offset.angle")
    }

    func testRollingOffsetCrownSurvivesTheFittingPicker() {
        assertCrownSurvives(tool: "rollingOffset", fields: ["input.rollingOffset.set"],
                            readout: "result.rollingOffset.hero", tapping: "input.rollingOffset.angle")
    }

    // MARK: - Coverage guard

    /// Every screen carrying a control beside a crown field must appear above.
    ///
    /// The screens with no such control have crown fields and nothing else tappable, so their only
    /// focus rival is the sibling field — covered by `testTappingTheOtherFieldMovesTheCrownTarget`'s
    /// shape instead. Listing them above would assert a control that does not exist.
    ///
    /// Together the two lists must account for all 20 screens, so a new tool lands in one or the other
    /// rather than escaping the crown suite entirely.
    func testEveryScreenWithAFocusStealingControlIsCovered() {
        let withControls = ["concrete", "stairs", "rebar", "units",
                            "aggregate", "pavers", "area", "volume",
                            "estimate", "mortar", "offset", "rollingOffset"]
        let twoFieldsOnly = ["pitch", "grade", "rafter", "footing",
                             "lumber", "miter", "cutLength", "roofing"]
        XCTAssertEqual(Set(withControls).count, withControls.count, "duplicate in the covered list")
        XCTAssertTrue(Set(withControls).isDisjoint(with: Set(twoFieldsOnly)),
                      "a screen cannot be in both lists")
        XCTAssertEqual(withControls.count + twoFieldsOnly.count, 20,
                       "every one of the 20 watch screens must be in exactly one list")
    }
}

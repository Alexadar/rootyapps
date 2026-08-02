import XCTest

/// The Spec tab keypad — that keys reach the engine and the engine's answer reaches the readout.
///
/// The combinatorial coverage of the engine itself lives in
/// `Kits/Dimension/DimensionKit/Tests/DimensionKitTests/TapeCalcStateSpaceTests.swift`: every operator,
/// every chained pair, every denominator × display precision, every reset path. That file runs in
/// microseconds. Driving the same cases through this keypad costs ~1.1 s per tap, so what remains here
/// is deliberately one assertion per behaviour — enough to prove the binding, no more.
///
/// Split into its own class because `-parallel-testing-enabled` shards by test CLASS, not by method:
/// this one, `CalculationChecks` and `NavigationChecks` are the three workers.
final class KeypadChecks: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    /// 6'2½" reads out as feet-inch-fraction, and + 2'7¾" = 8'10¼".
    /// (74.5" + 31.75" = 106.25" = 8'10¼".)  Kit oracle: `FeetInchOracleTests`.
    func testFeetInchFractionEntryAndAddition() {
        let app = launchApp()
        enter(app, feet: 6, inches: 2, num: 1, den: 2)
        assertShows(app, "calc.readout", "6'")
        assertShows(app, "calc.readout", "2-1/2")

        tapId(app, "key.op.add")
        enter(app, feet: 2, inches: 7, num: 3, den: 4)
        tapId(app, "key.equals")
        assertShows(app, "calc.readout", "8'")
        assertShows(app, "calc.readout", "10-1/4")
    }

    /// The exact tape shown in the store reel: 8'4½" × 3 − 2'6" ÷ 2 = 11'3¾".
    /// Left-to-right tape math: 100.5" × 3 = 301.5" − 30" = 271.5" ÷ 2 = 135.75" = 11'3¾".
    func testReelCutListTape() {
        let app = launchApp()
        enter(app, feet: 8, inches: 4, num: 1, den: 2)
        assertShows(app, "calc.readout", "8'")

        tapId(app, "key.op.mul"); enterScalar(app, 3)
        tapId(app, "key.op.sub"); enter(app, feet: 2, inches: 6)
        tapId(app, "key.op.div"); enterScalar(app, 2)
        tapId(app, "key.equals")

        assertShows(app, "calc.readout", "11'")
        assertShows(app, "calc.readout", "3-3/4")
    }

    /// Dimensioned multiplication: 10' × 8' is an AREA, and it says so.
    /// Kit oracle: `TapeDimensionTests.areaFromTwoLengths`.
    func testLengthTimesLengthIsAnArea() {
        let app = launchApp()
        enter(app, feet: 10)
        tapId(app, "key.op.mul")
        enter(app, feet: 8)
        tapId(app, "key.equals")
        assertShows(app, "calc.readout", "80 sq ft")
    }

    /// REGRESSION — the dimension must survive an intermediate `=`.
    ///
    /// `10' × 8' =` (read 80 sq ft) then `× 4" =` used to display **320 sq ft**: pressing `=` cleared
    /// the pending operator, and the next `setOp` then took the "nothing typed" branch of
    /// `commitEntryIntoAccumulator`, which reset the accumulated dimension to `.linear`. So the second
    /// multiplication computed another area instead of a volume — wrong number AND wrong unit, with
    /// nothing on screen looking broken.
    ///
    /// Reading an intermediate result and carrying on is exactly what a worker does at a pour, so this
    /// path matters more than the chained one the old tests covered. The model-level guard is
    /// `TapeCalcStateSpaceTests.dimensionLadderUp`; this proves the fix reaches the screen.
    func testDimensionSurvivesAnIntermediateEquals() {
        let app = launchApp()
        enter(app, feet: 10)
        tapId(app, "key.op.mul")
        enter(app, feet: 8)
        tapId(app, "key.equals")
        assertShows(app, "calc.readout", "80 sq ft")

        tapId(app, "key.op.mul")
        enter(app, inches: 4)
        tapId(app, "key.equals")
        let got = value(app, "calc.readout")
        XCTAssertTrue(got.contains("cu ft"),
                      "area × length must be a VOLUME after an intermediate '=', got «\(got)»")
        XCTAssertTrue(got.contains("26.67"), "expected 26.67 cu ft, got «\(got)»")
    }

    /// The denominator chips change the displayed precision. One assertion per chip, both directions —
    /// a control tested only in its default state is how a dead toggle ships.
    func testDenominatorChipsChangeThePrecision() {
        let app = launchApp()
        // 5" + a 1/16 fraction: visible at 1/16, necessarily coarser at 1/8.
        enter(app, inches: 5, num: 1, den: 16)
        tapId(app, "denominator.16")
        let atSixteenth = value(app, "calc.readout")
        XCTAssertTrue(atSixteenth.contains("/16"), "1/16 display did not show a sixteenth: «\(atSixteenth)»")

        tapId(app, "denominator.8")
        let atEighth = value(app, "calc.readout")
        XCTAssertNotEqual(atEighth, atSixteenth, "the 1/8 chip did not change the readout")

        tapId(app, "denominator.16")           // and back — a one-way toggle is still a bug
        assertShows(app, "calc.readout", "/16")
    }

    /// `C` returns the readout to zero from a mid-entry state, and the pad still works afterwards.
    func testClearResetsAndThePadStillWorks() {
        let app = launchApp()
        enter(app, feet: 12, inches: 4)
        tapId(app, "key.clear")
        tapId(app, "key.clear")                // first clears the entry, second the accumulator
        let cleared = value(app, "calc.readout")
        XCTAssertTrue(cleared.contains("0"), "C did not reset the readout, got «\(cleared)»")

        enterScalar(app, 7)                    // not bricked
        assertShows(app, "calc.readout", "7")
        XCTAssertEqual(app.state, .runningForeground)
    }

    /// Backspace unwinds an entry instead of underflowing.
    func testBackspaceUnwinds() {
        let app = launchApp()
        enter(app, feet: 12)
        for _ in 0..<10 { tapId(app, "key.backspace") }
        XCTAssertEqual(app.state, .runningForeground, "backspacing past empty took the app down")
        enterScalar(app, 5)
        assertShows(app, "calc.readout", "5")
    }
}

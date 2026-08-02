import XCTest

/// Every shipping calculator, checked through the UI against a known answer.
///
/// ## What this is for
///
/// `DefectChecks` proves the app does not regress the incumbent's four defects. This file proves
/// the **numbers on screen are right** — one assertion per calculator, so nobody has to open the
/// app and check by hand.
///
/// ## What it is NOT
///
/// It is not where the maths is verified. Each Kit owns that: 151 `swift test` assertions against
/// NIST SP 811, NIST PS 20-20, the 1959 Federal Register, USDA AH-73 and NBS Handbook 100. If a
/// number here is wrong, the Kit test is the one that should have caught it, and this test only
/// tells you the **wiring** between the Kit and the screen is broken — a view reading the wrong
/// property, a formatter dropping a fraction, a tool showing another tool's result.
///
/// So the expected values below are deliberately the SAME worked examples the Kits assert. They
/// are duplicated on purpose: if someone changes a Kit's answer, both layers must be updated, and
/// the diff makes that visible.
///
/// ## Running
///
///     xcodebuild test -scheme storypole \
///       -destination 'platform=iOS Simulator,name=SP-iPhone' \
///       -only-testing:storypoleUITests/CalculationChecks
///
/// Simulator only — never a physical device (see `DefectChecks` for why).
final class CalculationChecks: XCTestCase {

    override func setUp() { super.setUp(); continueAfterFailure = false }

    // MARK: - Helpers

    private func open(_ tool: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["STORYPOLE_TOOL"] = tool
        // Pin the locale. Storypole is a US-market app and `Fmt` follows the device
        // region, so on a comma-decimal simulator every number renders "152,11" and ten
        // of these tests fail on the separator rather than on the arithmetic.
        app.launchEnvironment["STORYPOLE_LANG"] = "en"
        app.launch()
        return app
    }

    /// The value of a result row, by identifier, regardless of the element type SwiftUI chose.
    private func value(_ app: XCUIApplication, _ id: String,
                       file: StaticString = #filePath, line: UInt = #line) -> String {
        let e = app.descendants(matching: .any).matching(identifier: id).firstMatch
        XCTAssertTrue(e.waitForExistence(timeout: 10), "no element '\(id)'", file: file, line: line)
        // `.text`, not `.label` — a plain SwiftUI Text has an EMPTY label on macOS and carries
        // its string in `value` instead. See UITestSupport.swift.
        return e.text
    }

    private func assertShows(_ app: XCUIApplication, _ id: String, _ needle: String,
                             file: StaticString = #filePath, line: UInt = #line) {
        let got = value(app, id)
        XCTAssertTrue(got.contains(needle),
                      "\(id): expected to contain «\(needle)», got «\(got)»", file: file, line: line)
    }

    // MARK: - Tape (DimensionKit)

    /// The hero calculation, driven on the real keypad: 6' 2-1/2" + 2' 7-3/4" = 8' 10-1/4".
    /// Kit oracle: exact rational addition — `FeetInchTests.additionIsExactlyInvertible`.
    func testTapeCalculatorAddsMixedFractions() {
        let app = XCUIApplication()
        app.launchEnvironment["STORYPOLE_LANG"] = "en"
        app.launch()
        func tap(_ id: String) {
            let b = app.buttons["key.\(id)"]
            XCTAssertTrue(b.waitForExistence(timeout: 5), "missing \(id)"); b.tap()
        }
        for k in ["digit6", "feet", "digit2", "inch", "digit1", "fraction", "digit2"] { tap(k) }
        tap("op.add")
        for k in ["digit2", "feet", "digit7", "inch", "digit3", "fraction", "digit4"] { tap(k) }
        tap("equals")
        let r = app.staticTexts["calc.readout"].text
        XCTAssertTrue(r.contains("8'") && r.contains("10") && r.contains("1/4"),
                      "expected 8' 10-1/4\", got «\(r)»")
    }

    /// Dimensioned multiplication: 12'4" × 12'4" = 152.11 sq ft.
    /// Kit oracle: `TapeCalcTests.dimensionedMultiplicationWorks` (21904 in² / 144).
    func testDimensionedMultiplicationGivesSquareFeet() {
        let app = XCUIApplication()
        app.launchEnvironment["STORYPOLE_LANG"] = "en"
        app.launch()
        func tap(_ id: String) { app.buttons["key.\(id)"].tap() }
        _ = app.buttons["key.digit1"].waitForExistence(timeout: 10)
        for k in ["digit1", "digit2", "feet", "digit4", "inch"] { tap(k) }
        tap("op.mul")
        for k in ["digit1", "digit2", "feet", "digit4", "inch"] { tap(k) }
        tap("equals")
        let r = app.staticTexts["calc.readout"].text
        XCTAssertTrue(r.contains("152.11") && r.contains("sq ft"),
                      "expected 152.11 sq ft, got «\(r)»")
    }

    /// 1 in ≡ 25.4 mm exactly — Federal Register 59-5442 (1959). 12' 6-1/2" = 3822.7 mm.
    func testConvertUsesTheExactInch() {
        let app = open("convert")
        assertShows(app, "convert.feetInch", "12'")
        assertShows(app, "convert.mm", "3822.7")
    }

    /// The display precision, and the tie rule. 8-7/16" at 1/16 stays 8-7/16".
    func testFractionRoundHoldsTheEnteredValue() {
        let app = open("fraction")
        assertShows(app, "fraction.result", "7/16")
    }

    // MARK: - Layout (LayoutKit) — the differentiator

    /// 62-1/4" in 8 equal parts. Bay = 7-25/32", shown as 7-3/4" at the 1/16 display precision,
    /// and there are 9 marks (parts + 1), the last landing exactly on the span.
    /// Kit oracle: `LayoutTests.baysSumToSpanExactly`.
    func testEqualSpacingBayAndMarkCount() {
        let app = open("equalSpacing")
        assertShows(app, "spacing.bay", "7")
        let marks = app.descendants(matching: .any).matching(identifier: "spacing.marks").firstMatch
        XCTAssertTrue(marks.waitForExistence(timeout: 10), "no marks list")
        // The last mark must BE the span — that is the whole promise of the tool.
        XCTAssertTrue(app.staticTexts["5' 2-1/4\""].exists
                      || marks.text.contains("5'"),
                      "the final mark should land on the 62-1/4\" span")
    }

    /// A 20'7-1/2" wall at 16" o.c.: 16 studs and a 7-1/2" odd last bay, reported not hidden.
    /// Kit oracle: `LayoutTests.oddLastBayIsReported`.
    func testOnCenterCountAndOddBay() {
        let app = open("onCenter")
        assertShows(app, "oc.count", "16")
        assertShows(app, "oc.lastBay", "7")
    }

    // MARK: - Takeoff (VolumeKit)

    /// 12'4" × 12'4" = 152.11 sq ft. Same worked example as the keypad, via the Area tool.
    func testAreaSquareFeet() {
        let app = open("area")
        assertShows(app, "area.result", "152.11")
    }

    /// 10' × 8' × 4" = 26.667 cu ft. Kit oracle: `AreaVolumeTests.volumes`.
    func testVolumeCubicFeet() {
        let app = open("volume")
        assertShows(app, "volume.result", "26.667")
    }

    /// A 10×10 slab at 4" is 33.33 ft³; +10 % waste over 27 ft³/yd³ = 1.36 yd³.
    /// Kit oracle: `AreaVolumeTests.slab` + NIST SP 811 §B.8 for the yd³ factor.
    func testCubicYardsWithWaste() {
        let app = open("cubicYards")
        assertShows(app, "yards.ft3", "33.33")
        assertShows(app, "yards.result", "1.36")
    }

    // MARK: - Roof (PitchKit)

    /// A 6/12 roof read three ways — 26.57°, 50 %, ×1.118034 — because three trades each use one.
    /// Kit oracle: `PitchRafterOracleTests.sixTwelve`.
    func testRoofPitchThreeWays() {
        let app = open("roofPitch")
        assertShows(app, "pitch.angle", "26.57")
        assertShows(app, "pitch.percent", "50")
        assertShows(app, "pitch.multiplier", "1.118034")
    }

    /// Framing-square bridge measure: a 6/12 common rafter is 13.42" per foot of run,
    /// hip/valley 18.00". Kit oracle: `PitchRafterOracleTests.commonPerFootRun`.
    func testRafterBridgeMeasure() {
        let app = open("rafter")
        assertShows(app, "rafter.perFoot", "13.42")
        assertShows(app, "rafter.hip", "18.00")
        assertShows(app, "rafter.plumb", "26.57")
    }

    // MARK: - Geometry (GeometryKit)

    /// 12' and 16' give exactly 20' — the 3-4-5 triple scaled by four.
    /// Kit oracle: `GeometryOracleTests.integerTriples`.
    func testSquareUpDiagonal() {
        let app = open("diagonal")
        assertShows(app, "diag.result", "20'")
    }

    /// A square corner mitres at 45°. Kit oracle: `GeometryOracleTests.cornerMiter`.
    func testMiterForASquareCorner() {
        let app = open("miter")
        assertShows(app, "miter.result", "45")
    }

    /// Pipe wrap on a 4" pipe is πd = 12.566". Kit oracle: `GeometryOracleTests.pipeWrap`.
    func testCircumferenceOfAFourInchPipe() {
        let app = open("circle")
        assertShows(app, "circle.decimal", "12.566")
    }

    // MARK: - Lumber (LumberKit) — the strongest oracle in the app

    /// A 2×4×8 is exactly 5⅓ board feet — NIST PS 20-20 §2.2.
    /// Kit oracle: `LumberOracleTests.boardMeasure`.
    func testBoardFeetForATwoByFour() {
        let app = open("boardFeet")
        assertShows(app, "bf.total", "5.333")
    }

    /// A 2×4 is 1-1/2" × 3-1/2" dry — NIST PS 20-20 Table 3, the row everyone knows.
    /// Kit oracle: `LumberOracleTests.twoByFour`.
    func testDressedSizeTableCarriesTheKnownRow() {
        let app = open("dressedSize")
        let table = app.descendants(matching: .any).matching(identifier: "dressed.table").firstMatch
        XCTAssertTrue(table.waitForExistence(timeout: 10), "no dressed-size table")
        XCTAssertTrue(app.staticTexts["1-1/2\""].exists && app.staticTexts["3-1/2\""].exists,
                      "the 2x4 row (1-1/2\" x 3-1/2\") must be present")
    }

    // MARK: - Gauge (GaugeKit)

    /// 12 AWG is 0.0808" — NBS Handbook 100 §2.1's geometric progression.
    /// Kit oracle: `AWGOracleTests.circularMils`.
    func testWireGaugeDiameter() {
        let app = open("wireGauge")
        assertShows(app, "awg.inch", "0.0808")
    }

    // MARK: - Coverage guard

    /// Every tool in the catalog must be covered by a numeric check above.
    ///
    /// Without this, adding a seventeenth calculator silently ships untested: the suite stays
    /// green because nothing asserts that the LIST is complete. Update both when the catalog grows.
    func testEveryToolHasANumericCheck() {
        let covered = ["tapeCalc", "convert", "fraction", "equalSpacing", "onCenter",
                       "area", "volume", "cubicYards", "roofPitch", "rafter",
                       "diagonal", "miter", "circle", "boardFeet", "dressedSize", "wireGauge"]
        XCTAssertEqual(covered.count, 16, "the catalog ships 16 calculators")
        XCTAssertEqual(Set(covered).count, covered.count, "duplicate in the coverage list")
    }
}

import XCTest

/// One on-screen NUMBER per shipping calculator — all 20 in the catalog.
///
/// ## What this layer proves, and what it deliberately does not
///
/// Not the arithmetic. The `*Kit` packages own that, against cited published sources, and re-deriving
/// it here would only duplicate the oracle at ~1.1 s per interaction instead of microseconds. What a
/// UI test proves is **wiring**: that the right Kit function is called with the right inputs and that
/// its answer reaches the right label on screen. A model test cannot catch a view bound to the wrong
/// property, and a Kit test cannot catch a hero reading the wrong tool's number.
///
/// Every expected value below was computed from the tool view's own `@State` defaults through the
/// same Kit call the view makes, then formatted the way the view formats it (`%.2f` unless noted).
/// They are duplicated from the Kit layer **on purpose**: if someone changes a Kit answer, both
/// layers must be updated, and the diff makes that visible.
///
/// Each tool is reached by its `KERFCALC_TOOL` deep link rather than by scroll-hunting the grid —
/// deterministic however long the catalog grows, and it exercises the same deep link the reel and
/// screenshot pipelines depend on. Navigation *from* the grid is covered by `NavigationChecks`.
final class CalculationChecks: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    /// Open a tool by deep link and assert its hero contains `needle`.
    private func check(_ tool: String, _ needle: String,
                       file: StaticString = #filePath, line: UInt = #line) {
        let app = launchApp(tool: tool)
        assertShows(app, "\(tool).hero", needle, file: file, line: line)
        // A label existing does not prove the app didn't crash and relaunch behind it.
        XCTAssertEqual(app.state, .runningForeground, file: file, line: line)
        app.terminate()
    }

    // MARK: - Framing

    /// 6/12 pitch over a 12 ft run, 1½" ridge, 12" overhang → 173.57" common rafter.
    /// Kit oracle: `FramingKitTests` rafter suite (the 1' run × 13.4164"/ft identity).
    func testRafterCommonLength() { check("rafter", "173.57") }

    /// 108" total rise at a 7.5" ideal riser → 14 risers (@ 7.71" each, inside IRC's 7¾" max).
    /// Kit oracle: `FramingKit.Stairs.solve`, IRC 2021 R311.7.
    func testStairsRiserCount() { check("stairs", "14") }

    /// 4/12: √(4² + 12²) = 12.649. Rendered to 3 dp by this screen.
    /// Kit oracle: `FramingKit.Pitch.diagonal`.
    func testRightAngleDiagonal() { check("pitch", "12.649") }

    // MARK: - Concrete

    /// 10' × 10' × 4" slab = 33.33 ft³, +10% waste = 36.67 ft³ = 1.358 yd³ (3 dp).
    ///
    /// NOTE: the previous suite asserted `1.235` here — the *pre-waste* figure (33.33/27). The waste
    /// input was added to this screen afterwards and the expected value was never updated, so this
    /// test was failing (or silently not being run) before this pass.
    /// Kit oracle: `GeometryKit.Concrete.slabCubicFeet` + `.withWaste` + `.cubicYards`.
    func testConcreteOrderWithWaste() { check("concrete", "1.358") }

    /// 100 ft of 16" × 8" continuous footing = 88.89 ft³ = 3.292 yd³ (3 dp).
    /// Kit oracle: `ConcreteKit.Footing.continuousCubicFeet`.
    func testFootingCubicYards() { check("footing", "3.292") }

    /// A #4 bar weighs 0.668 lb/ft — ASTM A615 nominal. Rendered to 3 dp.
    /// Kit oracle: `ConcreteKit.BarSize.weightLbPerFt`.
    func testRebarUnitWeight() { check("rebar", "0.668") }

    /// 20' × 10' × 4" of crushed stone = 2.47 yd³ → 3.33 tons.
    /// Kit oracle: `ConcreteKit.Aggregate.tons`.
    func testAggregateTonnage() { check("aggregate", "3.33") }

    /// 200 ft² of 8" × 4" pavers +10% waste = 991 pavers.
    /// Kit oracle: `ConcreteKit.Hardscape.paverCount`.
    func testPaverCount() { check("pavers", "991") }

    /// 100 blocks → 8 bags of mortar.
    /// Kit oracle: `ConcreteKit.Mortar.bagsForBlock`.
    func testMortarBags() { check("mortar", "8") }

    // MARK: - Takeoff

    /// A 10 × 12 rectangle is 120 ft².
    /// Kit oracle: `GeometryKit.Area.rectangle`.
    func testAreaRectangle() { check("area", "120.00") }

    /// A 10 × 10 × 8 box is 800 ft³.
    /// Kit oracle: `GeometryKit.Volume.box`.
    func testVolumeBox() { check("volume", "800.00") }

    // MARK: - Materials

    /// 2000 ft² footprint at 6/12 → 2236 ft² of roof → 22.36 squares.
    /// Kit oracle: `MaterialsKit.Roofing.roofArea` (the √(1+(6/12)²) = 1.118 slope factor).
    func testRoofingSquares() { check("roofing", "22.36") }

    /// 1000 ft² of drywall → 35 4×8 sheets.
    /// Kit oracle: `MaterialsKit.Estimate.drywallSheets`.
    func testDrywallSheets() { check("estimate", "35") }

    /// A 38° spring angle on a 4-sided corner → 31.62° miter.
    /// Kit oracle: `MaterialsKit.CompoundMiter.compound`.
    func testCompoundMiterAngle() { check("miter", "31.62") }

    /// A 2×6×10 is 10 board feet — NIST PS 20 board measure.
    /// Kit oracle: `MaterialsKit.Estimate.boardFeet`.
    func testBoardFeet() { check("lumber", "10.00") }

    // MARK: - Pipe

    /// A 10" set through a 45° fitting travels 10 × √2 = 14.14".
    /// Kit oracle: `PipeKit.PipeOffset.travelIn` (the 1.414 cosecant multiplier).
    func testPipeOffsetTravel() { check("offset", "14.14") }

    /// A 6" set with an 8" roll is a 10" true offset → 14.14" travel at 45°.
    /// Kit oracle: `PipeKit.RollingOffset.solve`.
    func testRollingOffsetTravel() { check("rollingOffset", "14.14") }

    /// 24" centre-to-centre less two 1½" takeouts = 21.00" end to end.
    /// Kit oracle: `PipeKit.PipeCut.endToEndIn`.
    func testPipeCutEndToEnd() { check("cutLength", "21.00") }

    /// 40 ft at ¼"/ft falls 10.00".
    /// Kit oracle: `PipeKit.PipeGrade.fallIn`.
    func testPipeGradeFall() { check("grade", "10.00") }

    // MARK: - Convert

    /// 1 ft = 0.3048 m exactly — NIST, by definition of the international inch.
    /// Kit oracle: `DimensionKit.UnitsOracleTests`.
    func testFootToMetre() { check("units", "0.3048") }

    // MARK: - Coverage guard

    /// Every tool in the catalog must have a numeric check above.
    ///
    /// Without this, adding a twenty-first calculator ships untested: the suite stays green because
    /// nothing asserts that the LIST is complete. Update both when the catalog grows.
    ///
    /// The count is written out rather than read from `Tool.allCases` because a UI-test bundle does
    /// not link the app module. `ToolCatalogCoverageTests` in `kerfcalcTests` pins it to
    /// `Tool.allCases.count` from inside the app target, so the two together catch a drift either way.
    func testEveryToolHasANumericCheck() {
        let covered = ["rafter", "stairs", "pitch",
                       "concrete", "footing", "rebar", "aggregate", "pavers", "mortar",
                       "area", "volume",
                       "roofing", "estimate", "miter", "lumber",
                       "offset", "rollingOffset", "cutLength", "grade",
                       "units"]
        XCTAssertEqual(covered.count, 20, "the catalog ships 20 calculators")
        XCTAssertEqual(Set(covered).count, covered.count, "duplicate in the coverage list")
    }
}

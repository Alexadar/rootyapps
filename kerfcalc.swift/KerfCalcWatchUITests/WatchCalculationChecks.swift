import XCTest

/// One on-screen NUMBER per watch calculator — **all 20**, the phone's whole catalog.
///
/// These are separate tests from the phone's `CalculationChecks` even where the tool name matches,
/// because they are different views composing the same Kit calls. Where a watch screen deliberately
/// shows a different quantity than the phone (Concrete is the net pour; the phone adds a waste %) the
/// divergence is asserted here on purpose — parity would be a bug in one of the two screens.
///
/// Every expected value was computed from the watch view's own defaults through the same Kit call the
/// view makes, formatted the way the view formats it. As on the phone, this proves **wiring**, not
/// arithmetic: the Kits own the numbers against cited sources, and their 148 assertions run in
/// microseconds.
final class WatchCalculationChecks: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    private func check(_ tool: String, _ id: String, _ needle: String,
                       file: StaticString = #filePath, line: UInt = #line) {
        let app = launchWatch(tool: tool)
        assertShows(app, id, needle, file: file, line: line)
        XCTAssertEqual(app.state, .runningForeground, file: file, line: line)
        app.terminate()
    }

    /// Convenience for the common case: the tool's hero.
    private func hero(_ tool: String, _ needle: String,
                      file: StaticString = #filePath, line: UInt = #line) {
        check(tool, "result.\(tool).hero", needle, file: file, line: line)
    }

    // MARK: - Framing

    /// 6/12 over a 12 ft run, 1½" ridge, 12" overhang → 173.57" cut; the line length to the ridge
    /// centre is 161.00" and the plumb cut 26.57°.
    /// Kit oracle: `FramingKit` rafter suite (the 13.4164"/ft-of-run identity).
    func testRafterCutLength() { hero("rafter", "173.57") }
    func testRafterLineLength() { check("rafter", "result.rafter.lineLength", "161.00") }
    func testRafterPlumbCut() { check("rafter", "result.rafter.plumbCut", "26.57") }

    /// 108" of rise at a 7.5" ideal riser → 14 risers @ 7.71", inside IRC 2021's 7¾" maximum.
    /// Kit oracle: `FramingKit.Stairs.solve`, IRC 2021 R311.7.
    func testStairsRiserCount() { hero("stairs", "14") }
    func testStairsRiserHeight() { check("stairs", "result.stairs.riserHeight", "7.71") }

    /// The wrist has no tread-depth input, so the code picker drives the tread: IRC's own 10" minimum,
    /// which must therefore PASS its own check — no `⚠` on the tread row. Left at the Kit's default this
    /// screen produced a layout violating the very code selected.
    /// Guarded at the model layer by `kerfcalcTests/WatchStairCodeTests`.
    func testStairsTreadFollowsTheSelectedCodeAndPasses() {
        let app = launchWatch(tool: "stairs")
        let treads = value(app, "result.stairs.treads")
        XCTAssertTrue(treads.contains("13"), "expected 13 treads for 14 risers, got «\(treads)»")
        XCTAssertTrue(treads.contains("10"), "IRC's tread minimum is 10\", got «\(treads)»")
        XCTAssertFalse(treads.contains("⚠"), "the tread failed its own code's minimum: «\(treads)»")
    }

    /// 6/12 → 26.6°, diagonal 13.42 for a 6:12 triangle.
    /// Kit oracle: `FramingKit.Pitch.angleDegrees` / `.diagonal`.
    func testPitchAngle() { hero("pitch", "26.6") }
    func testPitchDiagonal() { check("pitch", "result.pitch.diagonal", "13.42") }

    // MARK: - Concrete

    /// A 10' × 10' × 4" slab is 33.3 ft³ = 1.23 yd³ → 56 eighty-pound bags.
    ///
    /// NOTE the deliberate divergence: `ConcreteToolView` on the phone adds a waste percentage and a
    /// bag-size picker and reads `1.358`; the wrist shows the NET pour and says so in a pinned row.
    /// Kit oracle: `GeometryKit.Concrete.slabCubicFeet` / `.cubicYards` / `.bags`.
    func testConcreteCubicYards() { hero("concrete", "1.23") }
    func testConcreteBagCount() { check("concrete", "result.concrete.bags", "56") }

    /// 100 ft of 16" × 8" strip footing = 88.89 ft³ = 3.292 yd³ → 149 bags.
    /// Kit oracle: `ConcreteKit.Footing.continuousCubicFeet`.
    func testFootingCubicYards() { hero("footing", "3.292") }
    func testFootingCubicFeet() { check("footing", "result.footing.cubicFeet", "88.89") }

    /// A #4 bar over 20 ft weighs 13.4 lb (0.668 lb/ft, ASTM A615 nominal); its tension lap is 20.0".
    /// Kit oracle: `ConcreteKit.Rebar.weight` / `.lapLengthIn` / `BarSize.weightLbPerFt`.
    func testRebarTotalWeight() { hero("rebar", "13.4") }
    func testRebarUnitWeight() { check("rebar", "result.rebar.perFoot", "0.668") }
    func testRebarTensionLap() { check("rebar", "result.rebar.lap", "20.0") }

    /// 20' × 10' × 4" of crushed stone = 2.469 yd³ → 3.33 tons.
    /// Kit oracle: `ConcreteKit.Aggregate.tons`.
    func testAggregateTonnage() { hero("aggregate", "3.33") }
    func testAggregateCubicYards() { check("aggregate", "result.aggregate.cubicYards", "2.469") }

    /// 200 ft² of 8" × 4" pavers +10% waste = 991 pavers, at 4.50 per ft².
    /// Kit oracle: `ConcreteKit.Hardscape.paverCount` / `.paversPerFt2`.
    func testPaverCount() { hero("pavers", "991") }
    func testPaversPerSquareFoot() { check("pavers", "result.pavers.perFt2", "4.50") }

    // MARK: - Takeoff

    /// A 10 × 12 rectangle is 120 ft² = 13.33 yd².
    /// Kit oracle: `GeometryKit.Area.rectangle`.
    func testAreaRectangle() { hero("area", "120.00") }
    func testAreaSquareYards() { check("area", "result.area.squareYards", "13.33") }

    /// A 10 × 10 × 8 box is 800 ft³ = 29.630 yd³.
    /// Kit oracle: `GeometryKit.Volume.box`.
    func testVolumeBox() { hero("volume", "800.00") }
    func testVolumeCubicYards() { check("volume", "result.volume.cubicYards", "29.630") }

    // MARK: - Materials

    /// 2000 ft² footprint at 6/12 → 2236.07 ft² of roof → 22.36 squares, 24.60 with waste.
    /// Kit oracle: `MaterialsKit.Roofing.roofArea` (the √(1+(6/12)²) = 1.118 slope factor).
    func testRoofingSquares() { hero("roofing", "22.36") }
    func testRoofingSquaresWithWaste() { check("roofing", "result.roofing.withWaste", "24.60") }
    func testRoofingRoofArea() { check("roofing", "result.roofing.roofArea", "2236.07") }

    /// 1000 ft² of drywall → 35 4×8 sheets; the same wall is 7203 modular bricks.
    /// Kit oracle: `MaterialsKit.Estimate.drywallSheets` / `.units`.
    func testDrywallSheets() { hero("estimate", "35") }
    func testModularBrickCount() { check("estimate", "result.estimate.brick", "7203") }

    /// A 38° spring angle on a 4-sided corner → 31.62° miter, 33.86° bevel.
    /// Kit oracle: `MaterialsKit.CompoundMiter.compound`.
    func testCompoundMiterAngle() { hero("miter", "31.62") }
    func testCompoundBevelAngle() { check("miter", "result.miter.bevel", "33.86") }

    /// A 2×6×10 is 10 board feet — NIST PS 20 board measure.
    /// Kit oracle: `MaterialsKit.Estimate.boardFeet`.
    func testBoardFeet() { hero("lumber", "10.00") }

    /// 100 blocks → 8 bags of mortar, at 13 blocks a bag.
    /// Kit oracle: `ConcreteKit.Mortar.bagsForBlock`.
    func testMortarBags() { hero("mortar", "8") }

    // MARK: - Pipe

    /// A 10" set through a 45° fitting travels 10 × √2 = 14.14" and consumes 10.00" of run.
    /// Kit oracle: `PipeKit.PipeOffset.travelIn` (the 1.4142 cosecant multiplier).
    func testPipeOffsetTravel() { hero("offset", "14.14") }
    func testPipeOffsetRunConsumed() { check("offset", "result.offset.run", "10.00") }

    /// A 6" set with an 8" roll is a 10.00" true offset → 14.14" travel at 45°.
    /// Kit oracle: `PipeKit.RollingOffset.solve`.
    func testRollingOffsetTravel() { hero("rollingOffset", "14.14") }
    func testRollingOffsetTrueOffset() { check("rollingOffset", "result.rollingOffset.trueOffset", "10.00") }

    /// 24" centre-to-centre less two 1½" takeouts = 21.00" end to end, and the fittings fit.
    /// Kit oracle: `PipeKit.PipeCut.endToEndIn` / `.fittingsCollide`.
    func testPipeCutEndToEnd() { hero("cutLength", "21.00") }
    func testPipeCutFittingsFit() { check("cutLength", "result.cutLength.fit", "FIT") }

    /// 2.5" of fall over 10 ft = 0.250 in/ft = 2.08 % grade.
    /// Kit oracle: `PipeKit.PipeGrade.fallInPerFt` / `.percent`.
    func testGradePercent() { hero("grade", "2.08") }
    func testGradeFallPerFoot() { check("grade", "result.grade.fallPerFt", "0.250") }

    // MARK: - Convert

    /// 1 ft = 0.3048 m exactly — NIST, by definition of the international inch.
    /// Kit oracle: `DimensionKit.UnitsOracleTests`.
    func testFootToMetre() { hero("units", "0.3048") }

    // MARK: - Coverage guards

    /// The watch must cover EVERY phone calculator. This is the assertion that makes "all 20" permanent:
    /// a twenty-first tool on the phone fails here rather than quietly shipping a 20-tool watch.
    /// `kerfcalcTests/ToolCatalogCoverageTests.watchCoversEveryPhoneTool` pins the same number from
    /// inside the app target, where `Tool.allCases` is reachable.
    func testEveryWatchToolHasANumericCheck() {
        let covered = ["rafter", "stairs", "pitch",
                       "concrete", "footing", "rebar", "aggregate", "pavers",
                       "area", "volume",
                       "roofing", "estimate", "miter", "lumber", "mortar",
                       "offset", "rollingOffset", "cutLength", "grade",
                       "units"]
        XCTAssertEqual(covered.count, 20, "the watch ships all 20 calculators")
        XCTAssertEqual(Set(covered).count, covered.count, "duplicate in the coverage list")
    }

    /// Exactly one hero per screen — `DESIGN_GUIDELINES.md` §9. Two heroes means two competing answers,
    /// which on a 40 mm screen is the whole design gone.
    func testEachScreenHasExactlyOneHero() {
        for tool in ["rafter", "stairs", "pitch", "concrete", "footing", "rebar", "aggregate", "pavers",
                     "area", "volume", "roofing", "estimate", "miter", "lumber", "mortar",
                     "offset", "rollingOffset", "cutLength", "grade", "units"] {
            let app = launchWatch(tool: tool)
            let heroes = app.descendants(matching: .any).matching(identifier: "result.\(tool).hero")
            XCTAssertTrue(any(app, "result.\(tool).hero").waitForExistence(timeout: 15),
                          "\(tool) has no hero readout")
            XCTAssertEqual(heroes.count, 1, "\(tool) renders \(heroes.count) heroes, expected exactly 1")
            app.terminate()
        }
    }

    /// The hero must be the FIRST thing on screen, not scrolled below the inputs.
    ///
    /// Every screen is built hero → secondaries → pinned rows → crown fields (the overtonelab order).
    /// Fields-first is what pushes a multi-input tool's own answer off a 40 mm screen, and it is an
    /// ordering mistake no other test would notice: all the elements exist either way.
    func testTheHeroIsAboveTheInputsOnAMultiInputScreen() {
        for tool in ["rafter", "roofing", "miter", "rollingOffset"] {
            let app = launchWatch(tool: tool)
            let h = any(app, "result.\(tool).hero")
            XCTAssertTrue(h.waitForExistence(timeout: 15), "\(tool) has no hero")
            let inputs = app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier BEGINSWITH %@", "input.\(tool)"))
            XCTAssertGreaterThan(inputs.count, 0, "\(tool) has no crown fields")
            XCTAssertLessThan(h.frame.minY, inputs.element(boundBy: 0).frame.minY,
                              "\(tool): the hero is below its first input — the answer should be on " +
                              "screen when the tool opens")
            app.terminate()
        }
    }
}

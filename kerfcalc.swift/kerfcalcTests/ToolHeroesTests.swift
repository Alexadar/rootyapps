import Testing
import Foundation
@testable import KerfCalc

/// Unit tests for the mode-switch tools' hero (label + value + unit) mapping.
///
/// The Kit math these call is separately oracle-tested; here we lock down the *view wiring* — that each
/// mode picks the right function AND the right unit string. A copy-paste slip (e.g. showing "bags" for
/// grout, or paint gallons under the drywall tab) would fail here instead of reaching a worker.
/// Expected magnitudes derive from the tools' cited constants (Estimate/Mortar/Grout/Hardscape).
@Suite struct ToolHeroesTests {

    // MARK: Estimate — Drywall / Paint / Block
    @Test func estimateDrywall() {
        // 1000 ft² ÷ 32 ft²/sheet × 1.10 waste → ceil(34.375) = 35 sheets.
        let h = EstimateHero.hero(mode: 0, area: 1000, coats: 2)
        #expect(h.label == "Drywall sheets")
        #expect(h.value == "35")
        #expect(h.unit == "sheets")
    }

    @Test func estimatePaint() {
        // 1000 ft² × 2 coats ÷ 350 ft²/gal = 5.714… → "5.71" gal.
        let h = EstimateHero.hero(mode: 1, area: 1000, coats: 2)
        #expect(h.label == "Paint")
        #expect(h.value == "5.71")
        #expect(h.unit == "gal")
    }

    @Test func estimateBlock() {
        // 1000 ft² × 1.125 CMU/ft² × 1.05 waste → ceil(1181.25) = 1182 block.
        let h = EstimateHero.hero(mode: 2, area: 1000, coats: 2)
        #expect(h.label == "CMU block")
        #expect(h.value == "1182")
        #expect(h.unit == "block")
    }

    // MARK: Mortar — Block / Brick / Grout
    @Test func mortarBlock() {
        // 100 block ÷ 13 block/bag → ceil(7.69) = 8 bags (QUIKRETE #1136).
        let h = MortarHero.hero(mode: 0, count: 100, wallArea: 100)
        #expect(h.label == "Mortar bags")
        #expect(h.value == "8")
        #expect(h.unit == "bags")
    }

    @Test func mortarBrick() {
        // 1000 brick ÷ 37 brick/bag → ceil(27.03) = 28 bags.
        let h = MortarHero.hero(mode: 1, count: 1000, wallArea: 100)
        #expect(h.label == "Mortar bags")
        #expect(h.value == "28")
        #expect(h.unit == "bags")
    }

    @Test func mortarGrout() {
        // 100 ft² × 0.56 ft³/ft² ÷ 27 = 2.074… → "2.07" yd³ (NCMA TEK 3-2A).
        let h = MortarHero.hero(mode: 2, count: 100, wallArea: 100)
        #expect(h.label == "Grout")
        #expect(h.value == "2.07")
        #expect(h.unit == "yd³")
    }

    // MARK: Pavers — Pavers / Retaining wall
    @Test func paversPavers() {
        // 200 ft² × (144/32 = 4.5 pavers/ft²), waste 0 → exactly 900 pavers.
        // (waste=0 keeps this a clean mapping check; the waste-% arithmetic is oracle-tested in the Kit.)
        let h = PaversHero.hero(mode: 0, area: 200, pL: 8, pW: 4, waste: 0,
                                wallLenFt: 20, wallHIn: 24, blkL: 12, blkH: 6)
        #expect(h.label == "Pavers")
        #expect(h.value == "900")
        #expect(h.unit == "pavers")
    }

    @Test func paversWall() {
        // 20 ft ÷ 1 ft block = 20/course × ceil(24/6)=4 courses → 80 block.
        let h = PaversHero.hero(mode: 1, area: 200, pL: 8, pW: 4, waste: 10,
                                wallLenFt: 20, wallHIn: 24, blkL: 12, blkH: 6)
        #expect(h.label == "Wall block")
        #expect(h.value == "80")
        #expect(h.unit == "block")
    }
}

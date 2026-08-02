import Testing
import Foundation
@testable import MaterialsKit

/// Calc #8 (roofing/estimates) & #9 (compound miter — borrowed).
///
/// ORACLES:
///  • Roofing pitch multiplier — published slope-factor √(1+(rise/12)²): 6/12 = √1.25 = 1.11803.
///  • CMU 1.125/ft² — 1 ÷ (8/12·16/12) (NCMA/geometry). Modular brick 6.86/ft² — Brick Industry Assoc. rule.
///  • Compound crown — published crown tables: 38°→(31.62°,33.86°), 45°→(35.26°,30.00°).
///  • Waste %s are editable estimating conventions, explicitly NOT oracle-backed (not asserted here).
@Suite struct MaterialsOracle {

    @Test func guardsNoCrash() {
        #expect(Roofing.pitchMultiplier(riseIn12: 0) == 1)                 // flat → ×1
        #expect(Estimate.drywallSheets(areaFt2: 0) == 0)
        #expect(Estimate.paintGallons(areaFt2: 0) == 0)
        #expect(Estimate.drywallSheets(areaFt2: 1000, sheetFt2: 0) == 0)   // 0 sheet size → 0, no /0
    }

    @Test func roofingPitchMultiplier() {
        #expect(abs(Roofing.pitchMultiplier(riseIn12: 6) - 1.11803399) < 1e-6)   // √1.25 (published)
        #expect(abs(Roofing.pitchMultiplier(riseIn12: 12) - Double(2).squareRoot()) < 1e-9) // √2
        #expect(abs(Roofing.pitchMultiplier(riseIn12: 0) - 1) < 1e-12)           // flat → 1
        // 2000 ft² footprint at 6/12 → 2236.07 ft² → 22.36 squares (published example)
        #expect(abs(Roofing.roofArea(planAreaFt2: 2000, riseIn12: 6) - 2236.0680) < 1e-3)
        #expect(abs(Roofing.squares(roofAreaFt2: 2236.068) - 22.36068) < 1e-4)
    }

    @Test func masonryCoursing() {
        // CMU 8×16 face incl. mortar = (8/12)·(16/12) = 0.8889 ft²; 1/0.8889 = 1.125 (identity)
        #expect(abs(Estimate.cmu8x16PerFt2 - 1.125) < 1e-9)
        #expect(abs(1.0 / (8.0 / 12 * 16.0 / 12) - Estimate.cmu8x16PerFt2) < 1e-9)
        #expect(Estimate.modularBrickPerFt2 == 6.86)                 // BIA rule of thumb
    }

    @Test func drywallAndBoardFeet() {
        #expect(Estimate.drywallSheet4x8Ft2 == 32)                   // 4×8 (geometry)
        // 1000 ft² / 32 = 31.25 → ×1.10 waste = 34.375 → 35 sheets
        #expect(Estimate.drywallSheets(areaFt2: 1000) == 35)
        // board feet: 2"×6"×10' = 10 bf  (T·W·L/12 = 2·6·10/12)
        #expect(abs(Estimate.boardFeet(thicknessIn: 2, widthIn: 6, lengthFt: 10) - 10) < 1e-12)
        #expect(abs(Estimate.boardFeet(thicknessIn: 1, widthIn: 12, lengthIn: 12) - 1) < 1e-12)  // 144 in³ = 1 bf
    }

    @Test func paintCoverage() {
        // 1000 ft², 2 coats, 350 ft²/gal → 5.714 gal. (Coverage = paint-mfr TDS range 350–400.)
        #expect(abs(Estimate.paintGallons(areaFt2: 1000, coats: 2) - 5.7142857) < 1e-6)
        #expect(abs(Estimate.paintGallons(areaFt2: 350, coats: 1) - 1) < 1e-9)   // one gal covers 350 ft²
        #expect(Estimate.paintCoverageFt2PerGal == 350)
    }

    @Test func compoundCrownPublishedTables() {
        let s38 = CompoundMiter.compound(springDeg: 38, sides: 4)
        #expect(abs(s38.miter - 31.62) < 0.01)                       // published crown table
        #expect(abs(s38.bevel - 33.86) < 0.01)
        let s45 = CompoundMiter.compound(springDeg: 45, sides: 4)
        #expect(abs(s45.miter - 35.26) < 0.01)
        #expect(abs(s45.bevel - 30.00) < 0.01)
        #expect(abs(CompoundMiter.simpleMiterDeg(sides: 4) - 45) < 1e-12)   // square frame
        #expect(abs(CompoundMiter.simpleMiterDeg(sides: 8) - 22.5) < 1e-12) // octagon
    }
}

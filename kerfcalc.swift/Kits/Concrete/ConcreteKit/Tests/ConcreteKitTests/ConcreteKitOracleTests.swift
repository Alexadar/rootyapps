import Testing
import Foundation
@testable import ConcreteKit

/// Deepened concrete/masonry — rebar, footings, aggregate, mortar.
///
/// ORACLES:
///  • Rebar — **ASTM A615** nominal area & unit weight (CRSI). #4 = 0.20 in²/0.668 lb·ft⁻¹, #8 = 0.79/2.670, #9 = 1.00/3.400.
///  • Mortar — **QUIKRETE Mason Mix #1136** data sheet: 80-lb bag ≈ 13 block or 37 brick.
///  • Footings / aggregate volume — geometry identity (27 ft³/yd³); aggregate densities are cited typicals (editable).
@Suite struct ConcreteKitOracle {

    @Test func rebarTableASTM_A615() {
        #expect(BarSize.n4.areaIn2 == 0.20 && abs(BarSize.n4.weightLbPerFt - 0.668) < 1e-9)
        #expect(BarSize.n8.areaIn2 == 0.79 && abs(BarSize.n8.weightLbPerFt - 2.670) < 1e-9)
        #expect(BarSize.n9.areaIn2 == 1.00 && abs(BarSize.n9.weightLbPerFt - 3.400) < 1e-9)
        #expect(BarSize.n11.areaIn2 == 1.56 && abs(BarSize.n11.weightLbPerFt - 5.313) < 1e-9)
        #expect(BarSize.n3.diameterIn == 0.375 && BarSize.n8.diameterIn == 1.0)   // #N = N/8"
    }

    @Test func rebarWeightsAndCounts() {
        #expect(abs(Rebar.weight(.n5, lengthFt: 20) - 20.86) < 1e-9)     // 1.043 × 20
        #expect(Rebar.barCount(dimensionFt: 10, spacingIn: 12) == 11)     // 120/12 + 1
        #expect(Rebar.barCount(dimensionFt: 8, spacingIn: 16) == 7)       // 96/16 + 1
        // 10'×10' two-way mat @12" o.c.: 11 bars each way → 11·10 + 11·10 = 220 lf
        #expect(abs(Rebar.matLinealFeet(lengthFt: 10, widthFt: 10, spacingIn: 12) - 220) < 1e-9)
        #expect(abs(Rebar.matWeight(size: .n4, lengthFt: 10, widthFt: 10, spacingIn: 12) - 146.96) < 1e-9) // 220 × 0.668
    }

    @Test func footingVolumes() {
        // 100' × 16" × 8" continuous footing = 88.889 ft³ = 3.292 yd³  (identity)
        let ft3 = Footing.continuousCubicFeet(lengthFt: 100, widthIn: 16, depthIn: 8)
        #expect(abs(ft3 - 88.8888889) < 1e-6)
        #expect(abs(Footing.cubicYards(ft3) - 3.29218107) < 1e-6)
        // 24"×24"×12" pad = 4 ft³
        #expect(abs(Footing.padCubicFeet(lengthIn: 24, widthIn: 24, depthIn: 12) - 4) < 1e-9)
    }

    @Test func aggregateTonnage() {
        // 20' × 10' × 4" base = 2.4691 yd³; crushed stone @1.35 t/yd³ = 3.333 t  (cited density)
        let yd3 = Aggregate.cubicYards(lengthFt: 20, widthFt: 10, depthIn: 4)
        #expect(abs(yd3 - 2.4691358) < 1e-6)
        #expect(abs(Aggregate.tons(cubicYards: yd3, material: .crushedStone) - 3.3333333) < 1e-6)
        #expect(AggregateMaterial.roadBase.tonsPerCubicYard == 1.62)
    }

    @Test func guardsNoCrash() {
        #expect(Rebar.barCount(dimensionFt: 10, spacingIn: 0) == 0)        // spacing 0 → 0, no /0
        #expect(Rebar.weight(.n4, lengthFt: 0) == 0)                       // 0 length → 0 lb
        #expect(Mortar.bagsForBlock(0) == 0)
        #expect(Aggregate.cubicYards(lengthFt: 0, widthFt: 0, depthIn: 0) == 0)
        #expect(Hardscape.paversPerFt2(lengthIn: 0, widthIn: 0) == 0)     // 0 size → 0, no /0
    }

    @Test func mortarQuikrete() {
        #expect(Mortar.bagsForBlock(100) == 8)    // ceil(100/13)  (Quikrete #1136)
        #expect(Mortar.bagsForBrick(1000) == 28)   // ceil(1000/37)
        #expect(Mortar.blockPer80lbBag == 13 && Mortar.brickPer80lbBag == 37)
    }
}

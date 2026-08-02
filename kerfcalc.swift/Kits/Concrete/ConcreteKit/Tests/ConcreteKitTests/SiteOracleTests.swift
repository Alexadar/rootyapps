import Testing
import Foundation
@testable import ConcreteKit

/// Deepened concrete/masonry round 2 — ready-mix, control joints, grout, rebar laps, hardscape.
///
/// ORACLES:
///  • Ready-mix — NRMCA typical full truck ≈ 10 yd³.
///  • Control joints — ACI 360R: max spacing 24–36 × thickness(in) = 2–3 × thickness in feet.
///  • Grout — NCMA TEK 3-2A: fully-grouted 8" CMU ≈ 2.1 yd³ (56 ft³) per 100 ft² wall.
///  • Rebar lap — field rule 40×dₐ, min 12" (CRSI/ACI §25.5, NOT a design value); hook ≈ 12dₐ.
///  • Pavers — 4×8 paver = 4.5/ft² (geometry); waste % editable convention.
@Suite struct SiteOracle {

    @Test func readyMixTrucks() {
        #expect(ReadyMix.truckLoads(cubicYards: 25) == 3)        // ceil(25/10)
        #expect(ReadyMix.truckLoads(cubicYards: 10) == 1)
        #expect(ReadyMix.isShortLoad(cubicYards: 0.5))           // < 1 yd³ minimum
        #expect(!ReadyMix.isShortLoad(cubicYards: 2))
    }

    @Test func controlJointSpacing_ACI360() {
        let r = ControlJoints.spacingRangeFeet(thicknessIn: 4)
        #expect(r.min == 8 && r.max == 12)                       // 4" slab → 8–12 ft
        let r6 = ControlJoints.spacingRangeFeet(thicknessIn: 6)
        #expect(r6.min == 12 && r6.max == 18)                    // 6" slab → 12–18 ft
        #expect(ControlJoints.joints(lengthFt: 40, thicknessIn: 4) == 3)   // 40/12 → 4 panels → 3 joints
    }

    @Test func groutNCMA() {
        // 100 ft² fully-grouted 8" wall ≈ 56 ft³ ≈ 2.07 yd³ (NCMA published ≈ 2.1 yd³)
        #expect(abs(Grout.cubicFeet(wallAreaFt2: 100) - 56) < 1e-9)
        #expect(abs(Grout.cubicYards(wallAreaFt2: 100) - 2.074074) < 1e-5)
    }

    @Test func rebarLapsAndHooks() {
        #expect(abs(Rebar.lapLengthIn(.n4) - 20) < 1e-9)         // 40 × 0.5
        #expect(abs(Rebar.lapLengthIn(.n8) - 40) < 1e-9)         // 40 × 1.0
        #expect(abs(Rebar.lapLengthIn(.n3) - 15) < 1e-9)         // 40 × 0.375 = 15 (> 12 min)
        #expect(abs(Rebar.lapLengthIn(.n3, factor: 20) - 12) < 1e-9) // 20×0.375=7.5 → clamped to 12" min
        #expect(abs(Rebar.hookExtensionIn(.n5) - 7.5) < 1e-9)    // 12 × 0.625
    }

    @Test func hardscape() {
        #expect(abs(Hardscape.paversPerFt2(lengthIn: 8, widthIn: 4) - 4.5) < 1e-9)   // 144/32
        #expect(Hardscape.paverCount(areaFt2: 100, lengthIn: 8, widthIn: 4, wastePct: 5) == 473) // ceil(100·4.5·1.05)
        #expect(Hardscape.courses(wallHeightIn: 24, blockHeightIn: 6) == 4)
        #expect(Hardscape.wallBlockCount(wallLengthFt: 20, wallHeightIn: 24, blockLengthIn: 12, blockHeightIn: 6) == 80) // 20/course × 4
    }
}

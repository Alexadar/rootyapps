import Testing
import Foundation
@testable import GeometryKit

/// Calc #7 — concrete volume & bags.
///
/// ORACLE (published): QUIKRETE Concrete Mix #1101 data sheet — 80 lb bag yields 0.60 ft³;
/// 27 ft³ = 1 yd³ ⇒ a cubic yard needs 45 × 80 lb bags. (quikrete.com data_sheet-concrete mix 1101)
@Suite struct ConcreteOracle {

    @Test func bagsPerCubicYard() {
        // 1 yd³ = 27 ft³; 27 / 0.60 = 45 bags of 80 lb. (Quikrete published figure.)
        #expect(Concrete.bags(cubicFeet: 27, yieldFt3: Concrete.bag80lbYieldFt3) == 45)
        #expect(Concrete.bags(cubicFeet: 27, yieldFt3: Concrete.bag60lbYieldFt3) == 60)   // 27/0.45
        #expect(Concrete.bags(cubicFeet: 27, yieldFt3: Concrete.bag40lbYieldFt3) == 90)   // 27/0.30
    }

    @Test func slabVolume() {
        // 10' × 10' × 4" slab = 33.333 ft³ = 1.2346 yd³  (identity, geometry)
        let ft3 = Concrete.slabCubicFeet(lengthFt: 10, widthFt: 10, thicknessInches: 4)
        #expect(abs(ft3 - 33.33333333) < 1e-6)
        #expect(abs(Concrete.cubicYards(cubicFeet: ft3) - 1.234567901) < 1e-6)
        #expect(Concrete.bags(cubicFeet: ft3) == 56)             // ceil(33.33/0.6) = 56
    }

    @Test func wasteAllowance() {
        // 27 ft³ + 10 % = 29.7 ft³ = 1.1 yd³; bags on the waste-adjusted volume.
        #expect(abs(Concrete.withWaste(cubicFeet: 27, wastePct: 10) - 29.7) < 1e-9)
        #expect(abs(Concrete.cubicYards(cubicFeet: Concrete.withWaste(cubicFeet: 27, wastePct: 10)) - 1.1) < 1e-9)
        #expect(Concrete.bags(cubicFeet: Concrete.withWaste(cubicFeet: 27, wastePct: 10)) == 50) // ceil(29.7/0.6)
    }

    @Test func columnVolume() {
        // 12" dia × 48" sonotube: r = 0.5 ft, V = π·0.25·4 = 3.1416 ft³  (identity)
        #expect(abs(Concrete.columnCubicFeet(diameterInches: 12, heightInches: 48) - Double.pi) < 1e-6)
    }
}

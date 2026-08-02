import Testing
import Foundation
@testable import SolarIndexKit

/// ORACLE = SILSO / Wolf definition of the relative sunspot number, and the F10.7
///          solar-flux-unit convention.
///
///  • Sunspot number:  R = k·(10·g + s)   (Wolf 1848; Royal Observatory of Belgium / SILSO).
///    Worked values: g=1,s=1,k=1 ⇒ 11;  g=3,s=25,k=1 ⇒ 55;  g=5,s=40,k=0.6 ⇒ 54;
///    spotless Sun (g=0,s=0) ⇒ 0.
///  • F10.7: 1 sfu = 1e-22 W·m⁻²·Hz⁻¹ (solar flux unit at 2800 MHz / 10.7 cm).
@Suite("SolarIndex oracle — Wolf number & F10.7")
struct SolarIndexOracleTests {

    @Test func wolfFormulaWorkedValues() {
        #expect(SolarIndex.wolfNumber(groups: 1, spots: 1) == 11)
        #expect(SolarIndex.wolfNumber(groups: 3, spots: 25) == 55)
        #expect(SolarIndex.wolfNumber(groups: 0, spots: 0) == 0)
        #expect(SolarIndex.wolfNumber(groups: 5, spots: 40, k: 0.6) == 54)
    }

    @Test func wolfGroupWeightIsTen() {
        // One extra group adds exactly 10 to R (the "10·g" weighting).
        let base = SolarIndex.wolfNumber(groups: 2, spots: 30)
        let plusGroup = SolarIndex.wolfNumber(groups: 3, spots: 30)
        #expect(plusGroup - base == 10)
    }

    @Test func f107UnitConvention() {
        #expect(SolarIndex.sfuInWattsPerM2Hz == 1e-22)
        #expect(SolarIndex.f107InSI(150) == 150e-22)
    }

    @Test func activityBandsAreMonotonic() {
        // Sanity, not a published boundary: higher indices never map to a lower tier.
        #expect(SolarIndex.activity(sunspotNumber: 0) == "Spotless")
        #expect(SolarIndex.activity(sunspotNumber: 200) == "Very high")
        #expect(SolarIndex.f107Level(67) == "Very low")   // quiet-Sun floor
        #expect(SolarIndex.f107Level(250) == "Very high")
    }
}

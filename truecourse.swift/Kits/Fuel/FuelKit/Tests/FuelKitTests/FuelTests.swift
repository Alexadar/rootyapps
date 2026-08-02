import Testing
@testable import FuelKit

// Oracle = fuel arithmetic + standard avgas/Jet-A weights (FAA-H-8083-25 PHAK,
// "Aircraft Performance / Weight & Balance").
@Suite("Fuel — burn / endurance / range")
struct FuelTests {
    @Test func required()  { #expect(abs(Fuel.requiredGal(gph: 10, timeHr: 2.5) - 25) < 1e-9) }
    @Test func endurance() { #expect(abs(Fuel.enduranceHr(fuelGal: 40, gph: 10) - 4) < 1e-9) }
    @Test func burnRate()  { #expect(abs(Fuel.gph(fuelGal: 30, timeHr: 3) - 10) < 1e-9) }
    @Test func specRange() { #expect(abs(Fuel.specificRangeNmPerGal(gsKt: 120, gph: 12) - 10) < 1e-9) }
    @Test func weights() {
        #expect(abs(Fuel.avgasLbPerGal * 30 - 180) < 1e-9)   // 30 gal avgas = 180 lb
        #expect(abs(Fuel.jetALbPerGal - 6.7) < 1e-9)
    }
}

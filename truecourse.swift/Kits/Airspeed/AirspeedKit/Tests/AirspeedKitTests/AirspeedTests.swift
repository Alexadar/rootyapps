import Testing
import Foundation
@testable import AirspeedKit

// Oracle = ICAO / ISO 2533 International Standard Atmosphere and the standard E6B TAS
// relation TAS = CAS/√σ (FAA-H-8083-25 PHAK, https://www.faa.gov/regulations_policies/
// handbooks_manuals/aviation/phak). Speed of sound anchored to the ISA published value
// a₀ = 661.48 kt at 15 °C.
@Suite("Airspeed — ISA / E6B TAS")
struct AirspeedTests {

    @Test func tasEqualsCasAtStandardSeaLevel() {
        #expect(abs(Airspeed.tas(casKt: 120, pressureAltFt: 0, oatC: 15) - 120) < 1e-6)
    }

    @Test func tasGrowsWithAltitude() {
        // 100 KCAS at 10,000 ft pressure alt, ISA temp (−4.81 °C) → σ≈0.7386 → TAS≈116.36.
        let tas = Airspeed.tas(casKt: 100, pressureAltFt: 10000, oatC: -4.812)
        #expect(abs(tas - 116.36) < 0.1)
    }

    @Test func casIsInverseOfTas() {
        let tas = Airspeed.tas(casKt: 137, pressureAltFt: 8500, oatC: 5)
        #expect(abs(Airspeed.cas(tasKt: tas, pressureAltFt: 8500, oatC: 5) - 137) < 1e-6)
    }

    @Test func speedOfSoundMatchesISA() {
        #expect(abs(Airspeed.speedOfSoundKt(oatC: 15) - 661.48) < 0.01)          // sea-level ISA
        #expect(abs(Airspeed.speedOfSoundKt(oatC: -56.5) - 573.57) < 0.01)       // tropopause
    }

    @Test func machNumber() {
        // At the tropopause (−56.5 °C) Mach 1.0 ≈ 573.6 kt TAS.
        #expect(abs(Airspeed.mach(tasKt: 573.57, oatC: -56.5) - 1.0) < 0.001)
        #expect(abs(Airspeed.mach(tasKt: 480, oatC: -56.5) - 0.8369) < 0.001)
    }
}

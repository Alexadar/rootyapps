import Testing
import Foundation
@testable import SolarWindKit

/// ORACLE = published solar-wind / IMF conventions and their standard formulas.
///
///  • GSM sign convention: southward IMF Bz (Bz < 0) is geoeffective (reconnection).
///    Source: Dungey (1961) open-magnetosphere model; NOAA SWPC solar-wind product notes.
///  • Dynamic pressure:  P[nPa] = 1.6726e-6 · n[cm⁻³] · V[km/s]²  (proton-mass form).
///    Worked value: n=5, V=400 ⇒ 1.33808 nPa.
///  • Dawn–dusk electric field:  Ey[mV/m] = −V[km/s] · Bz[nT] · 1e-3.
///    Worked value: V=500, Bz=−10 ⇒ 5.0 mV/m.
@Suite("SolarWind oracle — IMF conventions & worked values")
struct SolarWindOracleTests {

    @Test func southwardIsGeoeffectiveSign() {
        #expect(SolarWind.isSouthward(bz: -0.1))
        #expect(!SolarWind.isSouthward(bz: 0))
        #expect(!SolarWind.isSouthward(bz: 8))
    }

    @Test func dynamicPressureWorkedValue() {
        #expect(abs(SolarWind.dynamicPressure(density: 5, speed: 400) - 1.33808) < 1e-5)
        // Doubling speed quadruples pressure (V² law).
        let p1 = SolarWind.dynamicPressure(density: 5, speed: 400)
        let p2 = SolarWind.dynamicPressure(density: 5, speed: 800)
        #expect(abs(p2 / p1 - 4.0) < 1e-9)
    }

    @Test func electricFieldWorkedValue() {
        #expect(abs(SolarWind.electricField(speed: 500, bz: -10) - 5.0) < 1e-9)
        // Northward IMF ⇒ negative Ey, and no southward (geoeffective) field.
        #expect(SolarWind.electricField(speed: 500, bz: 10) < 0)
        #expect(SolarWind.southwardField(speed: 500, bz: 10) == 0)
        #expect(abs(SolarWind.southwardField(speed: 500, bz: -10) - 5.0) < 1e-9)
    }

    @Test func couplingFlags() {
        let quiet = SolarWind.coupling(.init(bz: 3, speed: 380))
        #expect(!quiet.southward && !quiet.geoeffective)

        let storm = SolarWind.coupling(.init(bz: -12, speed: 600))
        #expect(storm.southward && storm.strongSouthward && storm.fastStream && storm.geoeffective)

        // Northward but fast: a high-speed stream is not geoeffective without southward Bz.
        let fastNorth = SolarWind.coupling(.init(bz: 6, speed: 650))
        #expect(fastNorth.fastStream && !fastNorth.geoeffective)
    }

    @Test func levelClassification() {
        #expect(SolarWind.level(bz: 2, speed: 380) == .calm)
        #expect(SolarWind.level(bz: -6, speed: 420) == .elevated)
        #expect(SolarWind.level(bz: -12, speed: 550) == .storming)
    }
}

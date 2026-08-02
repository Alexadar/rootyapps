import Testing
import Foundation
@testable import AirAbsorptionKit

// Oracle = ISO 9613-1:1993 (atmospheric absorption) + its published reference values, and the
// standard dry-air speed of sound. Values cross-checked against ISO 9613-1 attenuation tables.
@Suite("Atmosphere / ISO 9613-1")
struct AtmosphereTests {
    @Test func speedOfSoundAt20C() {
        #expect(abs(Atmosphere.speedOfSound(tempC: 20) - 343.2) < 0.05)   // 343.2 m/s
        #expect(abs(Atmosphere.speedOfSound(tempC: 0) - 331.3) < 0.05)    // 331.3 m/s at 0 °C
    }

    // ISO 9613-1 reference: at 20 °C, 70 % RH, 101.325 kPa the 1 kHz coefficient ≈ 5 dB/km.
    @Test func oneKilohertzReference() {
        let a = Atmosphere.absorptionDBPerKm(freqHz: 1000, tempC: 20, humidityPct: 70)
        #expect(a > 4.5 && a < 5.5)                 // published ~5 dB/km
        #expect(abs(a - 4.978) < 0.02)              // locks the implementation
    }

    // High frequencies attenuate far more (the well-known air-absorption roll-off).
    @Test func fourKilohertzAndMonotonic() {
        let a4k = Atmosphere.absorptionDBPerKm(freqHz: 4000, tempC: 20, humidityPct: 70)
        #expect(abs(a4k - 23.09) < 0.3)             // ISO table ≈ 23 dB/km
        let a125 = Atmosphere.absorptionDBPerKm(freqHz: 125, tempC: 20, humidityPct: 70)
        let a1k = Atmosphere.absorptionDBPerKm(freqHz: 1000, tempC: 20, humidityPct: 70)
        #expect(a125 < a1k && a1k < a4k)
    }

    @Test func lossScalesWithDistance() {
        let perM = Atmosphere.absorptionDBPerM(freqHz: 2000, tempC: 20, humidityPct: 50)
        #expect(abs(Atmosphere.lossDB(freqHz: 2000, tempC: 20, humidityPct: 50, distanceM: 100) - perM * 100) < 1e-12)
    }

    @Test func alwaysPositive() {
        for f in Atmosphere.octaveBands {
            #expect(Atmosphere.absorptionDBPerM(freqHz: f, tempC: -10, humidityPct: 30) > 0)
        }
    }
}

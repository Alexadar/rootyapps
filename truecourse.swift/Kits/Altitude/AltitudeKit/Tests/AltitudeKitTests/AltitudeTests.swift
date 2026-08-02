import Testing
import Foundation
@testable import AltitudeKit

// Oracle = ICAO / ISO 2533 International Standard Atmosphere table (pressure & density
// ratios) and FAA-H-8083-25 PHAK altitude rules (https://www.faa.gov/regulations_policies/
// handbooks_manuals/aviation/phak). Pressure/density ratios are asserted against the
// published ISA table; density altitude against the standard NWS closed form.
@Suite("Altitude — ISA standard atmosphere")
struct AltitudeTests {

    @Test func isaTemperatureLapse() {
        #expect(abs(Altitude.isaTempC(altitudeFt: 0) - 15) < 1e-9)
        #expect(abs(Altitude.isaTempC(altitudeFt: 10000) - -4.812) < 0.001)   // 15 − 19.812
    }

    @Test func isaPressureRatioMatchesTable() {
        #expect(abs(Altitude.isaPressureRatio(altitudeFt: 0) - 1.0) < 1e-9)
        #expect(abs(Altitude.isaPressureRatio(altitudeFt: 5000) - 0.8320) < 0.001)
        #expect(abs(Altitude.isaPressureRatio(altitudeFt: 10000) - 0.6877) < 0.001)
        #expect(abs(Altitude.isaPressureRatio(altitudeFt: 20000) - 0.4595) < 0.001)
    }

    @Test func isaDensityRatioMatchesTable() {
        #expect(abs(Altitude.isaDensityRatio(altitudeFt: 0) - 1.0) < 1e-9)
        #expect(abs(Altitude.isaDensityRatio(altitudeFt: 5000) - 0.8617) < 0.001)
        #expect(abs(Altitude.isaDensityRatio(altitudeFt: 10000) - 0.7385) < 0.001)
        #expect(abs(Altitude.isaDensityRatio(altitudeFt: 20000) - 0.5328) < 0.001)
    }

    @Test func pressureAltitude() {
        #expect(abs(Altitude.pressureAltitudeFt(indicatedAltFt: 5000, altimeterInHg: 29.92) - 5000) < 1e-6)
        #expect(abs(Altitude.pressureAltitudeFt(indicatedAltFt: 5000, altimeterInHg: 30.42) - 4500) < 1e-6)
        #expect(abs(Altitude.pressureAltitudeFt(indicatedAltFt: 5000, altimeterInHg: 29.42) - 5500) < 1e-6)
    }

    @Test func densityAltitude() {
        // Standard day at sea level → density altitude equals pressure altitude.
        #expect(abs(Altitude.densityAltitudeFt(pressureAltFt: 0, oatC: 15) - 0) < 0.5)
        // Hot & high worked example: PA 5,000 ft, OAT 30 °C (ISA+25) → ≈ 7,802 ft.
        #expect(abs(Altitude.densityAltitudeFt(pressureAltFt: 5000, oatC: 30) - 7802) < 5)
    }

    @Test func cloudBaseAndFreezingLevel() {
        #expect(abs(Altitude.cloudBaseFt(tempC: 25, dewpointC: 15) - 4000) < 1e-6)   // 10 °C spread
        #expect(abs(Altitude.freezingLevelFt(surfaceTempC: 15, elevationFt: 0) - 7571.17) < 0.5)
    }

    @Test func pivotalAltitude() {
        #expect(abs(Altitude.pivotalAltitudeFt(gsKt: 100) - 884.96) < 0.01)   // 100²/11.3
    }
}

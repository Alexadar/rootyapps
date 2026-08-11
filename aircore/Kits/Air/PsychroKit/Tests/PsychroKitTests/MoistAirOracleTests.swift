import Testing
import Foundation
@testable import PsychroKit

@Suite("Moist-air states against CoolProp")
struct MoistAirOracleTests {

    @Test("Every property of every reference state", arguments: Reference.states)
    func stateMatchesReference(_ ref: Reference.State) throws {
        let s = try MoistAir(dryBulb: ref.dryBulb, relativeHumidity: ref.relativeHumidity,
                             pressure: ref.pressure)
        let dewPoint = try #require(s.dewPoint)

        #expect(abs(s.wetBulb - ref.wetBulb) < Reference.Tolerance.wetBulb,
                "\(ref.name): wet bulb \(s.wetBulb) vs \(ref.wetBulb)")
        #expect(abs(dewPoint - ref.dewPoint) < Reference.Tolerance.dewPoint,
                "\(ref.name): dew point \(dewPoint) vs \(ref.dewPoint)")
        #expect(relativeError(s.humidityRatio, ref.humidityRatio)
                    < Reference.Tolerance.humidityRatioRelative,
                "\(ref.name): W \(s.humidityRatio) vs \(ref.humidityRatio)")
        #expect(abs(s.enthalpy - ref.enthalpy) < Reference.Tolerance.enthalpy,
                "\(ref.name): h \(s.enthalpy) vs \(ref.enthalpy)")
        #expect(relativeError(s.specificVolume, ref.specificVolume)
                    < Reference.Tolerance.specificVolumeRelative,
                "\(ref.name): v \(s.specificVolume) vs \(ref.specificVolume)")
        #expect(abs(s.relativeHumidity - ref.relativeHumidity) < 1e-9,
                "\(ref.name): RH must come back exactly as entered")
    }

    /// Altitude is where competitors are wrong, so it gets its own assertion rather than riding
    /// along inside the parameterised sweep: the same dry bulb and RH at Denver must produce a
    /// *materially* different state, not a rounding-level one.
    @Test func altitudeMovesTheStateByMoreThanRounding() throws {
        let sea = try MoistAir(dryBulb: 23.8888888889, relativeHumidity: 0.5,
                               pressure: Reference.seaLevel)
        let denver = try MoistAir(dryBulb: 23.8888888889, relativeHumidity: 0.5,
                                  pressure: Reference.denver)
        let mexico = try MoistAir(dryBulb: 23.8888888889, relativeHumidity: 0.5,
                                  pressure: Reference.mexicoCity)

        // Humidity ratio rises with elevation at fixed RH — 22 % more moisture in Denver.
        #expect(relativeError(denver.humidityRatio, sea.humidityRatio) > 0.20)
        #expect(mexico.humidityRatio > denver.humidityRatio)
        // Wet bulb falls: 0.46 °C at Denver, 0.64 °C at Mexico City.
        #expect(denver.wetBulb < sea.wetBulb - 0.4)
        #expect(mexico.wetBulb < denver.wetBulb)
        // Dew point is a property of the vapour pressure, so it barely moves.
        let denverDewPoint = try #require(denver.dewPoint)
        let seaDewPoint = try #require(sea.dewPoint)
        #expect(abs(denverDewPoint - seaDewPoint) < 0.01)
        // Specific volume rises by 22 % — the reason the 1.08 constant is wrong in Denver.
        #expect(relativeError(denver.specificVolume, sea.specificVolume) > 0.20)
    }

    /// The IP anchor points a technician would check against a printed chart.
    /// 75 °F / 50 % RH at sea level: WB 62.5 °F, DP 55.1 °F, h 28.1 Btu/lb, v 13.68 ft³/lb.
    @Test func publishedTableAnchorsInIP() throws {
        let c = { (f: Double) in (f - 32) / 1.8 }
        let s = try MoistAir(dryBulb: c(75), relativeHumidity: 0.5, pressure: Reference.seaLevel)
        let dewPointF = try #require(s.dewPoint) * 1.8 + 32

        #expect(abs(s.wetBulb * 1.8 + 32 - 62.5) < 0.1)
        #expect(abs(dewPointF - 55.1) < 0.1)
        // kJ/kg dry air → Btu/lb dry air. The scale factor is 2.326, but the two unit systems
        // put their enthalpy zero in different places — 0 °C in SI, 0 °F in IP — so the datum
        // offset 0.240 × 32 = 7.68 Btu/lb is part of the conversion. Dropping it is a 27 % error
        // at room temperature, and it is the kind of mistake a plain "× 2.326" helper invites.
        #expect(abs(s.enthalpy / 2.326 + 0.240 * 32 - 28.1) < 0.05)
        #expect(abs(s.specificVolume / 0.0624279606 - 13.68) < 0.02) // m³/kg → ft³/lb
        // Humidity ratio: the chart says 64.9 gr/lb, the ideal-gas relations say 64.65 —
        // the enhancement factor, and the whole of it.
        let grainsPerPound = s.humidityRatio * 7000
        #expect(abs(grainsPerPound - 64.9) < 0.4)
    }

    @Test func saturatedAirHasEqualDryWetAndDewPoint() throws {
        for t in [-10.0, 0.0, 15.5555555556, 35.0] {
            let s = try MoistAir(dryBulb: t, relativeHumidity: 1.0, pressure: Reference.seaLevel)
            let dewPoint = try #require(s.dewPoint)
            #expect(abs(s.wetBulb - t) < 1e-6, "wet bulb at saturation, \(t) °C")
            #expect(abs(dewPoint - t) < 1e-6, "dew point at saturation, \(t) °C")
            #expect(s.isSaturated)
            #expect(abs(s.degreeOfSaturation - 1) < 1e-9)
        }
    }

    @Test func perfectlyDryAirHasNoDewPoint() throws {
        let s = try MoistAir(dryBulb: 20, relativeHumidity: 0, pressure: Reference.seaLevel)
        #expect(s.dewPoint == nil, "0 % RH has no dew point — it must be absent, not a sentinel")
        #expect(s.humidityRatio == 0)
        // Bone-dry air still has a wet bulb; CoolProp puts it at 5.810 °C.
        #expect(abs(s.wetBulb - 5.810) < 0.05, "got \(s.wetBulb) °C")
    }

    /// Density is what HeatKit and DuctKit consume, so it is asserted here rather than trusted.
    @Test func densityMatchesStandardAir() throws {
        // "Standard air" in the HVAC trade: 0.075 lb/ft³ = 1.2015 kg/m³, ≈ 20 °C dry at sea level.
        let s = try MoistAir(dryBulb: 20, relativeHumidity: 0, pressure: Reference.seaLevel)
        #expect(abs(s.density - 1.2041) < 0.005, "got \(s.density) kg/m³")
    }

    @Test func statesRoundTripThroughCodable() throws {
        let s = try MoistAir(dryBulb: 23.8888888889, relativeHumidity: 0.5,
                             pressure: Reference.seaLevel)
        let back = try JSONDecoder().decode(MoistAir.self, from: JSONEncoder().encode(s))
        #expect(back == s, "state restoration after backgrounding depends on this")
    }
}

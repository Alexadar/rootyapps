import Testing
import Foundation
@testable import PsychroKit

@Suite("Adiabatic mixing")
struct AirMixingTests {

    static let cfmToCubicMetresPerSecond = 0.00047194745

    static func stream(dryBulbF: Double, rh: Double, cfm: Double,
                       pressure: Double) throws -> AirMixing.Stream {
        AirMixing.Stream(
            state: try MoistAir(dryBulb: (dryBulbF - 32) / 1.8, relativeHumidity: rh,
                                pressure: pressure),
            volumeFlow: cfm * cfmToCubicMetresPerSecond)
    }

    /// Mass-weighted mixing, computed independently from CoolProp state properties.
    /// 7,500 CFM return at 75 °F / 50 % against 2,500 CFM outdoor at 95 °F / 40 %, sea level.
    @Test func summerMixMatchesReference() throws {
        let mixed = try AirMixing.mix(
            Self.stream(dryBulbF: 75, rh: 0.5, cfm: 7500, pressure: Reference.seaLevel),
            Self.stream(dryBulbF: 95, rh: 0.4, cfm: 2500, pressure: Reference.seaLevel))

        #expect(abs(mixed.dryBulb - 26.593183) < 0.01, "got \(mixed.dryBulb) °C")
        #expect(relativeError(mixed.humidityRatio, 0.010419341) < 1e-4)
        #expect(abs(mixed.enthalpy - 53.326890) < 0.01)
    }

    /// Winter outdoor air is where CFM-weighting goes visibly wrong: the two streams differ in
    /// density by 11 %, so the shortcut and the correct answer separate by a readable margin.
    @Test func winterMixIsMassWeightedNotVolumeWeighted() throws {
        let ret = try Self.stream(dryBulbF: 75, rh: 0.5, cfm: 7500, pressure: Reference.seaLevel)
        let outdoor = try Self.stream(dryBulbF: 20, rh: 0.6, cfm: 2500,
                                      pressure: Reference.seaLevel)
        let mixed = try AirMixing.mix(ret, outdoor)

        #expect(abs(mixed.dryBulb - 15.622742) < 0.01, "got \(mixed.dryBulb) °C")
        #expect(relativeError(mixed.humidityRatio, 0.007061805) < 1e-4)

        // What CFM-weighting would have said, and how far off it is.
        let byVolume = (ret.state.dryBulb * 7500 + outdoor.state.dryBulb * 2500) / 10000
        // If this margin ever falls below the display precision the test has stopped proving
        // anything — the whole point is that the shortcut is visibly, not theoretically, wrong.
        #expect(abs(byVolume - mixed.dryBulb) > 0.3,
                "the shortcut differs by only \(abs(byVolume - mixed.dryBulb)) °C")
    }

    @Test func mixingHoldsAtAltitude() throws {
        let mixed = try AirMixing.mix(
            Self.stream(dryBulbF: 75, rh: 0.5, cfm: 7500, pressure: Reference.denver),
            Self.stream(dryBulbF: 95, rh: 0.4, cfm: 2500, pressure: Reference.denver))
        #expect(abs(mixed.dryBulb - 26.593679) < 0.01)
        #expect(relativeError(mixed.humidityRatio, 0.012700220) < 1e-4)
    }

    /// The mixed point must land on the straight line joining the two states on the chart, at the
    /// mass-flow ratio. This is the property the chart draws, so it is asserted, not assumed.
    @Test func mixedPointLiesOnTheProcessLine() throws {
        let a = try Self.stream(dryBulbF: 75, rh: 0.5, cfm: 7500, pressure: Reference.seaLevel)
        let b = try Self.stream(dryBulbF: 95, rh: 0.4, cfm: 2500, pressure: Reference.seaLevel)
        let mixed = try AirMixing.mix(a, b)
        let fractionB = AirMixing.massFraction(of: b, in: [a, b])

        let expectedW = a.state.humidityRatio * (1 - fractionB) + b.state.humidityRatio * fractionB
        let expectedH = a.state.enthalpy * (1 - fractionB) + b.state.enthalpy * fractionB
        #expect(relativeError(mixed.humidityRatio, expectedW) < 1e-12)
        #expect(relativeError(mixed.enthalpy, expectedH) < 1e-12)
        #expect(abs(fractionB - 0.2418) < 0.001,
                "2,500 of 10,000 CFM is 25 % by volume but \(fractionB * 100) % by mass")
    }

    @Test func mixingOneStreamWithNothingReturnsThatStream() throws {
        let a = try Self.stream(dryBulbF: 75, rh: 0.5, cfm: 7500, pressure: Reference.seaLevel)
        let none = AirMixing.Stream(state: a.state, volumeFlow: 0)
        let mixed = try AirMixing.mix(a, none)
        #expect(abs(mixed.dryBulb - a.state.dryBulb) < 1e-9)
        #expect(abs(mixed.humidityRatio - a.state.humidityRatio) < 1e-12)
    }

    /// Two cool, humid streams can mix to fog. That is a real answer and it must arrive as an
    /// error the UI can name, not as a state clamped back onto the saturation curve.
    @Test func mixingToFogFailsLoudly() throws {
        let a = AirMixing.Stream(
            state: try MoistAir(dryBulb: 35, relativeHumidity: 1.0, pressure: Reference.seaLevel),
            volumeFlow: 1)
        let b = AirMixing.Stream(
            state: try MoistAir(dryBulb: 5, relativeHumidity: 1.0, pressure: Reference.seaLevel),
            volumeFlow: 1)
        #expect(throws: (any Error).self) { try AirMixing.mix(a, b) }
    }

    @Test func refusesStreamsAtDifferentPressures() throws {
        let a = try Self.stream(dryBulbF: 75, rh: 0.5, cfm: 7500, pressure: Reference.seaLevel)
        let b = try Self.stream(dryBulbF: 95, rh: 0.4, cfm: 2500, pressure: Reference.denver)
        #expect(throws: (any Error).self) { try AirMixing.mix(a, b) }
    }

    @Test func refusesNegativeAndEmptyFlows() throws {
        let a = try Self.stream(dryBulbF: 75, rh: 0.5, cfm: 7500, pressure: Reference.seaLevel)
        let negative = AirMixing.Stream(state: a.state, volumeFlow: -1)
        #expect(throws: (any Error).self) { try AirMixing.mix(a, negative) }
        #expect(throws: (any Error).self) { try AirMixing.mix([]) }
    }
}

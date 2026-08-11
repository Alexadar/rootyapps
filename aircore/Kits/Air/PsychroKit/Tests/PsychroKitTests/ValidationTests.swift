import Testing
import Foundation
@testable import PsychroKit

/// Invalid input must fail loudly. A calculator that answers an impossible question with a
/// plausible number is the one failure mode a technician cannot detect in the field.
@Suite("Invalid input fails loudly")
struct ValidationTests {

    @Test func rejectsImpossibleRelativeHumidity() {
        #expect(throws: PsychroError.relativeHumidityOutOfRange(1.5)) {
            try MoistAir(dryBulb: 20, relativeHumidity: 1.5, pressure: Reference.seaLevel)
        }
        #expect(throws: PsychroError.relativeHumidityOutOfRange(-0.1)) {
            try MoistAir(dryBulb: 20, relativeHumidity: -0.1, pressure: Reference.seaLevel)
        }
    }

    @Test func rejectsImpossiblePressure() {
        for p in [0.0, -101_325, 5_000, 500_000] {
            #expect(throws: PsychroError.pressureOutOfRange(p)) {
                try MoistAir(dryBulb: 20, relativeHumidity: 0.5, pressure: p)
            }
        }
    }

    @Test func rejectsTemperaturesOutsideTheCorrelation() {
        #expect(throws: PsychroError.temperatureOutOfRange(300)) {
            try MoistAir(dryBulb: 300, relativeHumidity: 0.5, pressure: Reference.seaLevel)
        }
        #expect(throws: PsychroError.temperatureOutOfRange(-120)) {
            try MoistAir(dryBulb: -120, relativeHumidity: 0.5, pressure: Reference.seaLevel)
        }
    }

    /// Wet bulb above dry bulb, and dew point above dry bulb, are the two mistakes a user makes
    /// by typing into the wrong field. Both describe fog, and neither may quietly return a state.
    @Test func rejectsMoistureAboveSaturation() throws {
        #expect(throws: (any Error).self) {
            try MoistAir.solve(.dryBulb(20), .wetBulb(25), pressure: Reference.seaLevel)
        }
        #expect(throws: (any Error).self) {
            try MoistAir.solve(.dryBulb(20), .dewPoint(25), pressure: Reference.seaLevel)
        }
        let saturation = try Psychrometrics.saturationHumidityRatio(dryBulb: 20,
                                                                    pressure: Reference.seaLevel)
        #expect(throws: (any Error).self) {
            try MoistAir(dryBulb: 20, humidityRatio: saturation * 1.2,
                         pressure: Reference.seaLevel)
        }
    }

    @Test func rejectsNegativeMoisture() {
        #expect(throws: PsychroError.humidityRatioOutOfRange(-0.001)) {
            try MoistAir(dryBulb: 20, humidityRatio: -0.001, pressure: Reference.seaLevel)
        }
    }

    @Test func rejectsNotANumber() {
        #expect(throws: (any Error).self) {
            try MoistAir(dryBulb: .nan, relativeHumidity: 0.5, pressure: Reference.seaLevel)
        }
        #expect(throws: (any Error).self) {
            try MoistAir(dryBulb: 20, relativeHumidity: .nan, pressure: Reference.seaLevel)
        }
        #expect(throws: (any Error).self) {
            try MoistAir(dryBulb: 20, relativeHumidity: 0.5, pressure: .infinity)
        }
    }

    @Test func rejectsTwoKnownsOfTheSameKind() {
        #expect(throws: PsychroError.duplicateInput) {
            try MoistAir.solve(.dryBulb(20), .dryBulb(25), pressure: Reference.seaLevel)
        }
        #expect(throws: PsychroError.duplicateInput) {
            try MoistAir.solve(.relativeHumidity(0.4), .relativeHumidity(0.5),
                               pressure: Reference.seaLevel)
        }
    }

    @Test func rejectsTwoKnownsThatFixOnlyMoisture() {
        #expect(throws: PsychroError.underdetermined) {
            try MoistAir.solve(.dewPoint(10), .humidityRatio(0.0077),
                               pressure: Reference.seaLevel)
        }
    }

    /// Wet bulb and enthalpy trace near-coincident lines on the chart, so their intersection is
    /// not an answer: at 75 °F / 50 %, 0.05 °C of wet-bulb entry error moves the state 5.2 °C.
    /// Refusing the pair is the whole point — it is the one pair that would otherwise return a
    /// confident, badly wrong number from perfectly reasonable-looking input.
    @Test func rejectsTheDegenerateWetBulbEnthalpyPair() {
        #expect(throws: PsychroError.degeneratePair(.wetBulb, .enthalpy)) {
            try MoistAir.solve(.wetBulb(16.97), .enthalpy(47.54), pressure: Reference.seaLevel)
        }
        #expect(throws: PsychroError.degeneratePair(.enthalpy, .wetBulb)) {
            try MoistAir.solve(.enthalpy(47.54), .wetBulb(16.97), pressure: Reference.seaLevel)
        }
    }

    @Test func rejectsPairsThatDescribeNoState() {
        // An enthalpy far below anything reachable at any dry bulb in range at 100 % RH.
        #expect(throws: (any Error).self) {
            try MoistAir.solve(.relativeHumidity(1.0), .enthalpy(-500),
                               pressure: Reference.seaLevel)
        }
        #expect(throws: (any Error).self) {
            try MoistAir.solve(.relativeHumidity(0.5), .specificVolume(-1),
                               pressure: Reference.seaLevel)
        }
    }

    /// Errors carry the offending value, so the UI can say *what* is wrong rather than "invalid".
    @Test func errorsCarryTheOffendingValue() {
        do {
            _ = try MoistAir(dryBulb: 20, relativeHumidity: 1.5, pressure: Reference.seaLevel)
            Issue.record("expected a throw")
        } catch let error as PsychroError {
            #expect(error == .relativeHumidityOutOfRange(1.5))
            #expect(error.description.contains("1.5"))
        } catch {
            Issue.record("wrong error type: \(error)")
        }
    }
}

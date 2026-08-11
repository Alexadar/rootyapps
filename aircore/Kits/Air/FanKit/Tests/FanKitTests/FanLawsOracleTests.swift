import Testing
import Foundation
@testable import FanKit

/// The affinity laws are exact algebra, so the oracle is exact algebra: worked cases computed by
/// hand, and the defining proportionalities asserted as identities rather than approximations.
@Suite("Fan affinity laws")
struct FanLawsOracleTests {

    /// The textbook worked case: 2,000 CFM at 1,150 RPM and 1.5 BHP, sped up to 1,400 RPM.
    /// Q × 1.217391 = 2434.783; P × 1.482042; W × 1.804225 → 2.706337 BHP.
    @Test func workedCase() throws {
        let ratio = 1400.0 / 1150.0
        #expect(abs(try FanLaws.flow(2000, fromSpeed: 1150, toSpeed: 1400) - 2000 * ratio) < 1e-12)
        #expect(abs(try FanLaws.flow(2000, fromSpeed: 1150, toSpeed: 1400) - 2434.7826087) < 1e-6)

        let pressure = try FanLaws.pressure(1.0, fromSpeed: 1150, toSpeed: 1400,
                                            fromDensity: 1.2, toDensity: 1.2)
        #expect(abs(pressure - 1.4820416) < 1e-6)

        let power = try FanLaws.power(1.5, fromSpeed: 1150, toSpeed: 1400,
                                      fromDensity: 1.2, toDensity: 1.2)
        #expect(abs(power - 2.7063368) < 1e-6)
    }

    /// The exponents are the whole content of the laws, so they are asserted as exponents.
    @Test("Speed exponents are exactly 1, 2 and 3", arguments: [0.5, 0.8, 1.0, 1.25, 2.0, 3.0])
    func exponents(_ ratio: Double) throws {
        let n1 = 1000.0, n2 = 1000.0 * ratio
        let q = try FanLaws.flow(1, fromSpeed: n1, toSpeed: n2)
        let p = try FanLaws.pressure(1, fromSpeed: n1, toSpeed: n2, fromDensity: 1, toDensity: 1)
        let w = try FanLaws.power(1, fromSpeed: n1, toSpeed: n2, fromDensity: 1, toDensity: 1)

        #expect(abs(q - ratio) < 1e-12)
        #expect(abs(p - ratio * ratio) < 1e-12)
        #expect(abs(w - ratio * ratio * ratio) < 1e-12)
        // and the relations between them
        #expect(abs(p - q * q) < 1e-12)
        #expect(abs(w - q * p) < 1e-12)
    }

    /// **The trap.** Take a fan to Denver: it moves the same air volume, and develops 18 % less
    /// pressure on 18 % less power. A tool that scales all three — or none — is wrong.
    @Test func densityMovesPressureAndPowerButNotFlow() throws {
        let seaLevel = 1.2014, denver = 1.2014 * 0.823296

        let flow = try FanLaws.flow(2000, fromSpeed: 1150, toSpeed: 1150)
        #expect(abs(flow - 2000) < 1e-12, "a fan is a constant-volume machine")

        let pressure = try FanLaws.pressureAtDensity(1.0, fromDensity: seaLevel, toDensity: denver)
        #expect(abs(pressure - 0.823296) < 1e-9)

        let power = try FanLaws.powerAtDensity(1.5, fromDensity: seaLevel, toDensity: denver)
        #expect(abs(power - 1.5 * 0.823296) < 1e-9)
    }

    /// The other direction of the same trap: a motor sized on thin air overloads in dense air.
    /// Winter start-up at −18 °C is about 15 % denser than the 20 °C selection point.
    @Test func denserAirDrawsMorePower() throws {
        let selection = 1.2014, coldStart = 1.2014 * 1.15
        let power = try FanLaws.powerAtDensity(5.0, fromDensity: selection, toDensity: coldStart)
        #expect(power > 5.0)
        #expect(abs(power - 5.75) < 1e-9)
    }

    @Test func speedAndDensityCompose() throws {
        // Applying speed and density together must equal applying them one after the other.
        let both = try FanLaws.power(1.5, fromSpeed: 1150, toSpeed: 1400,
                                     fromDensity: 1.2014, toDensity: 0.99)
        let stepwise = try FanLaws.powerAtDensity(
            try FanLaws.power(1.5, fromSpeed: 1150, toSpeed: 1400,
                              fromDensity: 1.2014, toDensity: 1.2014),
            fromDensity: 1.2014, toDensity: 0.99)
        #expect(abs(both - stepwise) < 1e-12)
    }

    @Test func speedForATargetFlowIsTheInverseOfTheFlowLaw() throws {
        let speed = try FanLaws.speed(forFlow: 2400, fromFlow: 2000, atSpeed: 1150)
        #expect(abs(speed - 1380) < 1e-9)
        #expect(abs(try FanLaws.flow(2000, fromSpeed: 1150, toSpeed: speed) - 2400) < 1e-9)
    }

    @Test func identityWhenNothingChanges() throws {
        #expect(abs(try FanLaws.flow(1234, fromSpeed: 900, toSpeed: 900) - 1234) < 1e-12)
        #expect(abs(try FanLaws.pressure(2.5, fromSpeed: 900, toSpeed: 900,
                                         fromDensity: 1.1, toDensity: 1.1) - 2.5) < 1e-12)
        #expect(abs(try FanLaws.power(7.5, fromSpeed: 900, toSpeed: 900,
                                      fromDensity: 1.1, toDensity: 1.1) - 7.5) < 1e-12)
    }
}

@Suite("Invalid fan input fails loudly")
struct FanValidationTests {

    @Test func zeroOriginalSpeedIsNotSomethingToScaleFrom() {
        #expect(throws: FanError.indeterminate(name: "original speed")) {
            try FanLaws.flow(2000, fromSpeed: 0, toSpeed: 1400)
        }
        #expect(throws: FanError.indeterminate(name: "original density")) {
            try FanLaws.pressureAtDensity(1, fromDensity: 0, toDensity: 1.2)
        }
        #expect(throws: FanError.indeterminate(name: "flow")) {
            try FanLaws.speed(forFlow: 2400, fromFlow: 0, atSpeed: 1150)
        }
    }

    @Test func rejectsNegativeAndNonFiniteQuantities() {
        #expect(throws: FanError.invalidInput(name: "flow", value: -1)) {
            try FanLaws.flow(-1, fromSpeed: 1150, toSpeed: 1400)
        }
        #expect(throws: FanError.invalidInput(name: "new speed", value: -1400)) {
            try FanLaws.flow(2000, fromSpeed: 1150, toSpeed: -1400)
        }
        #expect(throws: FanError.invalidInput(name: "new density", value: 0)) {
            try FanLaws.pressureAtDensity(1, fromDensity: 1.2, toDensity: 0)
        }
        #expect(throws: (any Error).self) {
            try FanLaws.flow(.nan, fromSpeed: 1150, toSpeed: 1400)
        }
        #expect(throws: (any Error).self) {
            try FanLaws.power(1.5, fromSpeed: 1150, toSpeed: .infinity,
                              fromDensity: 1.2, toDensity: 1.2)
        }
    }

    /// A fan slowed to a stop moves no air, develops no pressure and draws no shaft power. That is
    /// a legitimate answer, not an error — only scaling *from* zero is impossible.
    @Test func zeroTargetSpeedIsAValidAnswer() throws {
        #expect(try FanLaws.flow(2000, fromSpeed: 1150, toSpeed: 0) == 0)
        #expect(try FanLaws.power(1.5, fromSpeed: 1150, toSpeed: 0,
                                  fromDensity: 1.2, toDensity: 1.2) == 0)
    }
}

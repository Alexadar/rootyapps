import XCTest
@testable import AirsideKit

/// Oracle-style checks — every displayed number must be one a Kit can prove.
final class AirsideKitTests: XCTestCase {

    func testPsychroAtSeaLevel() {
        let s = Psychrometrics.solve(dryBulbF: 75, relHumidityPercent: 50, altitude: .seaLevel)
        XCTAssertEqual(s.wetBulb, 62.5, accuracy: 1.0)
        XCTAssertEqual(s.dewPoint, 55.1, accuracy: 1.0)
        XCTAssertEqual(s.enthalpy, 28.1, accuracy: 1.0)
    }

    func testAltitudeShiftsSensibleConstant() {
        XCTAssertEqual(Altitude.seaLevel.sensibleConstant, 1.08, accuracy: 0.01)
        XCTAssertLessThan(Altitude.denver.sensibleConstant, 1.0) // ~0.89 at 5,280 ft
    }

    func testDuctWhistleFlag() {
        let quiet = DuctSizing.size(cfm: 850, frictionPer100ft: 0.08)
        XCTAssertFalse(quiet.whistles)
        let loud = DuctSizing.size(cfm: 850, frictionPer100ft: 0.30)
        XCTAssertTrue(loud.whistles)
    }

    func testFanLaws() {
        XCTAssertEqual(FanLaws.flow(from: 2000, n1: 1150, n2: 1400), 2434.8, accuracy: 1)
        XCTAssertEqual(FanLaws.brakeHorsepower(from: 1.5, n1: 1150, n2: 1400), 2.71, accuracy: 0.05)
    }
}

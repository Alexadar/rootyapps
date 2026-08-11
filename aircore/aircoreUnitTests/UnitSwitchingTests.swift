import XCTest
import UnitsKit
@testable import AirCore

/// # The IP ⇄ SI axis
///
/// The Kits are SI and the screen is whatever the user picked, so `Quantity` is the seam between
/// them — and it is a seam with 22 quantities and two systems on it, every one of which is a place
/// a wrong conversion could hide behind a plausible number.
///
/// A dead toggle has shipped in this repository before, because the tests only ever saw one side
/// of it. So these walk **every quantity in both systems, in both directions**, rather than
/// spot-checking the ones that seemed likely.
final class UnitSwitchingTests: XCTestCase {

    func testEveryQuantityRoundTripsInBothSystems() {
        for quantity in Quantity.allCases {
            for system in UnitSystem.allCases {
                for value in [-40.0, 0, 0.5, 1, 37.25, 1000, 98_765.4] {
                    let si = quantity.si(display: value, in: system)
                    let back = quantity.display(si: si, in: system)
                    XCTAssertEqual(back, value, accuracy: 1e-9 + 1e-12 * abs(value),
                                   "\(quantity) in \(system) turned \(value) into \(back)")
                }
            }
        }
    }

    /// Switching the unit system must not move the stored value. This is the whole promise of
    /// holding SI internally, and it is one careless `didSet` away from being false.
    func testSwitchingSystemsDoesNotMoveTheStoredValue() {
        for quantity in Quantity.allCases {
            let si = 12.345
            let asIP = quantity.display(si: si, in: .ip)
            let asSI = quantity.display(si: si, in: .si)
            XCTAssertEqual(quantity.si(display: asIP, in: .ip), si, accuracy: 1e-9)
            XCTAssertEqual(quantity.si(display: asSI, in: .si), si, accuracy: 1e-9)
        }
    }

    /// Every quantity must have a symbol and a spoken form in both systems. A blank one is a
    /// number on screen with no unit, which is not a result.
    func testEveryQuantityIsLabelledInBothSystems() {
        for quantity in Quantity.allCases where quantity != .dimensionless {
            for system in UnitSystem.allCases {
                XCTAssertFalse(quantity.symbol(system).isEmpty,
                               "\(quantity) has no symbol in \(system)")
                XCTAssertFalse(Fmt.spokenUnit(quantity, system).isEmpty,
                               "\(quantity) has no spoken unit in \(system)")
                XCTAssertFalse(Fmt.spokenUnit(quantity, system).contains("/"),
                               "\(quantity) spells a slash in \(system) — VoiceOver reads it aloud")
                XCTAssertFalse(Fmt.spokenUnit(quantity, system).contains("°"),
                               "\(quantity) spells a degree sign in \(system)")
            }
        }
    }

    /// The two quantities that carry a datum are the two that get it wrong. A reading and a
    /// difference are different conversions and must give different answers.
    func testDatumCarryingQuantitiesDifferFromTheirDifferences() {
        XCTAssertNotEqual(Quantity.temperature.si(display: 20, in: .ip),
                          Quantity.temperatureDifference.si(display: 20, in: .ip))
        XCTAssertEqual(Quantity.temperatureDifference.si(display: 18, in: .ip), 10, accuracy: 1e-12)
        XCTAssertEqual(Quantity.temperature.si(display: 32, in: .ip), 0, accuracy: 1e-12)

        XCTAssertNotEqual(Quantity.enthalpy.si(display: 28.1, in: .ip),
                          Quantity.enthalpyDifference.si(display: 28.1, in: .ip))
        // The datum gap is 17.88 kJ/kg, and it is 27 % of a room-temperature enthalpy.
        let gap = Quantity.enthalpyDifference.si(display: 28.1, in: .ip)
            - Quantity.enthalpy.si(display: 28.1, in: .ip)
        XCTAssertEqual(gap, 1.006 * 32 / 1.8, accuracy: 1e-9)
    }

    /// Published anchors, so a typo in a factor fails here rather than on a roof.
    func testKnownConversions() {
        XCTAssertEqual(Quantity.temperature.si(display: 75, in: .ip), 23.888888, accuracy: 1e-5)
        XCTAssertEqual(Quantity.airFlow.display(si: 0.4719474432, in: .ip), 1000, accuracy: 1e-6)
        XCTAssertEqual(Quantity.humidityRatio.display(si: 0.009277199, in: .ip), 64.94,
                       accuracy: 0.01)
        XCTAssertEqual(Quantity.airVelocity.display(si: 5.08, in: .ip), 1000, accuracy: 1e-9)
        XCTAssertEqual(Quantity.ductSize.display(si: 0.3556, in: .ip), 14, accuracy: 1e-9)
        XCTAssertEqual(Quantity.waterFlow.display(si: 40 * 6.30901964e-5, in: .ip), 40,
                       accuracy: 1e-9)
        XCTAssertEqual(Quantity.heatLoad.display(si: 3516.8528, in: .ip), 12_000, accuracy: 1)
        XCTAssertEqual(Quantity.elevation.display(si: 5280 * 0.3048, in: .ip), 5280, accuracy: 1e-9)
    }

    /// A comma-decimal locale types "23,5". Rejecting that makes the app unusable across most of
    /// Europe, and silently reading it as 235 would be worse.
    func testParsingAcceptsPlainNumbersAndRejectsRubbish() {
        XCTAssertEqual(Fmt.parse("75", .temperature, .ip)!, 23.888888, accuracy: 1e-5)
        XCTAssertEqual(Fmt.parse(" 75.5 ", .temperature, .ip)!, 24.166666, accuracy: 1e-5)
        XCTAssertNil(Fmt.parse("", .temperature, .ip), "an empty field is not zero")
        XCTAssertNil(Fmt.parse("abc", .temperature, .ip))
        XCTAssertNil(Fmt.parse("inf", .temperature, .ip), "infinity is not a temperature")
        XCTAssertNil(Fmt.parse("nan", .temperature, .ip))
    }

    /// Formatting must be stable: the same SI value formatted twice is the same string, and a
    /// non-finite value shows an em dash rather than "nan".
    func testFormattingIsStableAndNeverPrintsNaN() {
        XCTAssertEqual(Fmt.value(si: 23.8888888, .temperature, .ip),
                       Fmt.value(si: 23.8888888, .temperature, .ip))
        XCTAssertEqual(Fmt.number(.nan, decimals: 1), "—")
        XCTAssertEqual(Fmt.number(.infinity, decimals: 1), "—")
    }
}

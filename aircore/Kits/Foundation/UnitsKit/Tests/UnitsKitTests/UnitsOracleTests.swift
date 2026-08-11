import Testing
import Foundation
@testable import UnitsKit

/// Oracle: **NIST Special Publication 811**, Appendix B, plus the exact defining relations
/// (inch = 0.0254 m, pound = 0.45359237 kg, Btu_IT = 1055.05585262 J, gallon = 3.785411784 L).
/// Conversion factors are facts with published values, so these assertions are tight — anything
/// looser than 1e-9 relative here would be hiding a typo.
@Suite("Unit conversions against NIST SP 811")
struct UnitsOracleTests {

    static func expectExact(_ actual: Double, _ expected: Double,
                            _ what: Comment, tolerance: Double = 1e-9) {
        let error = expected == 0 ? abs(actual) : abs(actual - expected) / abs(expected)
        #expect(error < tolerance, what)
    }

    @Test func lengthAndVelocity() {
        Self.expectExact(Units.feet.toSI(1), 0.3048, "1 ft = 0.3048 m exactly")
        Self.expectExact(Units.inches.toSI(1), 0.0254, "1 in = 0.0254 m exactly")
        Self.expectExact(Units.feetPerMinute.toSI(1000), 5.08, "1000 fpm = 5.08 m/s")
        Self.expectExact(Units.feetPerSecond.toSI(5), 1.524, "5 ft/s = 1.524 m/s")
    }

    @Test func pressure() {
        Self.expectExact(Units.poundsPerSquareInch.toSI(1), 6894.757293168,
                         "1 psi = 6894.757293168 Pa", tolerance: 1e-10)
        Self.expectExact(Units.poundsPerSquareInch.fromSI(101_325), 14.6959487755,
                         "one standard atmosphere = 14.6959 psia", tolerance: 1e-8)
        Self.expectExact(Units.inchOfWaterGauge.toSI(1), 248.84, "1 in w.g. (60 °F) = 248.84 Pa")
        Self.expectExact(Units.inchOfMercury.fromSI(101_325), 29.9213, "1 atm = 29.92 inHg",
                         tolerance: 1e-5)
    }

    @Test func flow() {
        Self.expectExact(Units.cubicFeetPerMinute.toSI(1), 4.719474432e-4, "1 CFM in m³/s")
        Self.expectExact(Units.cubicFeetPerMinute.fromSI(Units.litresPerSecond.toSI(1000)),
                         2118.88, "1000 L/s = 2118.88 CFM", tolerance: 1e-5)
        Self.expectExact(Units.gallonsPerMinute.toSI(1), 6.30901964e-5, "1 GPM in m³/s")
    }

    @Test func moisture() {
        Self.expectExact(Units.grainsPerPoundDryAir.toSI(7000), 1.0, "7000 gr = 1 lb exactly")
        Self.expectExact(Units.grainsPerPoundDryAir.fromSI(0.009277199), 64.94039,
                         "0.009277 kg/kg = 64.94 gr/lb", tolerance: 1e-6)
        Self.expectExact(Units.gramsPerKilogramDryAir.fromSI(0.009277199), 9.277199, "kg/kg → g/kg")
    }

    @Test func powerAndEnergy() {
        Self.expectExact(Units.btuPerHour.toSI(1), 0.29307107017222, "1 Btu/h in W")
        Self.expectExact(Units.tonsOfRefrigeration.toSI(1), 3516.8528420667,
                         "1 ton = 12,000 Btu/h = 3516.85 W", tolerance: 1e-11)
        Self.expectExact(Units.btuPerHour.fromSI(Units.tonsOfRefrigeration.toSI(3)), 36_000,
                         "3 tons = 36,000 Btu/h", tolerance: 1e-10)
    }

    @Test func volumeAndDensity() {
        Self.expectExact(Units.cubicFeetPerPound.toSI(13.68), 0.8540145006816583,
                         "13.68 ft³/lb in m³/kg")
        Self.expectExact(Units.poundsPerCubicFoot.toSI(0.075), 1.2013847530470103,
                         "standard air 0.075 lb/ft³ = 1.2014 kg/m³")
    }

    @Test func waterHead() {
        // 1 ft of water at the 4 °C reference density = 2989.07 Pa.
        Self.expectExact(Units.footOfWater.toSI(1), 2989.0669, "1 ftH₂O in Pa", tolerance: 1e-7)
        // 10 ft of head per 100 ft of pipe is a 10 % gradient: 980.665 Pa/m.
        Self.expectExact(Units.footOfWaterPer100Feet.toSI(10), 980.665, "10 ft/100 ft in Pa/m")
        Self.expectExact(Units.kilopascalsPerMetre.fromSI(2000), 2.0, "2000 Pa/m = 2 kPa/m")
        // A foot of water per hundred feet is a hundredth of a foot of water per foot.
        Self.expectExact(Units.footOfWaterPer100Feet.factor * 100 * Units.metresPerFoot,
                         Units.footOfWater.factor, "the two water-head units must agree")
    }

    @Test func ductFrictionRate() {
        // 0.1 in w.g. per 100 ft — the friction rate a residential system is designed at.
        Self.expectExact(Units.inchesOfWaterPer100Feet.toSI(0.1), 0.8164041994750656,
                         "0.1 in w.g./100 ft in Pa/m")
    }
}

@Suite("Temperature carries a datum, differences do not")
struct TemperatureTests {

    @Test func absoluteReadings() {
        #expect(abs(Units.fahrenheit.toSI(32) - 0) < 1e-12)
        #expect(abs(Units.fahrenheit.toSI(212) - 100) < 1e-12)
        #expect(abs(Units.fahrenheit.toSI(75) - 23.888888888888) < 1e-9)
        #expect(abs(Units.fahrenheit.toSI(-40) - -40) < 1e-12, "the one place the scales meet")
    }

    /// A temperature *difference* has no datum. This is the distinction that turns a 20 °F coil
    /// ΔT into −6.7 °C instead of 11.1 °C, and it is one line of code away in either direction.
    @Test func differencesDropTheDatum() {
        #expect(abs(Units.fahrenheit.asDifference.toSI(20) - 11.1111111111) < 1e-9)
        #expect(abs(Units.fahrenheit.toSI(20) - -6.6666666667) < 1e-9)
        #expect(Units.fahrenheit.asDifference.toSI(20) != Units.fahrenheit.toSI(20))
        #expect(abs(Units.fahrenheit.asDifference.fromSI(10) - 18) < 1e-12,
                "a 10 K rise is an 18 °F rise")
    }
}

@Suite("Enthalpy: the datum offset that gets dropped")
struct EnthalpyDatumTests {

    /// 75 °F / 50 % RH at sea level: the chart says 28.1 Btu/lb, PsychroKit says 47.54 kJ/kg.
    @Test func matchesThePublishedChartValue() {
        let siValue = 47.5411
        #expect(abs(Units.btuPerPoundDryAir.fromSI(siValue) - 28.128) < 0.005)
    }

    /// The size of the mistake, asserted so it cannot be quietly reintroduced as "close enough".
    @Test func droppingTheOffsetIsATwentySevenPercentError() {
        let siValue = 47.5411
        let correct = Units.btuPerPoundDryAir.fromSI(siValue)
        let factorOnly = siValue / 2.326
        #expect(abs(correct - factorOnly - 7.6889271) < 1e-6)
        #expect(abs(correct - factorOnly) / correct > 0.27)
    }

    @Test func theScaleFactorIsExactlyTwoPointThreeTwoSix() {
        #expect(abs(Units.btuPerPoundDryAir.factor - 2.326) < 1e-12,
                "Btu_IT/lb → kJ/kg is exactly 2.326 by the definitions of the Btu and the pound")
    }

    /// A *difference* in enthalpy — what an air-side load is built from — carries no datum, and
    /// converts by the factor alone.
    @Test func enthalpyDifferencesUseTheFactorAlone() {
        let deltaSI = 10.0
        #expect(abs(Units.btuPerPoundDryAir.asDifference.fromSI(deltaSI) - 10 / 2.326) < 1e-12)
    }
}

@Suite("Switching units is free and reversible")
struct RoundTripTests {

    static let allConversions: [(String, Conversion)] = [
        ("fahrenheit", Units.fahrenheit), ("psi", Units.poundsPerSquareInch),
        ("inWG", Units.inchOfWaterGauge), ("inHg", Units.inchOfMercury),
        ("gr/lb", Units.grainsPerPoundDryAir), ("g/kg", Units.gramsPerKilogramDryAir),
        ("Btu/lb", Units.btuPerPoundDryAir), ("ft³/lb", Units.cubicFeetPerPound),
        ("lb/ft³", Units.poundsPerCubicFoot), ("CFM", Units.cubicFeetPerMinute),
        ("L/s", Units.litresPerSecond), ("GPM", Units.gallonsPerMinute),
        ("ft", Units.feet), ("in", Units.inches), ("mm", Units.millimetres),
        ("fpm", Units.feetPerMinute), ("Btu/h", Units.btuPerHour),
        ("ton", Units.tonsOfRefrigeration), ("in wg/100 ft", Units.inchesOfWaterPer100Feet),
        ("ftH₂O", Units.footOfWater), ("ft/100 ft", Units.footOfWaterPer100Feet),
        ("kPa/m", Units.kilopascalsPerMetre),
    ]

    /// The user must be able to flip IP ⇄ SI ⇄ IP and land on the number they typed. A conversion
    /// that loses a digit each way turns a unit toggle into a slow edit of the user's data.
    @Test("Every conversion round-trips", arguments: allConversions.map(\.1))
    func roundTrips(_ conversion: Conversion) {
        for value in [-40.0, 0, 0.001, 1, 33.7, 1000, 98_765.4321] {
            let back = conversion.fromSI(conversion.toSI(value))
            // Mixed absolute/relative: a scale with a large datum (0.001 °F sits on a −17.8 °C
            // offset) loses low bits to cancellation, and demanding pure relative accuracy there
            // would be asserting arithmetic that IEEE doubles cannot do. 1e-9 absolute is eleven
            // orders of magnitude below anything the app displays.
            #expect(abs(back - value) < 1e-9 + 1e-12 * abs(value),
                    "\(value) came back as \(back)")
        }
    }

    @Test func conversionsAreInvertible() {
        for (name, conversion) in Self.allConversions {
            #expect(conversion.factor != 0, "\(name) has a zero factor and cannot be inverted")
            #expect(conversion.factor.isFinite, "\(name) has a non-finite factor")
        }
    }

    /// Only temperature and enthalpy carry a datum. If a third ever appears, it is either a real
    /// discovery or a typo, and both deserve a failing test.
    @Test func onlyTemperatureAndEnthalpyHaveADatum() {
        let withOffset = Self.allConversions.filter { $0.1.offset != 0 }.map(\.0)
        #expect(Set(withOffset) == ["fahrenheit", "Btu/lb"], "found \(withOffset)")
    }
}

import Testing
import Foundation
@testable import DimensionKit

// Oracle = Federal Register 59-5442 (1959), NIST SP 811 §B.8, 85 FR 62698.  oracle-backed.
/// ORACLES:
///  • PUBLISHED — the 1959 refixing: 1 in = 25.4 mm, 1 ft = 0.3048 m, 1 yd = 0.9144 m, all EXACT.
///  • PUBLISHED — NIST SP 811 §B.8: cubic yard -> cubic metre = 7.645549E-01.
///  • PUBLISHED — 85 FR 62698: the US survey foot is 1200/3937 m and is deprecated from 2023-01-01.
///  • IDENTITY  — the factors are held as exact rationals, so conversions round-trip with no loss.
@Suite("Units — oracle-backed")
struct UnitsOracleTests {

    @Test("the 1959 inch, foot and yard are exact")
    func exactDefinedUnits() {
        let inch = Oracles.require("exact-inch-mm")
        #expect(Units.convert(Rational(1), from: .inch, to: .millimeter)
                == Rational(254, 10), "1 in must be exactly 25.4 mm")
        #expect(Units.convert(1.0, from: .inch, to: .millimeter) == inch.value("millimeters"))

        #expect(LengthUnit.foot.metersPerUnit == Rational(381, 1250), "0.3048 exactly")
        #expect(LengthUnit.yard.metersPerUnit == Rational(1143, 1250), "0.9144 exactly")

        // The definitional relationships, not just the decimals.
        #expect(LengthUnit.foot.metersPerUnit == LengthUnit.inch.metersPerUnit * Rational(12))
        #expect(LengthUnit.yard.metersPerUnit == LengthUnit.inch.metersPerUnit * Rational(36))
    }

    @Test("SP 811 §B.8 — cubic yard to cubic metre")
    func cubicYard() {
        let o = Oracles.require("sp811-B8-cubic-yard")
        let yd = LengthUnit.yard.metersPerUnit
        let m3 = (yd * yd * yd).doubleValue
        #expect(o.matches("cubicMeters", m3),
                "0.9144^3 = \(m3), SP 811 §B.8 publishes \(o.value("cubicMeters"))")
    }

    @Test("85 FR 62698 — the survey foot is 1200/3937 m and differs from the international foot")
    func surveyFoot() {
        let o = Oracles.require("survey-foot-meter")
        #expect(o.matches("meters", Units.surveyFootMeters.doubleValue))
        #expect(Units.surveyFootMeters != LengthUnit.foot.metersPerUnit,
                "the two feet must not be equal — that is the entire point of the legacy mode")
        // Over a mile the two feet differ by a measurable amount; the drift must not be zero.
        let drift = Units.surveyFootDrift(overFeet: Rational(5280))
        #expect(!drift.isZero, "survey-foot drift over a mile must be non-zero")
    }

    @Test("conversions round-trip exactly through the rational path")
    func roundTripsExactly() {
        for unit in LengthUnit.allCases {
            for n in 1...50 {
                let v = Rational(Int64(n), 16)
                let there = Units.convert(v, from: .inch, to: unit)
                let back = Units.convert(there, from: unit, to: .inch)
                #expect(back == v, "\(v) in -> \(unit) -> in lost precision: got \(back)")
            }
        }
    }

    @Test("a foot is twelve inches and a yard is three feet, exactly")
    func trivialIdentitiesHold() {
        #expect(Units.convert(Rational(1), from: .foot, to: .inch) == Rational(12))
        #expect(Units.convert(Rational(1), from: .yard, to: .foot) == Rational(3))
        #expect(Units.convert(Rational(1), from: .meter, to: .centimeter) == Rational(100))
    }
}

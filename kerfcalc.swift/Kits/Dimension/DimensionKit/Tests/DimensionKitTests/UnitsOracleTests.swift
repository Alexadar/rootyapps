import Testing
import Foundation
@testable import DimensionKit

/// Calc #2 — unit conversion.
///
/// ORACLE: NIST factors (published) — 1 in ≡ 25.4 mm, 1 ft ≡ 0.3048 m, 1 yd ≡ 0.9144 m
/// (NIST SP 811 App. B; 1959 international agreement). These are DEFINITIONS, exact.
/// https://www.nist.gov/pml/special-publication-811/nist-guide-si-appendix-b-conversion-factors
@Suite struct UnitsOracle {

    @Test func nistDefinitions() {
        #expect(abs(Units.convert(1, from: .inch, to: .millimeter) - 25.4) < 1e-12)   // NIST: in ≡ 25.4 mm
        #expect(abs(Units.convert(1, from: .foot, to: .meter) - 0.3048) < 1e-12)      // NIST: ft ≡ 0.3048 m
        #expect(abs(Units.convert(1, from: .foot, to: .millimeter) - 304.8) < 1e-9)
        #expect(abs(Units.convert(1, from: .yard, to: .meter) - 0.9144) < 1e-12)      // NIST: yd ≡ 0.9144 m
        #expect(abs(Units.convert(100, from: .inch, to: .millimeter) - 2540) < 1e-9)
    }

    @Test func withinCustomarySystem() {
        #expect(abs(Units.convert(12, from: .inch, to: .foot) - 1) < 1e-12)           // 12 in = 1 ft
        #expect(abs(Units.convert(3, from: .foot, to: .yard) - 1) < 1e-12)            // 3 ft = 1 yd
        #expect(abs(Units.convert(1, from: .yard, to: .inch) - 36) < 1e-12)
    }

    @Test func roundTripInvariant() {
        for u in LengthUnit.allCases {
            let mm = Units.convert(37.5, from: u, to: .millimeter)
            #expect(abs(Units.convert(mm, from: .millimeter, to: u) - 37.5) < 1e-9)   // x → mm → x
        }
    }

    @Test func surveyFootDiffersSlightly() {
        // Legacy US survey foot 1200/3937 m ≈ 0.30480061 m — deliberately NOT equal to the intl foot.
        #expect(abs(Units.surveyFootMeters - 0.3048006096) < 1e-9)
        #expect(Units.surveyFootMeters != 0.3048)
    }

    @Test func decimalFeetSurveying() {
        #expect(abs(Units.inchesToDecimalFeet(6) - 0.50) < 1e-9)     // 6" = 0.50 ft
        #expect(abs(Units.inchesToDecimalFeet(3) - 0.25) < 1e-9)     // 3" = 0.25 ft
        #expect(abs(Units.inchesToDecimalFeet(1, places: 2) - 0.08) < 1e-9)  // 1" ≈ 0.08 ft
    }
}

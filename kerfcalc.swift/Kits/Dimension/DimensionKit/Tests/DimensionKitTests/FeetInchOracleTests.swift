import Testing
import Foundation
@testable import DimensionKit

/// Calc #1 — feet-inch-fraction arithmetic.
///
/// ORACLE DISCIPLINE (see kerfcalc.swift/docs/VALIDATION.md). Feet-inch arithmetic is *definitional*
/// (exact rational arithmetic), so this suite mixes two allowed test classes and one cross-check:
///  • PUBLISHED anchor — `6'2-1/2" + 2'7-3/4" = 8'10-1/4"` is a standard carpentry-calculator result
///    (e.g. CalculatorSoup Feet-and-Inches calculator; 74.5" + 31.75" = 106.25" = 8'10¼"), and the
///    subtraction `6'5-1/4" - 3'2-7/8" = 3'2-3/8"` (77.25" − 38.875" = 38.375").
///  • IDENTITY — hand-verifiable definitions of rational arithmetic (2/4=1/2; 1⅓"×3 = 4"; ties).
///    Their "oracle" is the arithmetic definition itself, not a value this code invented.
///  • CROSS-CHECK (not the authority) — `Oracles/feetinch_oracle.py` is a separately-written CPython
///    `fractions.Fraction` implementation. Re-run it to independently confirm every fraction below.
///    Per the stricter rule it is a corroborating cross-check, NOT the source of ground truth.
@Suite struct FeetInchOracle {

    // MARK: exact arithmetic vs the CPython Fraction oracle
    // All expected fractions: oracle feetinch_oracle.py (CPython fractions.Fraction).

    @Test func addSubExactInches() {
        let a = FeetInch(feet: 6, inches: 2, num: 1, den: 2)   // 6' 2 1/2"
        let b = FeetInch(feet: 2, inches: 7, num: 3, den: 4)   // 2' 7 3/4"
        #expect((a + b).inches == Rational(425, 4))            // oracle: 425/4 in
        #expect((a - b).inches == Rational(171, 4))            // oracle: 171/4 in
    }

    @Test func scaleByNumber() {
        let a = FeetInch(feet: 6, inches: 2, num: 1, den: 2)
        #expect((a * Rational(3)).inches == Rational(447, 2))  // oracle: 447/2 in
        #expect((a / Rational(2)).inches == Rational(149, 4))  // oracle: 149/4 in
    }

    @Test func mixedAndRatio() {
        let c = FeetInch(feet: 12, inches: 6, num: 1, den: 2)  // 12' 6 1/2"
        let d = FeetInch(inches: 3, num: 3, den: 8)            // 3 3/8"
        #expect((c + d).inches == Rational(1231, 8))           // oracle: 1231/8 in
        #expect((c - d).inches == Rational(1177, 8))           // oracle: 1177/8 in
        #expect((c / d) == Rational(1204, 27))                 // oracle: 1204/27 (dimensionless ratio)
    }

    @Test func exactThirdsCancel() {
        let e = FeetInch(inches: 1, num: 1, den: 3)            // 1 1/3"
        #expect((e * Rational(3)).inches == Rational(4))       // oracle: 4/1 in (exact — no fp drift)
        #expect((e + e + e).inches == Rational(4))             // oracle: 4/1 in
    }

    // MARK: rounding to a set fraction — ties away from zero (oracle-computed)

    @Test func roundToNearestFraction() {
        let third = Rational(1, 3)
        #expect(third.rounded(toDenominator: 16) == Rational(5, 16))    // oracle: 5/16
        #expect(third.rounded(toDenominator: 32) == Rational(11, 32))   // oracle: 11/32
        // exact tie 7/32 == 3.5 sixteenths -> away from zero
        #expect(Rational(7, 32).rounded(toDenominator: 16) == Rational(1, 4))    // oracle: 1/4
        #expect(Rational(-7, 32).rounded(toDenominator: 16) == Rational(-1, 4))  // oracle: -1/4
    }

    @Test func divisionThenRound() {
        let x = FeetInch(feet: 10)                             // 120"
        #expect((x / Rational(7)).inches == Rational(120, 7))          // oracle: 120/7 in (exact)
        #expect((x / Rational(7)).rounded(toDenominator: 16).inches
                == Rational(137, 8))                                   // oracle: 137/8 in
    }

    // MARK: formatting — the published worked example, and round readouts

    @Test func formattingWorkedExample() {
        let a = FeetInch(feet: 6, inches: 2, num: 1, den: 2)
        let b = FeetInch(feet: 2, inches: 7, num: 3, den: 4)
        // PUBLISHED: 6'2½" + 2'7¾" = 8'10¼"  (CalculatorSoup Feet-and-Inches calculator)
        #expect((a + b).formatted(toDenominator: 16) == "8' 10-1/4\"")
    }

    @Test func publishedSubtractionExample() {
        // PUBLISHED worked example: 6'5¼" − 3'2⅞" = 3'2⅜"  (77.25" − 38.875" = 38.375")
        let a = FeetInch(feet: 6, inches: 5, num: 1, den: 4)
        let b = FeetInch(feet: 3, inches: 2, num: 7, den: 8)
        #expect((a - b).inches == Rational(307, 8))                    // 38.375"
        #expect((a - b).formatted(toDenominator: 16) == "3' 2-3/8\"")
    }

    @Test func formattingReadouts() {
        #expect(FeetInch(inches: Rational(171, 4)).formatted() == "3' 6-3/4\"")     // 42.75"
        #expect(FeetInch(inches: Rational(447, 2)).formatted() == "18' 7-1/2\"")    // 223.5"
        #expect(FeetInch(inches: Rational(1231, 8)).formatted() == "12' 9-7/8\"")   // 153.875"
        #expect(FeetInch(inches: Rational(4)).formatted() == "4\"")
        #expect(FeetInch(inches: Rational(137, 8)).formatted() == "1' 5-1/8\"")     // 17.125"
        #expect(FeetInch(inches: Rational(0)).formatted() == "0\"")
        #expect(FeetInch(inches: -Rational(171, 4)).formatted() == "-3' 6-3/4\"")
    }

    // MARK: parsing round-trips (parse is exact; compared against the same oracle inch-fractions)

    @Test func parsingRoundTrips() {
        #expect(FeetInch.parse("6' 2 1/2\"")?.inches == Rational(149, 2))   // 74.5"
        #expect(FeetInch.parse("8' 10-1/4\"")?.inches == Rational(425, 4))  // 106.25"
        #expect(FeetInch.parse("12'6-1/2\"")?.inches == Rational(301, 2))   // 150.5"
        #expect(FeetInch.parse("3 3/8\"")?.inches == Rational(27, 8))       // 3.375"
        #expect(FeetInch.parse("18")?.inches == Rational(18))               // bare inches
        #expect(FeetInch.parse("-2' 6\"")?.inches == Rational(-30))
        #expect(FeetInch.parse("garbage") == nil)
        #expect(FeetInch.parse("") == nil)
    }

    // MARK: invariants (identity/definition, cross-checked numerically)

    @Test func rationalInvariants() {
        #expect(Rational(2, 4) == Rational(1, 2))              // always reduced
        #expect(Rational(-3, -6) == Rational(1, 2))           // sign normalised to numerator
        #expect(Rational(0, 5) == Rational(0))                // zero reduces to 0/1
        #expect((Rational(1, 3) + Rational(1, 6)) == Rational(1, 2))
        #expect(Rational(1, 2).doubleValue == 0.5)
    }
}

import Testing
import Foundation
@testable import DimensionKit

// Oracle = NIST SP 811 §B.7.1/§B.7.2 and NIST PS 20-20 App. B §B1 + Table 3.  oracle-backed.
/// The load-bearing suite. Everything the app displays passes through this rounding.
///
/// ORACLES:
///  • PUBLISHED — NIST PS 20-20 Table 3, all 29 dressed lumber sizes, computed as 25.4 mm/in and
///    rounded by the App. B §B1 rule. Tolerance zero: the standard tabulates whole millimetres.
///  • PUBLISHED — the discriminating tie. Dressed 7-1/2 in is 190.5 mm EXACTLY, and PS 20-20
///    publishes 190. Half-away-from-zero gives 191. This one row is why `.halfToEven` is default.
///  • PUBLISHED — NIST SP 811 §B.7.1's four rounding examples, including both tie cases, and
///    §B.7.2's "36 ft x 0.3048 = 10.9728 m = 11.0 m".
///  • INVARIANT — rounding is idempotent, sign-symmetric, and never moves a value by more than
///    half a step.
///
/// SCOPE NOTE, which the corpus repeats and no test may overstate: SP 811 §B.7.1 rounds *decimal
/// digits* and PS 20-20 §B1 rounds *millimetres*. Neither publishes a rule for rounding to a
/// binary fraction denominator (1/16, 1/32, 1/64). What is cited is the TIE-BREAKING RULE;
/// applying it at a fraction denominator is this app's extension by analogy.
@Suite("Rounding — oracle-backed")
struct RoundingOracleTests {

    /// PS 20-20 App. B §B1: mm = 25.4 x dressed inches, to the nearest mm, ties to even.
    /// Modelled exactly: 25.4 is the rational 254/10, and "nearest mm" is denominator 1.
    private func ps20Millimetres(dressedInch: Rational, rule: RoundingRule = .halfToEven) -> Int64 {
        let mm = dressedInch * Rational(254, 10)
        return mm.rounded(toDenominator: 1, rule: rule).num
    }

    // MARK: - PUBLISHED: the whole of Table 3

    @Test("PS 20-20 Table 3 — all 29 dressed sizes reproduce exactly")
    func table3ReproducesExactly() {
        for (dressed, publishedMM) in Oracles.ps20Table3Rows {
            // dressed sizes are dyadic (n/16 at worst) so this is an exact rational, not an approximation
            let r = Rational(Int64((dressed * 16).rounded()), 16)
            #expect(r.doubleValue == dressed, "row \(dressed) is not a clean sixteenth")
            let got = ps20Millimetres(dressedInch: r)
            #expect(Double(got) == publishedMM,
                    "dressed \(dressed) in: got \(got) mm, PS 20-20 Table 3 publishes \(publishedMM) mm")
        }
    }

    // MARK: - PUBLISHED: the tie that separates the two rules

    @Test("the 7-1/2 in row proves the rule is half-to-EVEN")
    func discriminatingTie() {
        let o = Oracles.require("ps20-tie-7_5in-DISCRIMINATING")
        let dressed = Rational(15, 2)                       // 7-1/2 in
        #expect((dressed * Rational(254, 10)) == Rational(381, 2), "7.5 x 25.4 must be exactly 190.5")

        let even = ps20Millimetres(dressedInch: dressed, rule: .halfToEven)
        let away = ps20Millimetres(dressedInch: dressed, rule: .halfAwayFromZero)

        #expect(Double(even) == o.value("mmHalfToEven"), "half-to-even must give the published 190")
        #expect(Double(away) == o.value("mmHalfAwayFromZero"), "half-away-from-zero must give 191")
        #expect(even != away, "this row must separate the two rules, or it proves nothing")
    }

    @Test("the 2-1/2 in row is a tie where both rules agree")
    func agreeingTie() {
        let o = Oracles.require("ps20-tie-2_5in-agreeing")
        let dressed = Rational(5, 2)
        #expect((dressed * Rational(254, 10)) == Rational(127, 2), "2.5 x 25.4 must be exactly 63.5")
        #expect(Double(ps20Millimetres(dressedInch: dressed, rule: .halfToEven)) == o.value("mmHalfToEven"))
        #expect(Double(ps20Millimetres(dressedInch: dressed, rule: .halfAwayFromZero)) == o.value("mmHalfAwayFromZero"))
    }

    // MARK: - PUBLISHED: SP 811 §B.7.1 significant-figure examples

    /// SP 811 rounds significant digits; `Rational.rounded` rounds to a denominator. They meet by
    /// choosing the denominator that puts the cut at the published digit position.
    @Test("SP 811 §B.7.1 — the two tie examples",
          arguments: ["sp811-B71-tie-odd", "sp811-B71-tie-even"])
    func sp811Ties(id: String) {
        let o = Oracles.require(id)
        // 6.9749515 and 6.9749505 to 7 significant digits = 6 decimal places.
        let scale: Int64 = 1_000_000
        let exact = Rational(Int64((o.input("x") * 10_000_000).rounded()), 10_000_000)
        let got = exact.rounded(toDenominator: scale, rule: .halfToEven)
        #expect(got.doubleValue == o.value("rounded"),
                "\(o.input("x")) to 7 digits: got \(got.doubleValue), SP 811 publishes \(o.value("rounded"))")
    }

    @Test("SP 811 §B.7.1 — half-away-from-zero disagrees on the even tie, as it must")
    func sp811EvenTieSeparatesTheRules() {
        let exact = Rational(69_749_505, 10_000_000)        // 6.9749505
        let even = exact.rounded(toDenominator: 1_000_000, rule: .halfToEven)
        let away = exact.rounded(toDenominator: 1_000_000, rule: .halfAwayFromZero)
        #expect(even.doubleValue == 6.974950, "SP 811 publishes 6.974950")
        #expect(away.doubleValue == 6.974951, "half-away would give 6.974951 — which SP 811 does not publish")
    }

    // MARK: - PUBLISHED: SP 811 §B.7.2 conversion

    @Test("SP 811 §B.7.2 — 36 ft = 10.9728 m = 11.0 m")
    func sp811ConversionExample() {
        let o = Oracles.require("sp811-B72-36ft")
        let metres = Rational(36) * LengthUnit.foot.metersPerUnit
        #expect(metres.doubleValue == o.value("metersExact"),
                "36 ft x 0.3048 must be exactly 10.9728 m")
        // Three significant digits, which for a value near 11 is one decimal place.
        let rounded = metres.rounded(toDenominator: 10, rule: .halfToEven)
        #expect(rounded.doubleValue == o.value("metersRounded3sf"))
    }

    // MARK: - INVARIANT

    @Test("rounding to a denominator is idempotent")
    func idempotent() {
        for rule in RoundingRule.allCases {
            for n in -200...200 {
                let v = Rational(Int64(n), 64)
                let once = v.rounded(toDenominator: 16, rule: rule)
                let twice = once.rounded(toDenominator: 16, rule: rule)
                #expect(once == twice, "rounding \(v) twice moved it")
            }
        }
    }

    @Test("rounding never moves a value by more than half a step")
    func withinHalfAStep() {
        for rule in RoundingRule.allCases {
            for n in -500...500 {
                let v = Rational(Int64(n), 64)
                let r = v.rounded(toDenominator: 16, rule: rule)
                let delta = (r - v).magnitude
                #expect(!(Rational(1, 32) < delta), "rounding \(v) moved it by \(delta), more than 1/32")
            }
        }
    }

    @Test("both rules are symmetric about zero")
    func signSymmetric() {
        for rule in RoundingRule.allCases {
            for n in 1...300 {
                let v = Rational(Int64(n), 32)
                let pos = v.rounded(toDenominator: 8, rule: rule)
                let neg = (-v).rounded(toDenominator: 8, rule: rule)
                #expect(pos == -neg, "rule \(rule) is not symmetric at \(v): +\(pos) vs \(neg)")
            }
        }
    }

    @Test("a value already on the denominator is unchanged")
    func exactValuesUnchanged() {
        for rule in RoundingRule.allCases {
            for n in -64...64 {
                let v = Rational(Int64(n), 16)
                #expect(v.rounded(toDenominator: 16, rule: rule) == v)
            }
        }
    }

    /// The tie rule only ever differs when the two candidates straddle an odd/even boundary — so
    /// on a non-tie the rules must always agree. Guards against a typo swapping the branches.
    @Test("the two rules agree on every non-tie")
    func rulesAgreeOffTies() {
        for n in -400...400 {
            let v = Rational(Int64(n), 64)
            let scaled = v * Rational(16)
            let isTie = scaled.den == 2                      // exactly half a sixteenth
            if isTie { continue }
            #expect(v.rounded(toDenominator: 16, rule: .halfToEven)
                    == v.rounded(toDenominator: 16, rule: .halfAwayFromZero),
                    "rules disagreed on the non-tie \(v)")
        }
    }
}

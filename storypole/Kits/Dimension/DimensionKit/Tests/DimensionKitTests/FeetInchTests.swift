import Testing
import Foundation
@testable import DimensionKit

// Oracle = exact rational arithmetic (identity) + defects quoted from the incumbent's reviews.  identity/invariant.
/// ORACLES:
///  • IDENTITY  — exact rational arithmetic: `a + b - b == a`, `1/3 + 1/3 + 1/3 == 1`. These are
///    definitions of a field, not measurements, so they hold with tolerance zero or not at all.
///  • INVARIANT — parse->format->parse round-trips for every sixteenth across a realistic span.
///  • INVARIANT — negative mixed numbers format and re-parse correctly. This is the incumbent's
///    bug: *"it would show -7 7/8 but it should be -7 1/8 due to the directional problem"*
///    (5★ 2016-04-25). A magnitude-then-sign formatter cannot produce it; a truncating one can.
///  • INVARIANT — the incumbent's reported arithmetic error reproduces correctly here
///    (2★ 2021-07-10: a subtraction that "had to end in 15/16" returned 13/16).
@Suite("FeetInch — exactness and formatting")
struct FeetInchTests {

    // MARK: - IDENTITY: exact arithmetic

    @Test("a + b - b == a exactly, for every sixteenth")
    func additionIsExactlyInvertible() {
        let b = FeetInch(feet: 2, inches: 7, num: 7, den: 8)
        for n in -400...400 {
            let a = FeetInch(inches: Rational(Int64(n), 16))
            #expect((a + b) - b == a, "\(a) + \(b) - \(b) did not return \(a)")
        }
    }

    @Test("thirds sum to a whole, and tenths do too — where Double does not")
    func exactWhereDoubleIsNot() {
        let third = FeetInch(inches: Rational(1, 3))
        #expect(third + third + third == FeetInch(inches: Rational(1)))

        // The reason we do not use Double. Note 1/3+1/3+1/3 DOES give exactly 1.0 in IEEE 754 —
        // the rounding happens to cancel — so it is not a demonstration of anything. Tenths are:
        #expect(0.1 + 0.2 != 0.3, "if this ever passes, IEEE 754 has changed")
        #expect(FeetInch(inches: Rational(1, 10)) + FeetInch(inches: Rational(2, 10))
                == FeetInch(inches: Rational(3, 10)), "the same sum, exact")

        // And the one that actually bites a tape: a tenth of an inch is not a clean sixteenth,
        // so repeated accumulation in Double drifts off the mark. Exactly here, always.
        var acc = FeetInch.zero
        for _ in 0..<10 { acc = acc + FeetInch(inches: Rational(1, 10)) }
        #expect(acc == FeetInch(inches: Rational(1)), "ten tenths must be exactly one inch")
    }

    @Test("scaling by a rational and back is lossless")
    func scalingIsInvertible() {
        let a = FeetInch(feet: 12, inches: 6, num: 1, den: 2)
        for k in 1...32 {
            let f = Rational(Int64(k), 7)
            #expect((a * f) / f == a, "scaling \(a) by \(f) was not reversible")
        }
    }

    // MARK: - The incumbent's reported defects

    /// 2★ 2021-07-10: *"I knew it had to end in 15/16 because I was subtracting something ending in
    /// 11/16 from something ending in 5/8 (10/16) ... but it came up 13/16."*
    @Test("the incumbent's subtraction bug: 10 5/8 - 3 11/16 = 6 15/16")
    func subtractionEndsInFifteenSixteenths() {
        let a = FeetInch(inches: 10, num: 5, den: 8)
        let b = FeetInch(inches: 3, num: 11, den: 16)
        let r = a - b
        #expect(r.inches == Rational(111, 16), "expected 111/16 in, got \(r.inches)")
        #expect(r.formatted() == "6-15/16\"", "expected 6-15/16\", got \(r.formatted())")
    }

    /// 5★ 2016-04-25: *"it would show -7 7/8 but it should be -7 1/8 ... Can't have numbers going
    /// backwards and fractions going forward."*
    @Test("negative mixed numbers keep sign and fraction in the same direction")
    func negativeMixedNumbersFormatCorrectly() {
        #expect(FeetInch(inches: Rational(-57, 8)).formatted() == "-7-1/8\"")
        #expect(FeetInch(inches: Rational(-63, 8)).formatted() == "-7-7/8\"")
        #expect(FeetInch(inches: Rational(-1, 16)).formatted() == "-1/16\"")
        #expect(FeetInch(feet: -1, inches: -6).formatted() == "-1' 6\"")
    }

    @Test("formatting a negative round-trips through the parser")
    func negativesRoundTrip() {
        for n in -600...(-1) {
            let v = FeetInch(inches: Rational(Int64(n), 16))
            let text = v.formatted(toDenominator: 16)
            guard let back = FeetInch.parse(text) else {
                Issue.record("could not re-parse \(text)")
                continue
            }
            #expect(back == v, "\(v) formatted as \(text) and re-parsed as \(back)")
        }
    }

    // MARK: - INVARIANT: parse / format round-trips

    @Test("every sixteenth from 0 to 40 ft round-trips")
    func roundTripsAcrossARealisticSpan() {
        for n in stride(from: 0, through: 40 * 12 * 16, by: 7) {
            let v = FeetInch(inches: Rational(Int64(n), 16))
            let text = v.formatted(toDenominator: 16)
            guard let back = FeetInch.parse(text) else {
                Issue.record("could not re-parse \(text)")
                continue
            }
            #expect(back == v, "\(v) formatted as \(text) and re-parsed as \(back)")
        }
    }

    @Test("the parser accepts every form a tradesman writes",
          arguments: [
            ("12'",            Rational(144)),
            ("6\"",            Rational(6)),
            ("1/2\"",          Rational(1, 2)),
            ("6 1/2\"",        Rational(13, 2)),
            ("12' 6\"",        Rational(150)),
            ("12' 6 1/2\"",    Rational(301, 2)),
            ("12'6-1/2\"",     Rational(301, 2)),
            ("18",             Rational(18)),
            ("-2' 6\"",        Rational(-30)),
            ("12 ft",          Rational(144)),
            ("6 in",           Rational(6)),
          ])
    func parsesTradeForms(text: String, expected: Rational) {
        guard let v = FeetInch.parse(text) else {
            Issue.record("failed to parse \(text)")
            return
        }
        #expect(v.inches == expected, "\(text) parsed to \(v.inches), expected \(expected)")
    }

    @Test("the parser rejects nonsense rather than guessing",
          arguments: ["", "abc", "1/0\"", "6 1/2 3/4\"", "12''", "1..5"])
    func rejectsNonsense(text: String) {
        #expect(FeetInch.parse(text) == nil, "\(text) should not parse")
    }

    @Test("zero formats as 0\"")
    func zeroFormats() {
        #expect(FeetInch.zero.formatted() == "0\"")
    }

    // MARK: - approx

    @Test("approx lands on a clean fraction and respects the rounding rule")
    func approxRespectsTheRule() {
        // 1/32 above a sixteenth boundary: exactly halfway between 0 and 1/16.
        let halfway = 1.0 / 32.0
        #expect(FeetInch.approx(inches: halfway, den: 16, rule: .halfToEven).inches == Rational(0),
                "half-to-even sends a tie at 1/32 down to 0 (0 is even)")
        #expect(FeetInch.approx(inches: halfway, den: 16, rule: .halfAwayFromZero).inches == Rational(1, 16),
                "half-away sends it up to 1/16")
        // Negative side, symmetric.
        #expect(FeetInch.approx(inches: -halfway, den: 16, rule: .halfAwayFromZero).inches == Rational(-1, 16))
    }

    @Test("approx of a √ result stays on the denominator")
    func approxOfIrrational() {
        let diagonal = (3.0 * 3.0 + 4.0 * 4.0).squareRoot()      // exactly 5
        #expect(FeetInch.approx(inches: diagonal, den: 16).inches == Rational(5))
        let root2 = 2.0.squareRoot()
        let v = FeetInch.approx(inches: root2, den: 64)
        #expect(v.inches.den <= 64, "approx must land on the requested denominator or coarser")
    }
}

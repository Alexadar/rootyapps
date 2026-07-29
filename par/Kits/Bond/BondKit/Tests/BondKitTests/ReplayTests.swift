import Testing
import Foundation
import BondKit

/// The Kit-level half of the tape's correctness requirement (`par/plan_tape.md` §3): a saved tape stores
/// a security's terms and re-prices it on reopening. Terms must round-trip exactly — including the
/// first-period case, which selects a *different formula* and would silently reprice the line if it were
/// lost — and pricing must be deterministic.
///
/// ORACLES:
///  • IDENTITY — encode/decode is the identity on `Terms`; `quote` is pure.
///  • INVARIANT — corrupt persisted terms throw rather than trapping.
@Suite("Tape replay — codability and determinism")
struct ReplayTests {

    static let terms: [Bond.Terms] = [
        .init(couponPct: 8.75, fullPeriods: 59, daysToNextCoupon: 184, daysInPeriod: 184),
        .init(couponPct: 8.50, fullPeriods: 3, daysToNextCoupon: 181, daysInPeriod: 183,
              firstPeriod: .short),
        .init(couponPct: 8.50, fullPeriods: 10, daysToNextCoupon: 75, daysInPeriod: 181,
              firstPeriod: .long),
        .init(couponPct: 9.50, fullPeriods: 19, daysToNextCoupon: 167, daysInPeriod: 181,
              firstPeriod: .reopenedRegular),
        .init(couponPct: 10.75, fullPeriods: 39, daysToNextCoupon: 103, daysInPeriod: 184,
              firstPeriod: .reopenedLongRegularPortion,
              fractionalPortionDays: 44, fractionalPortionPeriodDays: 181),
    ]

    @Test("terms replay to the identical quote", arguments: terms.indices)
    func replayIsBitForBit(index: Int) throws {
        let original = Self.terms[index]
        let restored = try JSONDecoder().decode(Bond.Terms.self, from: JSONEncoder().encode(original))

        #expect(restored == original)
        #expect(restored.firstPeriod == original.firstPeriod,
                "losing the first-period case would silently reprice the line")

        for yield in [0.0, 0.0442, 0.0954, 0.1047, 0.31] {
            let before = Bond.quote(original, yield: yield)
            let after = Bond.quote(restored, yield: yield)
            #expect(after == before, "\(yield): \(after) != \(before) after a round trip")
        }
        // And the inverse solve replays identically too.
        let price = Bond.price(original, yield: 0.0954)
        #expect(try Bond.yieldToMaturity(restored, price: price)
                == (try Bond.yieldToMaturity(original, price: price)))
    }

    @Test func corruptPersistedTermsThrow() {
        let corrupt = [
            #"{"couponPct":-1,"fullPeriods":10,"daysToNextCoupon":90,"daysInPeriod":182,"firstPeriod":"regular","fractionalPortionDays":0,"fractionalPortionPeriodDays":1}"#,
            #"{"couponPct":5,"fullPeriods":-2,"daysToNextCoupon":90,"daysInPeriod":182,"firstPeriod":"regular","fractionalPortionDays":0,"fractionalPortionPeriodDays":1}"#,
            #"{"couponPct":5,"fullPeriods":10,"daysToNextCoupon":90,"daysInPeriod":0,"firstPeriod":"regular","fractionalPortionDays":0,"fractionalPortionPeriodDays":1}"#,
            #"{"couponPct":5,"fullPeriods":10,"daysToNextCoupon":90,"daysInPeriod":182,"firstPeriod":"regular","fractionalPortionDays":0,"fractionalPortionPeriodDays":0}"#,
            #"{"couponPct":5,"fullPeriods":10,"daysToNextCoupon":90,"daysInPeriod":182,"firstPeriod":"guesswork","fractionalPortionDays":0,"fractionalPortionPeriodDays":1}"#,
        ]
        for json in corrupt {
            #expect(throws: (any Error).self) {
                _ = try JSONDecoder().decode(Bond.Terms.self, from: Data(json.utf8))
            }
        }
    }
}

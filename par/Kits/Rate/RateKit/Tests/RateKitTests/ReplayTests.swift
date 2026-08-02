import Testing
import Foundation
import RateKit

/// The Kit-level half of the tape's correctness requirement (`par/plan_tape.md` §3): a saved tape stores
/// the advance and payment schedule and re-solves the APR on reopening. The schedule must round-trip
/// exactly — fractional unit-periods included, since those are the values a naive encoding would round —
/// and the solve must be deterministic.
///
/// ORACLES:
///  • IDENTITY — encode/decode is the identity on `Advance`/`Payment`; `aprActuarial` is pure.
///  • INVARIANT — corrupt persisted data throws rather than trapping.
@Suite("Tape replay — codability and determinism")
struct ReplayTests {

    @Test("published schedules replay to the identical APR",
          arguments: Oracles.appendixJCases.map(\.id))
    func replayIsBitForBit(id: String) throws {
        let example = Oracles.requireCase(id)
        let advances = [Rate.Advance(amount: example.advance, fullPeriods: 0)]
        let payments = example.series.flatMap {
            Rate.series(amount: $0.amount, count: $0.count,
                        firstAtFullPeriods: $0.fullPeriods, fraction: $0.fraction)
        }

        let encoder = JSONEncoder()
        let restoredAdvances = try JSONDecoder().decode(
            [Rate.Advance].self, from: encoder.encode(advances)
        )
        let restoredPayments = try JSONDecoder().decode(
            [Rate.Payment].self, from: encoder.encode(payments)
        )
        #expect(restoredAdvances == advances)
        #expect(restoredPayments == payments)
        // Fractions like 26/28 and 52/60 are the values that would silently degrade under a lossy
        // encoding, and they are exactly the ones that move the published rate.
        for (restored, original) in zip(restoredPayments, payments) {
            #expect(restored.fraction == original.fraction)
        }

        let before = try Rate.aprActuarial(advances: advances, payments: payments,
                                           unitPeriodsPerYear: example.unitPeriodsPerYear)
        let after = try Rate.aprActuarial(advances: restoredAdvances, payments: restoredPayments,
                                          unitPeriodsPerYear: example.unitPeriodsPerYear)
        #expect(after == before, "\(id): \(after) != \(before) after a round trip")
    }

    @Test func corruptPersistedScheduleEntriesThrow() {
        let corruptPayments = [
            #"[{"amount":100,"fullPeriods":-1,"fraction":0}]"#,
            #"[{"amount":100,"fullPeriods":1,"fraction":1}]"#,
            #"[{"amount":100,"fullPeriods":1,"fraction":-0.5}]"#,
            #"[{"amount":100,"fullPeriods":1}]"#,
        ]
        for json in corruptPayments {
            #expect(throws: (any Error).self) {
                _ = try JSONDecoder().decode([Rate.Payment].self, from: Data(json.utf8))
            }
        }
        // An advance of zero is not an advance.
        #expect(throws: (any Error).self) {
            _ = try JSONDecoder().decode(
                [Rate.Advance].self,
                from: Data(#"[{"amount":0,"fullPeriods":0,"fraction":0}]"#.utf8)
            )
        }
    }
}

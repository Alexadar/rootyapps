import Testing
import Foundation
import AmortKit

/// The Kit-level half of the tape's correctness requirement (`par/plan_tape.md` §3): a saved tape stores
/// the loan and rebuilds its schedule on reopening, so a `Loan` must survive a disk round trip exactly
/// and the schedule must be a deterministic function of it. The tape's own tests live in the app target;
/// this is the guarantee they rest on.
///
/// ORACLES:
///  • IDENTITY — encode/decode is the identity on `Loan`; `schedule` is pure.
///  • INVARIANT — corrupt persisted data throws rather than trapping.
@Suite("Tape replay — codability and determinism")
struct ReplayTests {

    static let loans: [Amortization.Loan] = [
        .init(principal: 420_000, periodicRate: 0.0625 / 12, periods: 360),
        .init(principal: 250_000, periodicRate: 0.0525 / 12, periods: 300, timing: .begin,
              rounding: .currency(decimals: 2)),
        .init(principal: 12_345.67, periodicRate: 0.049366666666666665, periods: 37,
              rounding: .currency(decimals: 0), balloon: 1_111.111),
        .init(principal: 1_000, periodicRate: 0, periods: 12),
    ]

    @Test("a loan and its whole schedule replay identically", arguments: loans.indices)
    func replayIsBitForBit(index: Int) throws {
        let original = Self.loans[index]
        let restored = try JSONDecoder().decode(
            Amortization.Loan.self, from: JSONEncoder().encode(original)
        )
        #expect(restored == original)
        #expect(restored.rounding == original.rounding, "the rounding policy must round-trip too")

        // Every row, `==` on the doubles — not a tolerance. A reopened tape shows the same table.
        let before = Amortization.schedule(original)
        let after = Amortization.schedule(restored)
        #expect(after == before)
        #expect(Amortization.payment(after: restored) == Amortization.payment(after: original))
        #expect(Amortization.totalInterest(restored) == Amortization.totalInterest(original))
    }

    @Test func corruptPersistedLoansThrow() {
        let corrupt = [
            #"{"principal":-1,"periodicRate":0.005,"periods":12,"timing":"end","rounding":{"exact":{}},"balloon":0}"#,
            #"{"principal":1000,"periodicRate":0.005,"periods":0,"timing":"end","rounding":{"exact":{}},"balloon":0}"#,
            #"{"principal":1000,"periodicRate":-2,"periods":12,"timing":"end","rounding":{"exact":{}},"balloon":0}"#,
            #"{"principal":1000,"periodicRate":0.005,"periods":12,"timing":"end","rounding":{"exact":{}},"balloon":-5}"#,
        ]
        for json in corrupt {
            #expect(throws: (any Error).self) {
                _ = try JSONDecoder().decode(Amortization.Loan.self, from: Data(json.utf8))
            }
        }
    }
}

/// A tiny shim so the replay test reads the way the tape does — one line, one result.
private extension Amortization {
    static func payment(after loan: Loan) -> Double { payment(loan) }
}

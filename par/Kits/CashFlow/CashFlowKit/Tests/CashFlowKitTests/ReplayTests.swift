import Testing
import Foundation
import CashFlowKit

/// The Kit-level half of the tape's correctness requirement (`par/plan_tape.md` §3): a saved tape stores
/// the grouped cash flows and re-runs NPV/IRR on reopening, so groups must round-trip exactly and both
/// measures must be deterministic — including the multi-root case, where "which root" must not drift
/// between runs.
///
/// ORACLES:
///  • IDENTITY — encode/decode is the identity on `Group`; `npv` and `irr` are pure.
///  • INVARIANT — corrupt persisted data throws rather than trapping.
@Suite("Tape replay — codability and determinism")
struct ReplayTests {

    static let groupSets: [[CashFlow.Group]] = [
        [.init(amount: -5_000, count: 1), .init(amount: 230, count: 24)],
        [.init(amount: -250_000, count: 1), .init(amount: 1_480.37, count: 300)],
        [.init(amount: -4_000, count: 1), .init(amount: 25_000, count: 1), .init(amount: -25_000, count: 1)],
        [.init(amount: -12_345.67, count: 1), .init(amount: 333.331, count: 37),
         .init(amount: 1_111.111, count: 1)],
    ]

    @Test("grouped flows and their measures replay identically", arguments: groupSets.indices)
    func replayIsBitForBit(index: Int) throws {
        let original = Self.groupSets[index]
        let restored = try JSONDecoder().decode(
            [CashFlow.Group].self, from: JSONEncoder().encode(original)
        )
        #expect(restored == original)
        #expect(CashFlow.expand(restored) == CashFlow.expand(original))

        let flows = CashFlow.expand(restored)
        let flowsBefore = CashFlow.expand(original)
        for rate in [0.0, 0.004, 0.0525 / 12, 0.31] {
            #expect(CashFlow.npv(rate: rate, flows: flows) == CashFlow.npv(rate: rate, flows: flowsBefore))
        }
        // IRR too — including the multi-root set, where the *set* of roots must be identical.
        #expect(CashFlow.irr(flows: flows) == CashFlow.irr(flows: flowsBefore))
    }

    /// The IRR result itself is persistable, so a tape can show what it found — one root, several, or
    /// none — without re-deriving it to draw a row.
    @Test func irrResultRoundTrips() throws {
        let cases: [CashFlow.IRRResult] = [
            .unique(0.008075), .multiple([0.25, 4.75]), .none,
        ]
        for value in cases {
            let restored = try JSONDecoder().decode(
                CashFlow.IRRResult.self, from: JSONEncoder().encode(value)
            )
            #expect(restored == value)
        }
    }

    @Test func corruptPersistedGroupsThrow() {
        let corrupt = [
            #"[{"amount":100,"count":0}]"#,
            #"[{"amount":100,"count":-3}]"#,
            #"[{"count":4}]"#,
        ]
        for json in corrupt {
            #expect(throws: (any Error).self) {
                _ = try JSONDecoder().decode([CashFlow.Group].self, from: Data(json.utf8))
            }
        }
    }
}

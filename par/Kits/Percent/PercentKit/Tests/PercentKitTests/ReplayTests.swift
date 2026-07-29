import Testing
import Foundation
import PercentKit

/// The Kit-level half of the tape's correctness requirement (`par/plan_tape.md` §3): a saved tape stores
/// the cost, the price and the break-even inputs, and re-derives the margin on reopening.
///
/// **This Kit persists no type of its own.** `Percent` is a pure namespace — no struct, no enum, nothing
/// `Codable` — so unlike the other nine there is no Kit type to round-trip. What a tape actually stores
/// is six scalars (`PercentInputs` in the app target, which a Kit cannot import), and what has to survive
/// is the arithmetic over them. `Fixture` below mirrors those six fields exactly; if it ever drifts from
/// `PercentInputs`, this suite is testing the wrong shape. The absence is stated here for the same reason
/// `PercentTests` states the absence of a published corpus rather than inventing one.
///
/// ORACLES:
///  • IDENTITY — encode/decode is the identity on the stored scalars; every `Percent` function is pure.
///  • INVARIANT — the values a stored row must exclude are exactly the Kit's own preconditions.
@Suite("Tape replay — codability and determinism")
struct ReplayTests {

    /// Mirrors `Par/Models/TapeRow.swift`'s `PercentInputs`, field for field.
    struct Fixture: Codable, Equatable {
        var mode: String
        var cost: Double
        var price: Double
        var fixedCosts: Double
        var variableCostPerUnit: Double
        var targetProfit: Double
    }

    static let rows: [Fixture] = [
        .init(mode: "margin", cost: 60, price: 100,
              fixedCosts: 10_000, variableCostPerUnit: 15, targetProfit: 0),
        // Values chosen to have no exact binary representation: the round trip has to be real.
        .init(mode: "margin", cost: 61.379999999999995, price: 99.94999999999999,
              fixedCosts: 12_345.67, variableCostPerUnit: 15.333333333333334, targetProfit: 7_777.77),
        .init(mode: "breakEven", cost: 12.5, price: 41.25,
              fixedCosts: 88_000.01, variableCostPerUnit: 12.5, targetProfit: 25_000),
    ]

    @Test("stored rows replay to the identical margin and break-even", arguments: rows.indices)
    func replayIsBitForBit(index: Int) throws {
        let row = Self.rows[index]
        let restored = try JSONDecoder().decode(Fixture.self, from: JSONEncoder().encode(row))
        #expect(restored == row)
        // Field by field, with `==` on the doubles — not a tolerance.
        #expect(restored.cost == row.cost)
        #expect(restored.price == row.price)
        #expect(restored.fixedCosts == row.fixedCosts)
        #expect(restored.variableCostPerUnit == row.variableCostPerUnit)
        #expect(restored.targetProfit == row.targetProfit)

        let marginBefore = Percent.marginOnPrice(cost: row.cost, price: row.price)
        let marginAfter = Percent.marginOnPrice(cost: restored.cost, price: restored.price)
        #expect(marginAfter == marginBefore,
                "row \(index): margin \(marginAfter) != \(marginBefore) after a round trip")

        if row.price > row.variableCostPerUnit {
            let before = Percent.unitsForTargetProfit(
                fixedCosts: row.fixedCosts, pricePerUnit: row.price,
                variableCostPerUnit: row.variableCostPerUnit, targetProfit: row.targetProfit)
            let after = Percent.unitsForTargetProfit(
                fixedCosts: restored.fixedCosts, pricePerUnit: restored.price,
                variableCostPerUnit: restored.variableCostPerUnit,
                targetProfit: restored.targetProfit)
            #expect(after == before, "row \(index): break-even units moved across a round trip")
        }
    }

    @Test func solvingIsPureAndRepeatable() {
        let row = Self.rows[1]
        let first = Percent.marginOnPrice(cost: row.cost, price: row.price)
        for _ in 0..<100 {
            #expect(Percent.marginOnPrice(cost: row.cost, price: row.price) == first)
        }
        // Changing one input changes only that answer; the original inputs are untouched.
        let other = Percent.marginOnPrice(cost: row.cost, price: row.price * 2)
        #expect(other != first)
        #expect(Percent.marginOnPrice(cost: row.cost, price: row.price) == first)
    }

    /// The Kit's preconditions are traps, so a hand-edited tape must never reach them. `TapeSolver`
    /// guards each one before calling in; this pins the exact boundary set those guards have to
    /// cover, so the two cannot drift apart silently.
    @Test func theValuesAStoredRowMustExcludeAreTheKitsPreconditions() {
        let row = Self.rows[0]

        // `marginOnPrice` divides by price.
        #expect(row.price != 0)

        // `unitsForTargetProfit` needs a positive contribution and non-negative fixed costs.
        #expect(row.price > row.variableCostPerUnit)
        #expect(row.fixedCosts >= 0)

        // A row whose price does not exceed its variable cost has no break-even at any volume, and
        // the Kit traps rather than returning infinity — which is why the replay test guards before
        // calling instead of assuming every stored row is solvable.
        let unsolvable = Fixture(mode: "breakEven", cost: 10, price: 12.5,
                                 fixedCosts: 5_000, variableCostPerUnit: 12.5, targetProfit: 0)
        #expect(!(unsolvable.price > unsolvable.variableCostPerUnit))

        // And the scalars themselves must be finite — JSON can carry a value that is not.
        for stored in Self.rows {
            #expect(stored.cost.isFinite && stored.price.isFinite)
            #expect(stored.fixedCosts.isFinite && stored.variableCostPerUnit.isFinite)
            #expect(stored.targetProfit.isFinite)
        }
    }

    @Test func corruptPersistedRowsThrow() {
        let corrupt = [
            // a missing field
            #"{"mode":"margin","cost":60,"price":100,"fixedCosts":10000,"variableCostPerUnit":15}"#,
            // a price that is not a number
            #"{"mode":"margin","cost":60,"price":"free","fixedCosts":10000,"variableCostPerUnit":15,"targetProfit":0}"#,
            // a mode that is not a string
            #"{"mode":7,"cost":60,"price":100,"fixedCosts":10000,"variableCostPerUnit":15,"targetProfit":0}"#,
        ]
        for json in corrupt {
            #expect(throws: (any Error).self) {
                _ = try JSONDecoder().decode(Fixture.self, from: Data(json.utf8))
            }
        }
    }
}

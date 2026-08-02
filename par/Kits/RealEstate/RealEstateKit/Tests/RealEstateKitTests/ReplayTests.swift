import Testing
import Foundation
import RealEstateKit

/// The Kit-level half of the tape's correctness requirement (`par/plan_tape.md` §3): a saved tape stores
/// the rent roll and the two lender tests, and re-sizes the loan on reopening. The sizing must round-trip
/// exactly — a borrower reads the loan figure off it — and a sizing that arrives from disk must be one
/// `sizeLoan` could have produced, because nothing downstream re-derives it.
///
/// ORACLES:
///  • IDENTITY — encode/decode is the identity on `LoanSizing`; `sizeLoan` is pure.
///  • INVARIANT — corrupt persisted data throws a `DecodingError` rather than being drawn as an offer.
@Suite("Tape replay — codability and determinism")
struct ReplayTests {

    /// The same deal the identity suite uses: 24 units, $1,800/month, 5% vacancy, 38% expenses.
    static let noi = RealEstate.netOperatingIncome(
        grossPotentialRent: 24.0 * 1_800 * 12, vacancyRate: 0.05, operatingExpenses: 197_000
    )

    /// Deliberately mixed: one deal the coverage test binds, one the value test does. Which one bound
    /// is itself persisted, so both branches have to survive the trip.
    static let deals: [(value: Double, dscr: Double, ltv: Double, rate: Double, years: Double)] = [
        (5_400_000, 1.25, 0.75, 6.25, 30),
        (3_000_000, 1.20, 0.80, 5.00, 25),
        // A rate with no exact binary representation, and a fractional amortisation.
        (4_150_000, 1.3333333333333333, 0.6949999999999999, 6.1234567, 27.5),
    ]

    @Test("a sized loan replays to the identical offer", arguments: deals.indices)
    func replayIsBitForBit(index: Int) throws {
        let deal = Self.deals[index]
        let sizing = RealEstate.sizeLoan(
            netOperatingIncome: Self.noi, value: deal.value, targetDSCR: deal.dscr,
            maxLTV: deal.ltv, annualRatePct: deal.rate, amortizationYears: deal.years
        )
        let restored = try JSONDecoder().decode(
            RealEstate.LoanSizing.self, from: JSONEncoder().encode(sizing)
        )
        // Field by field, with `==` on the doubles — not a tolerance. A reopened tape shows the
        // same offer, to the cent.
        #expect(restored == sizing)
        #expect(restored.loan == sizing.loan)
        #expect(restored.byDSCR == sizing.byDSCR)
        #expect(restored.byLTV == sizing.byLTV)
        #expect(restored.dscrConstrained == sizing.dscrConstrained)

        // Re-sizing from the same inputs is deterministic, so a tape can re-derive rather than trust.
        let resized = RealEstate.sizeLoan(
            netOperatingIncome: Self.noi, value: deal.value, targetDSCR: deal.dscr,
            maxLTV: deal.ltv, annualRatePct: deal.rate, amortizationYears: deal.years
        )
        #expect(resized == sizing)
    }

    @Test func bothBindingBranchesAreRepresented() {
        let constrained = Self.deals.map { deal in
            RealEstate.sizeLoan(netOperatingIncome: Self.noi, value: deal.value,
                                targetDSCR: deal.dscr, maxLTV: deal.ltv,
                                annualRatePct: deal.rate, amortizationYears: deal.years)
                .dscrConstrained
        }
        #expect(constrained.contains(true), "no deal exercises the coverage-bound branch")
        #expect(constrained.contains(false), "no deal exercises the value-bound branch")
    }

    @Test func corruptPersistedSizingsThrow() {
        let corrupt = [
            // a loan larger than either test supports — the one that would be read as an offer
            #"{"byDSCR":100,"byLTV":200,"loan":999999999,"dscrConstrained":true}"#,
            // the loan is not the smaller test
            #"{"byDSCR":100,"byLTV":200,"loan":200,"dscrConstrained":true}"#,
            // the wrong test named as binding
            #"{"byDSCR":100,"byLTV":200,"loan":100,"dscrConstrained":false}"#,
            // a negative loan
            #"{"byDSCR":-100,"byLTV":200,"loan":-100,"dscrConstrained":true}"#,
        ]
        for json in corrupt {
            #expect(throws: (any Error).self) {
                _ = try JSONDecoder().decode(RealEstate.LoanSizing.self, from: Data(json.utf8))
            }
        }
        // A sizing this Kit really produced still decodes.
        #expect(throws: Never.self) {
            let real = RealEstate.sizeLoan(
                netOperatingIncome: Self.noi, value: 5_400_000, targetDSCR: 1.25,
                maxLTV: 0.75, annualRatePct: 6.25, amortizationYears: 30
            )
            _ = try JSONDecoder().decode(
                RealEstate.LoanSizing.self, from: JSONEncoder().encode(real))
        }
    }
}

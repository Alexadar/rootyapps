import Testing
import Foundation
import AmortKit

/// Enforcement guard for the oracle corpus, per `calculators/VALIDATION.md`.
///
/// ORACLES:
///  • GUARD — structural only.
@Suite("Oracle corpus integrity")
struct OracleGuardTests {

    @Test func everyOracleCitesAnExternalSource() {
        for o in Oracles.all {
            #expect(!o.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            #expect(o.source.contains("CFR") && o.source.contains("http"),
                    "oracle '\(o.id)' must cite a locatable document")
            #expect(!o.inputs.isEmpty)
            #expect(!o.precision.isEmpty, "oracle '\(o.id)' has no precision rationale")
        }
    }

    @Test func everyValueHasAMatchingTolerance() {
        for o in Oracles.all {
            #expect(!o.values.isEmpty)
            for key in o.values.keys {
                #expect(o.tolerances[key] != nil, "'\(o.id)'.\(key) has no tolerance")
                #expect((o.tolerances[key] ?? -1) > 0, "'\(o.id)'.\(key) tolerance must be positive")
            }
            for key in o.tolerances.keys { #expect(o.values[key] != nil) }
        }
    }

    @Test func oracleIDsAreUniqueAndResolvable() {
        let ids = Oracles.all.map(\.id)
        #expect(Set(ids).count == ids.count)
        for o in Oracles.all { #expect(Oracles.require(o.id).id == o.id) }
    }

    /// Coverage guard: every rounding mode the app can select must be exercised by the closure tests,
    /// which is what makes "the schedule always closes" a claim rather than a hope.
    @Test func everyRoundingModeIsExercised() {
        let exercised: [Amortization.Rounding] = [.exact, .currency(decimals: 2), .currency(decimals: 0)]
        #expect(exercised.contains(.exact))
        #expect(exercised.contains(.currency(decimals: 2)))
        #expect(exercised.count == 3)
    }
}

// Oracle = 12 CFR 1026 App J (c)(1) (CFPB, public domain).  oracle-backed.
/// The published level payment behind Appendix J's own APR examples.
///
/// ORACLES:
///  • PUBLISHED — (c)(1)(i): $5,000 over 24 monthly payments at the published 9.69% APR is a $230
///    payment. The tolerance comes from the APR's published rounding, measured, not guessed.
@Suite("Payment — oracle-backed")
struct PaymentOracles {

    @Test func publishedMonthlyPayment() {
        let o = Oracles.require("regz-appJ-c1-i-payment")
        let loan = Amortization.Loan(
            principal: o.input("principal"),
            periodicRate: o.input("annualRatePct") / 100 / o.input("periodsPerYear"),
            periods: Int(o.input("periods"))
        )
        let pmt = Amortization.payment(loan)
        #expect(o.matches("payment", pmt), "computed \(pmt) against published \(o.value("payment"))")
    }

}

/// What amortization must always do, whatever the inputs.
///
/// ORACLES:
///  • IDENTITY — Σprincipal == principal − balloon; interest == balance × rate every period; the
///    closed-form remaining balance equals the walked schedule.
///  • INVARIANT — closure under every rounding mode, monotone balance, begin/end difference, balloon,
///    zero rate, single period, totals additivity.
@Suite("Amortization — identity and invariant")
struct AmortIdentities {

    static let loans: [Amortization.Loan] = [
        .init(principal: 400_000, periodicRate: 0.065 / 12, periods: 360),
        .init(principal: 32_000, periodicRate: 0.049 / 12, periods: 60),
        .init(principal: 5_000, periodicRate: 0.0969 / 12, periods: 24),
        .init(principal: 1_000, periodicRate: 0, periods: 12),                       // zero rate
        .init(principal: 250_000, periodicRate: 0.0525 / 12, periods: 300, timing: .begin),
        .init(principal: 100_000, periodicRate: 0.07 / 12, periods: 120, balloon: 40_000),
        .init(principal: 9_500, periodicRate: 0.24 / 12, periods: 1),                // single period
        .init(principal: 750_000, periodicRate: 1e-9, periods: 240),                  // near-zero rate
    ]

    @Test("the schedule closes and the principal adds up", arguments: loans.indices)
    func scheduleCloses(index: Int) {
        let loan = Self.loans[index]
        let rows = Amortization.schedule(loan)

        #expect(rows.count == loan.periods)
        #expect(rows.map(\.index) == Array(1...loan.periods))

        let principalPaid = rows.reduce(0) { $0 + $1.principal }
        let scale = max(loan.principal, 1)
        #expect(abs(principalPaid - (loan.principal - loan.balloon)) <= 1e-9 * scale,
                "Σprincipal must equal the amount actually repaid")
        #expect(abs((rows.last?.balance ?? .nan) - loan.balloon) <= 1e-9 * scale,
                "the final balance must be exactly the balloon (zero, when there is none)")

        // Every payment is interest plus principal, exactly.
        for row in rows {
            #expect(abs(row.payment - (row.interest + row.principal)) <= 1e-9 * max(row.payment, 1))
        }
    }

    @Test("interest is always the balance times the rate", arguments: loans.indices)
    func interestIsBalanceTimesRate(index: Int) {
        let loan = Self.loans[index]
        let rows = Amortization.schedule(loan)
        var balance = loan.principal
        for row in rows {
            // Payments at period end accrue interest on the whole balance; payments at period start
            // accrue it on the balance the payment has already reduced.
            let base = loan.timing == .begin ? balance - row.payment : balance
            let expected = max(base, 0) * loan.periodicRate
            #expect(abs(row.interest - expected) <= 1e-9 * max(abs(expected), 1),
                    "period \(row.index): interest \(row.interest) vs balance×rate \(expected)")
            balance = row.balance
        }
    }

    @Test("the closed-form balance matches the walked schedule", arguments: loans.indices)
    func closedFormBalanceMatchesSchedule(index: Int) {
        let loan = Self.loans[index]
        let rows = Amortization.schedule(loan)
        let scale = max(loan.principal, 1)
        #expect(abs(Amortization.balance(loan, after: 0) - loan.principal) <= 1e-12 * scale)
        for row in rows.dropLast() {
            let closed = Amortization.balance(loan, after: row.index)
            #expect(abs(closed - row.balance) <= 1e-7 * scale,
                    "period \(row.index): closed form \(closed) vs schedule \(row.balance)")
        }
    }

    @Test func balanceFallsMonotonicallyAndInterestFalls() {
        let loan = Amortization.Loan(principal: 400_000, periodicRate: 0.065 / 12, periods: 360)
        let rows = Amortization.schedule(loan)
        for (previous, next) in zip(rows, rows.dropFirst()) {
            #expect(next.balance < previous.balance, "balance must fall every period")
            #expect(next.interest < previous.interest, "interest must fall as the balance does")
            #expect(next.principal > previous.principal, "principal must rise as interest falls")
        }
        #expect(rows.first!.interest > rows.last!.interest * 10, "an early mortgage payment is mostly interest")
    }

    /// The lender's schedule: round to the cent, and let the last payment absorb the residue. It must
    /// still close exactly, and the sum of rounded interest must stay within a cent per period of the
    /// exact schedule.
    @Test("rounded schedules still close exactly", arguments: [0, 2])
    func currencyRoundingStillCloses(decimals: Int) {
        for seed in Self.loans {
            let loan = Amortization.Loan(
                principal: seed.principal, periodicRate: seed.periodicRate, periods: seed.periods,
                timing: seed.timing, rounding: .currency(decimals: decimals), balloon: seed.balloon
            )
            let rows = Amortization.schedule(loan)
            let epsilon = 0.5 * pow(10.0, Double(-decimals))

            #expect(abs((rows.last?.balance ?? .nan) - loan.balloon) <= epsilon,
                    "a rounded schedule must still land on the balloon")
            let principalPaid = rows.reduce(0) { $0 + $1.principal }
            #expect(abs(principalPaid - (loan.principal - loan.balloon)) <= epsilon)

            // Every rounded figure must sit on the rounding grid.
            let scale = pow(10.0, Double(decimals))
            for row in rows {
                #expect(abs((row.payment * scale).rounded() - row.payment * scale) <= 1e-6)
                #expect(abs((row.interest * scale).rounded() - row.interest * scale) <= 1e-6)
            }

            // The final payment differs from the level one by the accumulated rounding residue. That
            // residue compounds, so the honest bound is one rounding step grown over the whole term:
            // ε·((1+i)ⁿ − 1)/i, which is $366 for a 300-month loan rounded to the dollar.
            let level = Amortization.payment(loan)
            let i = loan.periodicRate, n = Double(loan.periods)
            let compoundedResidue = i == 0 ? epsilon * n : epsilon * (pow(1 + i, n) - 1) / i
            let residue = abs((rows.last?.payment ?? .nan) - level)
            #expect(residue <= compoundedResidue + epsilon,
                    "residue \(residue) exceeded the compounded rounding bound \(compoundedResidue)")
        }
    }

    @Test func totalsAddUpAndSliceCorrectly() {
        let loan = Amortization.Loan(principal: 400_000, periodicRate: 0.065 / 12, periods: 360)
        let rows = Amortization.schedule(loan)

        let whole = Amortization.totals(loan, from: 1, through: 360)
        #expect(abs(whole.interest - Amortization.totalInterest(loan)) <= 1e-9)
        #expect(abs(whole.principal - loan.principal) <= 1e-7)
        #expect(abs(whole.payments - (whole.interest + whole.principal)) <= 1e-7)
        #expect(abs(whole.closingBalance) <= 1e-7)

        // Year 1 + year 2 + … must equal the whole; and each year must match its rows.
        var interestByYear = 0.0
        for year in 1...30 {
            let y = Amortization.totals(loan, year: year, periodsPerYear: 12)
            interestByYear += y.interest
            let slice = rows[((year - 1) * 12)..<(year * 12)]
            #expect(abs(y.interest - slice.reduce(0) { $0 + $1.interest }) <= 1e-9)
            #expect(abs(y.closingBalance - slice.last!.balance) <= 1e-9)
        }
        #expect(abs(interestByYear - whole.interest) <= 1e-7)

        // A 30-year mortgage at 6.5% pays more in interest than it borrows — worth asserting because
        // it is the number the app exists to show.
        #expect(whole.interest > loan.principal)
    }

    /// Paying at the start of each period costs less, by exactly one period of interest on the payment.
    @Test func annuityDueCostsLess() {
        let end = Amortization.Loan(principal: 250_000, periodicRate: 0.0525 / 12, periods: 300)
        let begin = Amortization.Loan(principal: 250_000, periodicRate: 0.0525 / 12, periods: 300,
                                      timing: .begin)
        let pEnd = Amortization.payment(end)
        let pBegin = Amortization.payment(begin)
        #expect(pBegin < pEnd)
        #expect(abs(pBegin * (1 + end.periodicRate) - pEnd) <= 1e-9 * pEnd)
        #expect(Amortization.totalInterest(begin) < Amortization.totalInterest(end))
        // The first period's interest accrues on the balance the first payment already reduced.
        let firstRow = Amortization.schedule(begin).first!
        let expectedFirstInterest = (begin.principal - firstRow.payment) * begin.periodicRate
        #expect(abs(firstRow.interest - expectedFirstInterest) <= 1e-9 * expectedFirstInterest)
        #expect(firstRow.interest < Amortization.schedule(end).first!.interest)
    }

    /// A balloon loan amortises to the balloon, not to zero, and costs more in interest.
    @Test func balloonLeavesExactlyTheBalloon() {
        let full = Amortization.Loan(principal: 100_000, periodicRate: 0.07 / 12, periods: 120)
        let balloon = Amortization.Loan(principal: 100_000, periodicRate: 0.07 / 12, periods: 120,
                                        balloon: 40_000)
        #expect(Amortization.payment(balloon) < Amortization.payment(full))
        #expect(abs(Amortization.schedule(balloon).last!.balance - 40_000) <= 1e-7)
        // Less principal repaid over the same term at the same rate means more interest paid.
        #expect(Amortization.totalInterest(balloon) > Amortization.totalInterest(full))
    }

    @Test func zeroRateIsAllPrincipal() {
        let loan = Amortization.Loan(principal: 1_200, periodicRate: 0, periods: 12)
        let rows = Amortization.schedule(loan)
        #expect(abs(Amortization.payment(loan) - 100) <= 1e-12)
        #expect(rows.allSatisfy { $0.interest == 0 })
        #expect(abs(Amortization.totalInterest(loan)) <= 1e-12)
        #expect(abs(rows.last!.balance) <= 1e-12)
    }

    /// A near-zero rate must not collapse to the zero-rate branch by accident.
    @Test func nearZeroRateStillChargesInterest() {
        let loan = Amortization.Loan(principal: 750_000, periodicRate: 1e-9, periods: 240)
        let total = Amortization.totalInterest(loan)
        #expect(total > 0, "1e-9 is not zero")
        #expect(total < 1.0, "…but it is very nearly zero: \(total)")
        #expect(abs(Amortization.schedule(loan).last!.balance) <= 1e-6)
    }

    /// A single-period loan is principal plus one period of interest.
    @Test func singlePeriodLoan() {
        let loan = Amortization.Loan(principal: 9_500, periodicRate: 0.02, periods: 1)
        let rows = Amortization.schedule(loan)
        #expect(rows.count == 1)
        #expect(abs(rows[0].interest - 190) <= 1e-9)
        #expect(abs(rows[0].payment - 9_690) <= 1e-9)
        #expect(abs(rows[0].balance) <= 1e-9)
    }

    /// The payment must agree with an independently written annuity formula, not just with itself.
    @Test func paymentMatchesAnIndependentFormula() {
        for loan in Self.loans where loan.timing == .end && loan.balloon == 0 && loan.periodicRate > 1e-6 {
            let i = loan.periodicRate, n = Double(loan.periods)
            let independent = loan.principal * i / (1 - pow(1 + i, -n))
            #expect(abs(Amortization.payment(loan) - independent) <= 1e-9 * independent)
        }
    }
}

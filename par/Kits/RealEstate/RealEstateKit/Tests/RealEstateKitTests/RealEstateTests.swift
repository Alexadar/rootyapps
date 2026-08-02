import Testing
import Foundation
import RealEstateKit

/// **This Kit has no PUBLISHED oracles, and that is stated rather than hidden.**
///
/// Cap rate, DSCR, LTV and the rest are arithmetic definitions. A lender's term sheet or an agency
/// underwriting guide would provide a citable worked example; an attempt to obtain one from HUD's
/// Multifamily Accelerated Processing guide and a Fannie Mae multifamily term sheet failed on
/// 2026-07-27 (see `par/scratch/SOURCES.md` §7). Rather than transcribe a number from a blog and call it
/// ground truth, the corpus records the gap.
///
/// Per `calculators/VALIDATION.md`, everything here is *identity/definition* or *invariant* — and the
/// strongest of those is not a restated formula but a genuine cross-check: the loan `maxLoanByDSCR`
/// returns must, when amortised at the same rate and term, produce exactly the target coverage.
@Suite("Corpus classification")
struct CorpusClassificationTests {

    /// An explicit, failing-if-changed statement of the open item, so it cannot be forgotten.
    @Test func theMissingPublishedOracleIsRecorded() {
        let openItems = [
            "TODO(oracle): a published underwriting worked example (HUD MAP guide or an agency "
                + "multifamily term sheet) would upgrade maxLoanByDSCR from IDENTITY to PUBLISHED. "
                + "Attempted 2026-07-27, not obtained.",
        ]
        #expect(openItems.count == 1, "resolve or restate the open oracle item")
        #expect(openItems[0].contains("TODO(oracle)"))
    }
}

/// The definitions, their inversions, and the property that actually binds.
///
/// ORACLES:
///  • IDENTITY — cap rate ↔ value inversion; NOI from a rent roll; DSCR, LTV, GRM and cash-on-cash as
///    defined; the mortgage constant as the annuity it is.
///  • INVARIANT — the DSCR-sized loan reproduces the target coverage exactly; the smaller of the two
///    lender tests binds; leverage helps only when the cap rate exceeds the mortgage constant;
///    break-even occupancy is where cash flow is zero.
@Suite("Real estate — identity and invariant")
struct RealEstateIdentities {

    // A representative deal, used throughout: 24 units, $1,800/month, 5% vacancy, 38% expenses.
    static let grossPotentialRent = 24.0 * 1_800 * 12          // 518,400
    static let operatingExpenses = 197_000.0
    static let noi = RealEstate.netOperatingIncome(
        grossPotentialRent: grossPotentialRent, vacancyRate: 0.05,
        operatingExpenses: operatingExpenses
    )

    @Test func netOperatingIncomeFollowsTheRentRoll() {
        // 518,400 × 0.95 − 197,000 = 295,480
        #expect(abs(Self.noi - 295_480) <= 1e-9, "NOI \(Self.noi)")

        // Other income adds, reserves subtract, and both are explicit rather than assumed.
        let withExtras = RealEstate.netOperatingIncome(
            grossPotentialRent: Self.grossPotentialRent, vacancyRate: 0.05,
            otherIncome: 14_000, operatingExpenses: Self.operatingExpenses, reserves: 7_200
        )
        #expect(abs(withExtras - (Self.noi + 14_000 - 7_200)) <= 1e-9)

        // Effective gross income and the expense ratio agree with the NOI they imply.
        let egi = RealEstate.effectiveGrossIncome(
            grossPotentialRent: Self.grossPotentialRent, vacancyRate: 0.05
        )
        #expect(abs(egi - Self.operatingExpenses - Self.noi) <= 1e-9)
        let ratio = RealEstate.operatingExpenseRatio(
            operatingExpenses: Self.operatingExpenses, effectiveGrossIncome: egi
        )
        #expect(ratio > 0.39 && ratio < 0.41, "expense ratio \(ratio)")

        // Full vacancy is not allowed as an input (it would make the ratios meaningless), but a high
        // vacancy must simply reduce NOI.
        let stressed = RealEstate.netOperatingIncome(
            grossPotentialRent: Self.grossPotentialRent, vacancyRate: 0.35,
            operatingExpenses: Self.operatingExpenses
        )
        #expect(stressed < Self.noi)
    }

    @Test func capRateAndValueInvert() {
        let value = 5_400_000.0
        let rate = RealEstate.capRate(netOperatingIncome: Self.noi, value: value)
        #expect(abs(rate - Self.noi / value) <= 1e-15)
        #expect(abs(RealEstate.value(netOperatingIncome: Self.noi, capRate: rate) - value) <= 1e-6)

        // A lower cap rate means a higher price for the same income — the market's whole mechanism.
        var previous = 0.0
        for capRate in [0.075, 0.065, 0.055, 0.045] {
            let priced = RealEstate.value(netOperatingIncome: Self.noi, capRate: capRate)
            #expect(priced > previous)
            previous = priced
        }

        // 5.47% on this NOI is about 5.4 million.
        #expect(abs(RealEstate.value(netOperatingIncome: 295_480, capRate: 0.0547) - 5_401_828.15) <= 1)
    }

    /// The real test in this Kit: size a loan by coverage, amortise it, and the coverage must come back
    /// exactly. If the mortgage constant and the loan-sizing algebra disagree, this fails.
    @Test func theDSCRSizedLoanReproducesTheTargetCoverage() {
        for target in [1.15, 1.20, 1.25, 1.40] {
            for rate in [0.0, 4.5, 6.25, 9.0] {
                for years in [20.0, 25.0, 30.0] {
                    let loan = RealEstate.maxLoanByDSCR(
                        netOperatingIncome: Self.noi, targetDSCR: target,
                        annualRatePct: rate, amortizationYears: years
                    )
                    let service = RealEstate.annualDebtService(
                        loan: loan, annualRatePct: rate, amortizationYears: years
                    )
                    let achieved = RealEstate.debtServiceCoverageRatio(
                        netOperatingIncome: Self.noi, annualDebtService: service
                    )
                    #expect(abs(achieved - target) <= 1e-9 * target,
                            "target \(target) at \(rate)% over \(years)y produced \(achieved)")
                }
            }
        }
    }

    /// The mortgage constant must agree with an independently written annuity payment — the same check
    /// AmortKit's payment makes from the other side.
    @Test func mortgageConstantIsTheAnnuityItClaimsToBe() {
        for rate in [0.0, 3.0, 6.25, 12.0] {
            for years in [15.0, 30.0] {
                let i = rate / 100 / 12
                let n = years * 12
                let independentMonthly = i == 0 ? 1 / n : i / (1 - pow(1 + i, -n))
                let constant = RealEstate.mortgageConstant(
                    annualRatePct: rate, amortizationYears: years
                )
                #expect(abs(constant - independentMonthly * 12) <= 1e-12,
                        "rate \(rate), \(years)y: \(constant) vs \(independentMonthly * 12)")
            }
        }
        // A 6.25%, 30-year loan has a constant near 0.0739 — about 7.39 cents of annual debt service
        // per dollar borrowed.
        let constant = RealEstate.mortgageConstant(annualRatePct: 6.25, amortizationYears: 30)
        #expect(constant > 0.073 && constant < 0.075, "constant \(constant)")
    }

    @Test func theSmallerLenderTestBinds() {
        let value = 5_400_000.0
        // A low cap rate makes coverage the binding test.
        let tight = RealEstate.sizeLoan(
            netOperatingIncome: Self.noi, value: value, targetDSCR: 1.25, maxLTV: 0.75,
            annualRatePct: 6.25, amortizationYears: 30
        )
        #expect(tight.loan == min(tight.byDSCR, tight.byLTV))
        #expect(tight.dscrConstrained == (tight.byDSCR <= tight.byLTV))

        // A generous coverage requirement flips it to the LTV test.
        let loose = RealEstate.sizeLoan(
            netOperatingIncome: Self.noi, value: value, targetDSCR: 1.0, maxLTV: 0.55,
            annualRatePct: 6.25, amortizationYears: 30
        )
        #expect(loose.byLTV < loose.byDSCR)
        #expect(!loose.dscrConstrained)
        #expect(abs(loose.loan - value * 0.55) <= 1e-9)

        // And the loan is never more than either test allows.
        for sizing in [tight, loose] {
            #expect(sizing.loan <= sizing.byDSCR + 1e-9)
            #expect(sizing.loan <= sizing.byLTV + 1e-9)
            #expect(RealEstate.loanToValue(loan: sizing.loan, value: value) <= 0.75 + 1e-9)
        }
    }

    @Test func coverageBelowOneMeansNegativeCashFlow() {
        let service = RealEstate.annualDebtService(
            loan: 4_600_000, annualRatePct: 6.25, amortizationYears: 30
        )
        let dscr = RealEstate.debtServiceCoverageRatio(
            netOperatingIncome: Self.noi, annualDebtService: service
        )
        let cashFlow = RealEstate.cashFlowBeforeTax(
            netOperatingIncome: Self.noi, annualDebtService: service
        )
        // The two statements must always agree: DSCR < 1 ⟺ cash flow < 0.
        #expect((dscr < 1) == (cashFlow < 0), "DSCR \(dscr), cash flow \(cashFlow)")

        // At exactly 1.0 coverage, cash flow is exactly zero.
        let breakEvenLoan = RealEstate.maxLoanByDSCR(
            netOperatingIncome: Self.noi, targetDSCR: 1.0,
            annualRatePct: 6.25, amortizationYears: 30
        )
        let breakEvenService = RealEstate.annualDebtService(
            loan: breakEvenLoan, annualRatePct: 6.25, amortizationYears: 30
        )
        #expect(abs(RealEstate.cashFlowBeforeTax(netOperatingIncome: Self.noi,
                                                annualDebtService: breakEvenService)) <= 1e-6)
    }

    @Test func cashOnCashAndBreakEvenOccupancy() {
        let price = 5_400_000.0
        let loan = 3_800_000.0
        let service = RealEstate.annualDebtService(
            loan: loan, annualRatePct: 6.25, amortizationYears: 30
        )
        let cashFlow = RealEstate.cashFlowBeforeTax(
            netOperatingIncome: Self.noi, annualDebtService: service
        )
        let equity = price - loan
        let coc = RealEstate.cashOnCash(cashFlowBeforeTax: cashFlow, cashInvested: equity)
        #expect(abs(coc - cashFlow / equity) <= 1e-15)

        // Break-even occupancy: expenses plus debt service over gross potential rent.
        let occupancy = RealEstate.breakEvenOccupancy(
            operatingExpenses: Self.operatingExpenses, annualDebtService: service,
            grossPotentialRent: Self.grossPotentialRent
        )
        #expect(occupancy > 0 && occupancy < 1, "break-even occupancy \(occupancy)")
        // At exactly that occupancy, NOI equals debt service — the definition, checked.
        let atBreakEven = RealEstate.netOperatingIncome(
            grossPotentialRent: Self.grossPotentialRent, vacancyRate: 1 - occupancy,
            operatingExpenses: Self.operatingExpenses
        )
        #expect(abs(atBreakEven - service) <= 1e-6, "NOI \(atBreakEven) vs service \(service)")
    }

    /// Leverage only helps when the asset out-yields the debt. Stated as a predicate and then verified
    /// against the arithmetic it summarises, because this is the sentence that decides a deal.
    @Test func leverageHelpsOnlyAboveTheMortgageConstant() {
        let price = 5_400_000.0
        let constant = RealEstate.mortgageConstant(annualRatePct: 6.25, amortizationYears: 30)

        for capRate in [0.045, 0.06, 0.0739, 0.09, 0.12] {
            let noi = price * capRate
            let loan = price * 0.65
            let service = RealEstate.annualDebtService(
                loan: loan, annualRatePct: 6.25, amortizationYears: 30
            )
            let unlevered = capRate
            let levered = RealEstate.cashOnCash(
                cashFlowBeforeTax: RealEstate.cashFlowBeforeTax(netOperatingIncome: noi,
                                                               annualDebtService: service),
                cashInvested: price - loan
            )
            let predicted = RealEstate.leveragedReturnIsPositive(
                capRate: capRate, mortgageConstant: constant
            )
            #expect(predicted == (levered > unlevered),
                    "cap \(capRate): predicate said \(predicted), levered \(levered) vs \(unlevered)")
        }
    }

    @Test func perUnitAndPerAreaAndGRM() {
        #expect(abs(RealEstate.pricePerUnit(price: 5_400_000, units: 24) - 225_000) <= 1e-9)
        #expect(abs(RealEstate.pricePerArea(price: 5_400_000, area: 21_600) - 250) <= 1e-9)
        let grm = RealEstate.grossRentMultiplier(price: 5_400_000, annualGrossRent: Self.grossPotentialRent)
        #expect(abs(grm - 5_400_000 / Self.grossPotentialRent) <= 1e-15)
        #expect(grm > 10 && grm < 11, "GRM \(grm)")
    }

    /// A zero-rate loan is interest-free amortisation: the constant is simply 1/term.
    @Test func zeroRateLoanIsPurePrincipal() {
        let constant = RealEstate.mortgageConstant(annualRatePct: 0, amortizationYears: 25)
        #expect(abs(constant - 1.0 / 25) <= 1e-15)
        let service = RealEstate.annualDebtService(loan: 1_000_000, annualRatePct: 0, amortizationYears: 25)
        #expect(abs(service - 40_000) <= 1e-9)
    }

    // Tape replay moved to `ReplayTests.swift`, matching the other nine Kits — and gained the
    // INVARIANT half it lacked here, now that the decoder rejects a sizing `sizeLoan` could not
    // have produced.
}

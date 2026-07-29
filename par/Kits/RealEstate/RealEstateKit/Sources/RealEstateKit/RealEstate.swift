import Foundation

/// Income-property underwriting: net operating income, the capitalisation rate, coverage and leverage
/// ratios, and the two loan-sizing tests every commercial lender applies. Pure, stateless.
///
/// MODEL CAVEAT (these are ratio definitions, not conventions): cap rate, DSCR, LTV and the rest are
/// arithmetic definitions, and this Kit carries **no published worked examples** for them. A lender's
/// term sheet would supply one, and an attempt to obtain a citable underwriting example from HUD's MAP
/// guide or a Fannie Mae multifamily term sheet did not succeed — recorded as an open item rather than
/// papered over with a plausible-looking number. What the tests assert instead is each definition, the
/// inversions between them, and the one property that actually binds: the loan `maxLoanByDSCR` returns
/// must, when amortised, produce exactly the target coverage.
///
/// MODEL CAVEAT (annual figures): NOI, debt service and income are annual amounts. Debt service is the
/// *annualised* payment — twelve monthly payments, not one.
///
/// MODEL CAVEAT (NOI excludes debt service and capital items): net operating income is income after
/// operating expenses and before debt service, income tax, depreciation and capital expenditure. Whether
/// reserves belong above or below the line is a matter of underwriting policy, so `reserves` is a
/// separate, explicit input rather than a hidden assumption.
public enum RealEstate {

    // MARK: - Income

    /// Net operating income from a rent roll.
    ///
    /// `NOI = grossPotentialRent × (1 − vacancy) + otherIncome − operatingExpenses − reserves`
    public static func netOperatingIncome(
        grossPotentialRent: Double,
        vacancyRate: Double,
        otherIncome: Double = 0,
        operatingExpenses: Double,
        reserves: Double = 0
    ) -> Double {
        precondition(grossPotentialRent >= 0, "gross potential rent must be >= 0")
        precondition(vacancyRate >= 0 && vacancyRate < 1, "vacancy must be a fraction in [0, 1)")
        precondition(operatingExpenses >= 0, "operating expenses must be >= 0")
        precondition(reserves >= 0, "reserves must be >= 0")
        return grossPotentialRent * (1 - vacancyRate) + otherIncome - operatingExpenses - reserves
    }

    /// Effective gross income: gross potential rent less vacancy, plus other income.
    public static func effectiveGrossIncome(
        grossPotentialRent: Double, vacancyRate: Double, otherIncome: Double = 0
    ) -> Double {
        precondition(vacancyRate >= 0 && vacancyRate < 1, "vacancy must be a fraction in [0, 1)")
        return grossPotentialRent * (1 - vacancyRate) + otherIncome
    }

    /// Operating expense ratio: expenses over effective gross income.
    public static func operatingExpenseRatio(
        operatingExpenses: Double, effectiveGrossIncome: Double
    ) -> Double {
        precondition(effectiveGrossIncome > 0, "effective gross income must be > 0")
        return operatingExpenses / effectiveGrossIncome
    }

    // MARK: - Value and yield

    /// Capitalisation rate: NOI over value.
    public static func capRate(netOperatingIncome: Double, value: Double) -> Double {
        precondition(value > 0, "value must be > 0")
        return netOperatingIncome / value
    }

    /// Value implied by a cap rate — the inverse of `capRate`, and how income property is actually priced.
    public static func value(netOperatingIncome: Double, capRate: Double) -> Double {
        precondition(capRate > 0, "cap rate must be > 0")
        return netOperatingIncome / capRate
    }

    /// Gross rent multiplier: price over annual gross rent. A screening ratio, not a valuation.
    public static func grossRentMultiplier(price: Double, annualGrossRent: Double) -> Double {
        precondition(annualGrossRent > 0, "gross rent must be > 0")
        return price / annualGrossRent
    }

    /// Price per unit.
    public static func pricePerUnit(price: Double, units: Int) -> Double {
        precondition(units > 0, "units must be > 0")
        return price / Double(units)
    }

    /// Price per square foot (or per square metre — the Kit does not care which, as long as the caller
    /// is consistent).
    public static func pricePerArea(price: Double, area: Double) -> Double {
        precondition(area > 0, "area must be > 0")
        return price / area
    }

    // MARK: - Debt

    /// Debt service coverage ratio: NOI over annual debt service. Below 1.0 the property cannot pay its
    /// own mortgage.
    public static func debtServiceCoverageRatio(
        netOperatingIncome: Double, annualDebtService: Double
    ) -> Double {
        precondition(annualDebtService > 0, "annual debt service must be > 0")
        return netOperatingIncome / annualDebtService
    }

    /// Loan to value.
    public static func loanToValue(loan: Double, value: Double) -> Double {
        precondition(value > 0, "value must be > 0")
        return loan / value
    }

    /// The annual constant: the annual debt service per unit of loan, for a fully amortising loan.
    ///
    /// `12 · i/(1 − (1+i)⁻ⁿ)` with a monthly rate — written out here because a Kit takes no
    /// dependencies. AmortKit solves the same annuity from the other side and the tests check they agree.
    public static func mortgageConstant(annualRatePct: Double, amortizationYears: Double) -> Double {
        precondition(annualRatePct >= 0, "rate must be >= 0")
        precondition(amortizationYears > 0, "amortization must be > 0")
        let i = annualRatePct / 100 / 12
        let n = amortizationYears * 12
        if i == 0 { return 12 / n }
        return 12 * i / -expm1(-n * log1p(i))
    }

    /// Annual debt service on a loan.
    public static func annualDebtService(
        loan: Double, annualRatePct: Double, amortizationYears: Double
    ) -> Double {
        loan * mortgageConstant(annualRatePct: annualRatePct, amortizationYears: amortizationYears)
    }

    /// The largest loan whose debt service leaves the target coverage — the DSCR-constrained loan.
    ///
    /// `loan = (NOI / targetDSCR) / mortgageConstant`
    public static func maxLoanByDSCR(
        netOperatingIncome: Double, targetDSCR: Double,
        annualRatePct: Double, amortizationYears: Double
    ) -> Double {
        precondition(netOperatingIncome > 0, "NOI must be > 0 to support any loan")
        precondition(targetDSCR > 0, "target DSCR must be > 0")
        let affordableDebtService = netOperatingIncome / targetDSCR
        return affordableDebtService
            / mortgageConstant(annualRatePct: annualRatePct, amortizationYears: amortizationYears)
    }

    /// The LTV-constrained loan.
    public static func maxLoanByLTV(value: Double, maxLTV: Double) -> Double {
        precondition(value > 0, "value must be > 0")
        precondition(maxLTV > 0, "max LTV must be > 0")
        return value * maxLTV
    }

    /// What a lender will actually offer: the smaller of the two tests, and which one bound.
    public struct LoanSizing: Equatable, Sendable, Codable {
        public let byDSCR: Double
        public let byLTV: Double
        public let loan: Double
        /// True when the coverage test is what limits the loan — the common case in a low-cap-rate market,
        /// and the thing a borrower needs to know before negotiating.
        public let dscrConstrained: Bool
    }

    /// Size a loan against both tests at once.
    ///
    /// The two structural facts this establishes — that `loan` is the smaller test and that
    /// `dscrConstrained` names which one bound — are re-checked when a `LoanSizing` is decoded (see
    /// the extension at the foot of this file). A sizing that arrives from disk claiming a loan
    /// neither test supports is not a rounding difference; it is a corrupt file.
    public static func sizeLoan(
        netOperatingIncome: Double, value: Double, targetDSCR: Double, maxLTV: Double,
        annualRatePct: Double, amortizationYears: Double
    ) -> LoanSizing {
        let byDSCR = maxLoanByDSCR(
            netOperatingIncome: netOperatingIncome, targetDSCR: targetDSCR,
            annualRatePct: annualRatePct, amortizationYears: amortizationYears
        )
        let byLTV = maxLoanByLTV(value: value, maxLTV: maxLTV)
        return LoanSizing(
            byDSCR: byDSCR, byLTV: byLTV,
            loan: min(byDSCR, byLTV), dscrConstrained: byDSCR <= byLTV
        )
    }

    // MARK: - Equity returns

    /// Cash flow after debt service.
    public static func cashFlowBeforeTax(
        netOperatingIncome: Double, annualDebtService: Double
    ) -> Double {
        netOperatingIncome - annualDebtService
    }

    /// Cash-on-cash return: cash flow after debt service over cash invested. Also the equity dividend rate.
    public static func cashOnCash(cashFlowBeforeTax: Double, cashInvested: Double) -> Double {
        precondition(cashInvested > 0, "cash invested must be > 0")
        return cashFlowBeforeTax / cashInvested
    }

    /// Break-even occupancy: the occupancy at which income exactly covers operating expenses and debt
    /// service. Above 1.0 the deal cannot break even at any occupancy.
    public static func breakEvenOccupancy(
        operatingExpenses: Double, annualDebtService: Double, grossPotentialRent: Double
    ) -> Double {
        precondition(grossPotentialRent > 0, "gross potential rent must be > 0")
        return (operatingExpenses + annualDebtService) / grossPotentialRent
    }

    /// The cap rate at which a property must be bought for a given cash-on-cash return, given the debt —
    /// the algebraic link between the yield on the asset and the yield on the equity.
    public static func leveragedReturnIsPositive(
        capRate: Double, mortgageConstant: Double
    ) -> Bool {
        capRate > mortgageConstant
    }
}

// MARK: - Decoding a sizing that was never produced by `sizeLoan`

extension RealEstate.LoanSizing {
    /// A stored sizing is untrusted input.
    ///
    /// The synthesized decoder accepts any four well-formed values, so a hand-edited tape could
    /// present a loan larger than either test supports, or say the coverage test bound when the
    /// value test did — and the app would render it as a lender's offer. The two invariants
    /// `RealEstate.sizeLoan` establishes are re-checked here instead, and a file that breaks them
    /// throws rather than being drawn.
    ///
    /// Declared in an extension so the memberwise initialiser `sizeLoan` uses is still synthesized.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let byDSCR = try container.decode(Double.self, forKey: .byDSCR)
        let byLTV = try container.decode(Double.self, forKey: .byLTV)
        let loan = try container.decode(Double.self, forKey: .loan)
        let dscrConstrained = try container.decode(Bool.self, forKey: .dscrConstrained)

        func fail(_ why: String) -> DecodingError {
            DecodingError.dataCorrupted(
                .init(codingPath: container.codingPath, debugDescription: why))
        }
        guard byDSCR.isFinite, byLTV.isFinite, loan.isFinite else {
            throw fail("a loan sizing must be finite")
        }
        guard byDSCR >= 0, byLTV >= 0 else {
            throw fail("neither test can support a negative loan")
        }
        guard loan == Swift.min(byDSCR, byLTV) else {
            throw fail("a lender offers the smaller of the two tests: \(loan) is not min(\(byDSCR), \(byLTV))")
        }
        guard dscrConstrained == (byDSCR <= byLTV) else {
            throw fail("the binding test does not match the two limits")
        }
        self.init(byDSCR: byDSCR, byLTV: byLTV, loan: loan, dscrConstrained: dscrConstrained)
    }
}

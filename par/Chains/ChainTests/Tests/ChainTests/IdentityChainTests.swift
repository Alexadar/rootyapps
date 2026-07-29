import Testing
import Foundation
import ChainSupport
import DayCountKit
import TVMKit
import AmortKit
import CashFlowKit
import RateKit
import BondKit
import DepKit
import PercentKit
import StatKit
import RealEstateKit

/// Chains that are algebraic identities: two Kits computing the same quantity by different routes must
/// land on the same number. No published value is available for these — they are definitions meeting
/// across a boundary — so the assertion is equality to floating point, not to a tolerance, wherever the
/// arithmetic permits it.
///
/// ORACLES:
///  • IDENTITY — 26 chains, listed by id in `Chain.matrix`.
@Suite("Identity chains")
struct IdentityChainTests {

    // MARK: DayCountKit → the period-counting Kits

    /// `dates-to-apy-term`: a term stated in dates must give RateKit the day count its APY formula needs.
    @Test func datesToAPYTerm() {
        let open = DayCount.YearMonthDay(2026, 1, 15)
        let maturity = DayCount.YearMonthDay(2026, 7, 15)
        let days = DayCount.actualDays(from: open, to: maturity)
        #expect(days == 181)

        let apy = Rate.apy(interest: 30.37, principal: 1_000, daysInTerm: Double(days))
        // The same deposit over a 182-day term yields slightly less per year — the exponent is the term.
        let longer = Rate.apy(interest: 30.37, principal: 1_000, daysInTerm: 182)
        #expect(apy > longer)
        #expect(abs(apy - 100 * (pow(1 + 30.37 / 1_000, 365.0 / Double(days)) - 1)) <= 1e-9)
    }

    /// `dates-to-payment-schedule`: monthly payment dates generated from a start date must be the count
    /// AmortKit amortises over, month-end clamping included.
    @Test func datesToPaymentSchedule() {
        let first = DayCount.YearMonthDay(2026, 1, 31)
        var dates: [DayCount.YearMonthDay] = []
        for month in 0..<12 { dates.append(DayCount.date(first, byAddingMonths: month)) }

        #expect(dates.count == 12)
        #expect(dates[1] == DayCount.YearMonthDay(2026, 2, 28), "January 31 + 1 month clamps to February")
        #expect(dates.last == DayCount.YearMonthDay(2026, 12, 31))

        let loan = Amortization.Loan(principal: 12_000, periodicRate: 0.06 / 12, periods: dates.count)
        #expect(Amortization.schedule(loan).count == dates.count)
    }

    /// `dates-to-term-in-periods`: a term in dates converts to TVM periods, and back.
    @Test func datesToTermInPeriods() throws {
        let start = DayCount.YearMonthDay(2026, 7, 27)
        let end = DayCount.YearMonthDay(2056, 7, 27)
        let years = Double(DayCount.actualDays(from: start, to: end)) / 365.25
        let periods = (years * 12).rounded()
        #expect(periods == 360, "thirty years is 360 monthly periods, got \(periods)")

        let payment = try TVM.solve(for: .payment, .init(
            periods: periods, annualRatePct: 6.25, presentValue: 420_000,
            paymentsPerYear: 12, compoundsPerYear: 12
        ))
        #expect(payment < 0 && abs(payment) > 2_000)
    }

    /// `dates-to-flow-periods`: dated cash flows become integer-period flows for CashFlowKit, and the
    /// mapping must be exact for evenly spaced dates.
    @Test func datesToFlowPeriods() {
        let base = DayCount.YearMonthDay(2026, 1, 1)
        let dates = (0...4).map { DayCount.date(base, byAddingMonths: $0 * 12) }
        let periods = dates.map { Double(DayCount.actualDays(from: base, to: $0)) / 365.25 }
        #expect(periods.map { ($0).rounded() } == [0, 1, 2, 3, 4])

        let flows: [Double] = [-1_000, 300, 300, 300, 300]
        #expect(flows.count == dates.count)
        #expect(abs(CashFlow.npv(rate: 0.08, flows: flows)
                    - flows.enumerated().reduce(0) { $0 + $1.element / pow(1.08, Double($1.offset)) })
                <= 1e-9)
    }

    // MARK: TVMKit outward

    /// `tvm-to-npv-of-the-same-flows`: a TVM present value is the NPV of the flows it describes.
    @Test func tvmToNPVOfTheSameFlows() throws {
        let registers = TVM.Registers(periods: 24, annualRatePct: 9.69, payment: -230,
                                      futureValue: 0, paymentsPerYear: 12, compoundsPerYear: 12)
        let presentValue = try TVM.solve(for: .presentValue, registers)

        var flows: [Double] = [0]
        flows.append(contentsOf: Array(repeating: -230.0, count: 24))
        let npv = CashFlow.npv(rate: 0.0969 / 12, flows: flows)
        #expect(abs(presentValue + npv) <= 1e-9, "PV \(presentValue) vs −NPV \(-npv)")
    }

    /// `compounded-series-to-exponential-fit` and `exponential-fit-to-growth-rate`: a balance compounded
    /// at a known rate, fitted exponentially, must give that rate back.
    @Test func compoundedSeriesToExponentialFit() throws {
        let rate = 0.0625 / 12
        let periods = Array(1...36).map(Double.init)
        let balances = periods.map { 10_000 * pow(1 + rate, $0) }

        let fit = try Stat.fit(x: periods, y: balances, model: .exponential)
        #expect(abs(exp(fit.slope) - (1 + rate)) <= 1e-9,
                "recovered monthly growth \(exp(fit.slope) - 1) vs \(rate)")
        #expect(abs(fit.rSquared - 1) <= 1e-12)

        // …and that rate, handed back to TVM, reproduces the final balance.
        let futureValue = try TVM.solve(for: .futureValue, .init(
            periods: 36, annualRatePct: 6.25, presentValue: -10_000,
            paymentsPerYear: 12, compoundsPerYear: 12
        ))
        #expect(abs(futureValue - balances.last!) <= 1e-6)
    }

    /// `tvm-payment-to-mortgage-constant` and `mortgage-constant-to-tvm-payment`: the annual constant is
    /// twelve TVM payments per unit of loan, from either direction.
    @Test func tvmPaymentAndMortgageConstantAgree() throws {
        for rate in [0.0, 4.5, 6.25, 9.0] {
            for years in [15.0, 25.0, 30.0] {
                let payment = try TVM.solve(for: .payment, .init(
                    periods: years * 12, annualRatePct: rate, presentValue: 1,
                    paymentsPerYear: 12, compoundsPerYear: 12
                ))
                let constant = RealEstate.mortgageConstant(annualRatePct: rate, amortizationYears: years)
                #expect(abs(abs(payment) * 12 - constant) <= 1e-12,
                        "\(rate)% over \(years)y: TVM \(abs(payment) * 12) vs constant \(constant)")
            }
        }
    }

    /// `tvm-periodic-rate-to-effective-rate` and `rate-to-mortgage-constant`: TVM's periodic rate
    /// compounds to RateKit's effective annual rate, and RateKit's rate sizes a mortgage constant.
    @Test func periodicRateToEffectiveRate() {
        for nominal in [3.0, 6.25, 18.99] {
            for m in [1, 2, 4, 12, 52] {
                let periodic = TVM.periodicRate(annualRatePct: nominal, paymentsPerYear: m,
                                                compoundsPerYear: m)
                let effectiveFromTVM = 100 * (pow(1 + periodic, Double(m)) - 1)
                let effective = Rate.effectiveAnnualRate(nominalPct: nominal, timesPerYear: m)
                #expect(abs(effectiveFromTVM - effective) <= 1e-9,
                        "\(nominal)% at m=\(m): \(effectiveFromTVM) vs \(effective)")
            }
        }

        // A rate quoted as effective must be converted back to nominal before sizing a loan, and the two
        // constants differ — the conversion is load-bearing, not cosmetic.
        let nominal = Rate.nominalAnnualRate(effectivePct: 6.5, timesPerYear: 12)
        let correct = RealEstate.mortgageConstant(annualRatePct: nominal, amortizationYears: 30)
        let naive = RealEstate.mortgageConstant(annualRatePct: 6.5, amortizationYears: 30)
        #expect(correct < naive)
        #expect(naive - correct > 1e-4)
    }

    // MARK: AmortKit outward

    /// `schedule-to-npv-equals-principal`: discounting a loan's own payments at its own rate returns the
    /// principal. The cleanest cross-Kit identity in the project.
    @Test func scheduleToNPVEqualsPrincipal() {
        for (principal, rate, periods) in [(400_000.0, 0.065 / 12, 360), (5_000.0, 0.0969 / 12, 24),
                                           (12_000.0, 0.0, 12)] {
            let loan = Amortization.Loan(principal: principal, periodicRate: rate, periods: periods)
            var flows: [Double] = [0]
            flows.append(contentsOf: Amortization.schedule(loan).map(\.payment))
            let npv = CashFlow.npv(rate: rate, flows: flows)
            #expect(abs(npv - principal) <= 1e-6 * principal,
                    "discounted payments \(npv) vs principal \(principal)")
        }
    }

    /// `remaining-balance-to-tvm-future-value`: the balance after k payments is the TVM future value at
    /// n = k. Two Kits, one number.
    @Test func remainingBalanceToTVMFutureValue() throws {
        let loan = Amortization.Loan(principal: 400_000, periodicRate: 0.065 / 12, periods: 360)
        let payment = Amortization.payment(loan)
        for k in [1, 12, 60, 180, 359] {
            let scheduled = Amortization.balance(loan, after: k)
            let tvm = try TVM.solve(for: .futureValue, .init(
                periods: Double(k), annualRatePct: 6.5, presentValue: 400_000, payment: -payment,
                paymentsPerYear: 12, compoundsPerYear: 12
            ))
            #expect(abs(scheduled + tvm) <= 1e-6 * 400_000,
                    "after \(k): schedule \(scheduled), TVM \(-tvm)")
        }
    }

    /// `schedule-to-annual-debt-service` and `sized-loan-to-schedule`: twelve scheduled payments are the
    /// annual debt service the coverage ratio is measured against, and a DSCR-sized loan amortises to
    /// exactly that coverage.
    @Test func scheduleToAnnualDebtService() {
        let noi = 295_480.0
        let loan = RealEstate.maxLoanByDSCR(
            netOperatingIncome: noi, targetDSCR: 1.25, annualRatePct: 6.25, amortizationYears: 30
        )
        let schedule = Amortization.schedule(
            .init(principal: loan, periodicRate: 0.0625 / 12, periods: 360)
        )
        let firstYear = schedule.prefix(12).reduce(0) { $0 + $1.payment }
        let dscr = RealEstate.debtServiceCoverageRatio(
            netOperatingIncome: noi, annualDebtService: firstYear
        )
        #expect(abs(dscr - 1.25) <= 1e-9, "amortised coverage \(dscr)")
        #expect(abs(firstYear - RealEstate.annualDebtService(
            loan: loan, annualRatePct: 6.25, amortizationYears: 30)) <= 1e-6)
    }

    // MARK: CashFlowKit outward

    /// `npv-of-level-flows-to-tvm-present-value`: CashFlowKit's uniform present value is TVM's annuity
    /// factor, at every rate including zero.
    @Test func uniformPresentValueIsTheAnnuityFactor() {
        for rate in [0.0, 1e-9, 0.004, 0.0625 / 12, 0.5] {
            for n in [1.0, 12.0, 360.0] {
                let upv = CashFlow.uniformPresentValue(rate: rate, periods: n)
                let annuity = TVM.annuityFactor(periodicRate: rate, periods: n)
                #expect(abs(upv - annuity) <= 1e-12 * max(upv, 1),
                        "r=\(rate), n=\(n): \(upv) vs \(annuity)")
            }
        }
    }

    /// `npv-of-property-flows` and `property-flows-to-npv`: a property's cash flows discounted must equal
    /// the value its cap rate implies when the flows are level and perpetual-equivalent.
    @Test func propertyFlowsToNPV() {
        let noi = 295_480.0
        let capRate = 0.0547
        let value = RealEstate.value(netOperatingIncome: noi, capRate: capRate)

        // A level perpetuity at the cap rate: NPV over a long horizon approaches the capitalised value.
        var flows: [Double] = [0]
        flows.append(contentsOf: Array(repeating: noi, count: 600))
        let npv = CashFlow.npv(rate: capRate, flows: flows)
        #expect(abs(npv - value) / value < 0.001,
                "600 years of NOI discounted (\(npv)) approaches the capitalised value (\(value))")

        // With a sale at the horizon, the match is exact at any horizon.
        var withSale: [Double] = [0]
        withSale.append(contentsOf: Array(repeating: noi, count: 10))
        withSale[10] += value
        #expect(abs(CashFlow.npv(rate: capRate, flows: withSale) - value) <= 1e-6 * value)
    }

    // MARK: BondKit and RateKit

    /// `effective-rate-to-bond-yield` and `bond-yield-to-effective-rate`: a nominal semiannual bond yield
    /// and RateKit's effective annual rate are the same rate stated two ways.
    @Test func bondYieldToEffectiveRate() {
        for yield in [0.02, 0.0442, 0.0884, 0.1047] {
            let effective = Rate.effectiveAnnualRate(nominalPct: yield * 100, timesPerYear: 2)
            let byHand = 100 * (pow(1 + yield / 2, 2) - 1)
            #expect(abs(effective - byHand) <= 1e-12)

            // A bond priced at par yields its coupon nominally, and more than that effectively.
            let terms = Bond.Terms(couponPct: yield * 100, fullPeriods: 20,
                                   daysToNextCoupon: 182, daysInPeriod: 182)
            #expect(abs(Bond.price(terms, yield: yield) - 100) <= 1e-9)
            #expect(effective > yield * 100 || yield == 0)
        }
    }

    /// `bond-yield-to-tvm-discounting`: BondKit's discount and annuity factors are TVM's, at the
    /// semiannual rate.
    @Test func bondYieldToTVMDiscounting() {
        for yield in [0.0, 0.0442, 0.0954, 0.1047] {
            for n in [1, 19, 39, 59] {
                #expect(abs(Bond.discountFactor(yield: yield, periods: n)
                            - TVM.discountFactor(periodicRate: yield / 2, periods: Double(n))) <= 1e-15)
                #expect(abs(Bond.annuityFactor(yield: yield, periods: n)
                            - TVM.annuityFactor(periodicRate: yield / 2, periods: Double(n)))
                        <= 1e-9 * max(Double(n), 1))
            }
        }
    }

    // MARK: DepKit and PercentKit

    /// `deduction-to-share-of-basis`: each MACRS deduction is that year's published percentage of basis,
    /// as PercentKit computes a share.
    @Test func deductionToShareOfBasis() {
        let asset = Depreciation.Asset(cost: 10_000, recoveryYears: 7)
        let percentages = Depreciation.macrsPercentages(recoveryYears: 7, convention: .halfYear)
        for row in Depreciation.macrs(asset) {
            let share = Percent.share(part: row.depreciation, whole: asset.cost)
            #expect(abs(share - percentages[row.year - 1]) <= 1e-9,
                    "year \(row.year): \(share)% vs published \(percentages[row.year - 1])%")
        }
        #expect(abs(Percent.share(part: Depreciation.macrs(asset).reduce(0) { $0 + $1.depreciation },
                                 whole: asset.cost) - 100) <= 1e-9)
    }

    /// `break-even-volume-to-break-even-occupancy` and `occupancy-to-break-even`: the same break-even
    /// idea in two domains must agree when the property is modelled as units of rent.
    @Test func breakEvenVolumeToBreakEvenOccupancy() {
        let units = 24.0
        let annualRentPerUnit = 1_800.0 * 12
        let operatingExpenses = 197_000.0
        let debtService = 180_000.0

        let occupancy = RealEstate.breakEvenOccupancy(
            operatingExpenses: operatingExpenses, annualDebtService: debtService,
            grossPotentialRent: units * annualRentPerUnit
        )
        // The same question as PercentKit's: how many units must be let to cover fixed costs, with no
        // variable cost per unit?
        let unitsNeeded = Percent.breakEvenUnits(
            fixedCosts: operatingExpenses + debtService,
            pricePerUnit: annualRentPerUnit, variableCostPerUnit: 0
        )
        #expect(abs(unitsNeeded / units - occupancy) <= 1e-9,
                "\(unitsNeeded) of \(units) units is \(unitsNeeded / units), occupancy says \(occupancy)")
    }

    /// `margin-to-flow-vector`: a margin applied to a revenue plan produces the flow vector NPV discounts.
    @Test func marginToFlowVector() {
        let revenue = [0.0, 250_000, 300_000, 360_000]
        let margin = 22.5
        let flows = revenue.map { Percent.of(percent: margin, value: $0) }
        #expect(abs(flows[1] - 56_250) <= 1e-9)

        var withInvestment = flows
        withInvestment[0] = -150_000
        let npv = CashFlow.npv(rate: 0.12, flows: withInvestment)
        #expect(npv > 0, "a 22.5% margin on this plan clears a 12% hurdle: NPV \(npv)")
        // Halve the margin and it should not.
        let thin = revenue.map { Percent.of(percent: margin / 2, value: $0) }
        var thinWithInvestment = thin
        thinWithInvestment[0] = -150_000
        #expect(CashFlow.npv(rate: 0.12, flows: thinWithInvestment) < 0)
    }

    /// `forecast-to-flow-vector`: a regression forecast feeding a cash-flow projection.
    @Test func forecastToFlowVector() throws {
        let periods: [Double] = [1, 2, 3, 4, 5]
        let revenue: [Double] = [100_000, 112_000, 125_440, 140_492.8, 157_351.936]  // exactly 12% growth

        let fit = try Stat.fit(x: periods, y: revenue, model: .exponential)
        #expect(abs(exp(fit.slope) - 1.12) <= 1e-9, "recovered growth \(exp(fit.slope) - 1)")

        // The series is indexed from x = 1, so y(x) = 100,000 × 1.12^(x−1): the forecast at x = 6 is the
        // *fifth* year of growth, not the sixth. Getting that off by one is the classic projection bug,
        // so the expectation states the exponent explicitly.
        let projected = (6...10).map { Stat.forecastY(x: Double($0), fit: fit) }
        for (index, value) in projected.enumerated() {
            let x = 6 + index
            let expected = 100_000 * pow(1.12, Double(x - 1))
            #expect(abs(value - expected) <= 1e-6 * expected,
                    "x=\(x): forecast \(value), expected \(expected)")
        }

        var flows: [Double] = [-400_000]
        flows.append(contentsOf: projected)
        #expect(CashFlow.irr(flows: flows).rate != nil, "a projected series must still yield one IRR")
    }
}

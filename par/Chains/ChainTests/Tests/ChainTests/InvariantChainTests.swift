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

/// Chains where the two Kits are not computing the same number, but the relationship between them must
/// hold in a direction: accelerating a deduction is worth something, a longer accrual is worth more, a
/// thinner margin needs more volume. These catch sign errors and inverted comparisons — the class of bug
/// that survives every equality test because nothing is equal.
///
/// ORACLES:
///  • INVARIANT — 14 chains, listed by id in `Chain.matrix`.
@Suite("Invariant chains")
struct InvariantChainTests {

    /// `dates-to-placed-in-service-convention`: the month an asset is placed in service selects the
    /// MACRS convention, and a later quarter must mean a smaller first-year deduction.
    @Test func datesToPlacedInServiceConvention() {
        func convention(for date: DayCount.YearMonthDay) -> Depreciation.Convention {
            switch date.month {
            case 1...3: return .midQuarterFirst
            case 4...6: return .midQuarterSecond
            case 7...9: return .midQuarterThird
            default: return .midQuarterFourth
            }
        }

        let dates = [
            DayCount.YearMonthDay(2026, 2, 14), DayCount.YearMonthDay(2026, 5, 30),
            DayCount.YearMonthDay(2026, 8, 11), DayCount.YearMonthDay(2026, 11, 3),
        ]
        var previous = Double.infinity
        for date in dates {
            let first = Depreciation.macrsPercentages(
                recoveryYears: 7, convention: convention(for: date)
            )[0]
            #expect(first < previous, "\(date) should give a smaller first-year deduction")
            previous = first
        }
        // And every quarter still recovers the whole basis.
        for date in dates {
            let total = Depreciation.macrsPercentages(
                recoveryYears: 7, convention: convention(for: date)
            ).reduce(0, +)
            #expect(abs(total - 100) <= 1e-9)
        }
    }

    /// `tvm-annuity-to-bond-price-components`: a bond's price is an annuity of coupons plus a discounted
    /// redemption, so TVM's factors must account for it exactly.
    @Test func tvmAnnuityToBondPriceComponents() {
        let coupon = 8.75 / 2, n = 59, yield = 0.0884
        let annuity = TVM.annuityFactor(periodicRate: yield / 2, periods: Double(n))
        let discount = TVM.discountFactor(periodicRate: yield / 2, periods: Double(n))
        let assembled = (coupon + coupon * annuity + 100 * discount) / (1 + yield / 2)

        let terms = Bond.Terms(couponPct: 8.75, fullPeriods: n, daysToNextCoupon: 184, daysInPeriod: 184)
        #expect(abs(assembled - Bond.price(terms, yield: yield)) <= 1e-9,
                "assembled from TVM factors: \(assembled)")
    }

    /// `balance-series-to-regression`: an amortising balance is convex, so a straight line fits it
    /// poorly and an exponential fit does better — the shape a UI would draw.
    @Test func balanceSeriesToRegression() throws {
        let loan = Amortization.Loan(principal: 400_000, periodicRate: 0.065 / 12, periods: 360)
        let rows = Amortization.schedule(loan)
        let x = rows.map { Double($0.index) }
        let balances = rows.map(\.balance).map { max($0, 1) }

        let linear = try Stat.fit(x: x, y: balances, model: .linear)
        #expect(linear.slope < 0, "a balance falls")
        #expect(linear.rSquared < 0.99, "…but not in a straight line: R² \(linear.rSquared)")

        // Early balances fall slower than late ones: the second half sheds more principal than the first.
        let firstHalf = rows[0].balance - rows[179].balance
        let secondHalf = rows[179].balance - rows[359].balance
        #expect(secondHalf > firstHalf, "amortisation accelerates")
    }

    /// `interest-share-of-payment`: the interest share of a payment falls monotonically, and starts above
    /// half for a long mortgage — the fact every borrower is surprised by.
    @Test func interestShareOfPayment() {
        let loan = Amortization.Loan(principal: 400_000, periodicRate: 0.065 / 12, periods: 360)
        let rows = Amortization.schedule(loan)

        let firstShare = Percent.share(part: rows[0].interest, whole: rows[0].payment)
        let lastShare = Percent.share(part: rows[359].interest, whole: rows[359].payment)
        #expect(firstShare > 80, "the first payment of a 30-year mortgage is \(firstShare)% interest")
        #expect(lastShare < 5)

        var previous = 101.0
        for row in rows {
            let share = Percent.share(part: row.interest, whole: row.payment)
            #expect(share <= previous + 1e-9, "the interest share must never rise")
            previous = share
        }
    }

    /// `npv-to-profitability-index`: the profitability index is NPV expressed as a percentage of the
    /// investment, and its sign must agree with the NPV's.
    @Test func npvToProfitabilityIndex() {
        let flows: [Double] = [-150_000, 56_250, 67_500, 81_000]
        for rate in [0.05, 0.12, 0.25, 0.45] {
            let npv = CashFlow.npv(rate: rate, flows: flows)
            let presentValueOfInflows = npv - flows[0]
            let index = Percent.share(part: presentValueOfInflows, whole: -flows[0]) / 100
            #expect((npv > 0) == (index > 1), "rate \(rate): NPV \(npv), index \(index)")
        }
    }

    /// `yield-curve-points-to-regression`: fitting a line through yields at increasing maturities must
    /// recover the slope of the curve — upward for a normal curve, downward for an inverted one.
    @Test func yieldCurvePointsToRegression() throws {
        let maturities: [Double] = [1, 2, 3, 5, 7, 10, 20, 30]
        let normal = maturities.map { 3.5 + 0.6 * log($0) }
        let inverted = maturities.map { 5.4 - 0.35 * log($0) }

        #expect(try Stat.fit(x: maturities, y: normal).slope > 0)
        #expect(try Stat.fit(x: maturities, y: inverted).slope < 0)

        // A logarithmic fit describes the shape better than a straight line, which is why curves are
        // drawn that way.
        let linear = try Stat.fit(x: maturities, y: normal, model: .linear)
        let logarithmic = try Stat.fit(x: maturities, y: normal, model: .logarithmic)
        #expect(logarithmic.rSquared > linear.rSquared)
        #expect(abs(logarithmic.rSquared - 1) < 1e-12,
                "a log curve fitted logarithmically is exact: R² \(logarithmic.rSquared)")
    }

    /// `price-change-to-percentage-change`: a bond's price move expressed as a percentage must match what
    /// duration predicts, to first order.
    @Test func priceChangeToPercentageChange() {
        let terms = Bond.Terms(couponPct: 4.25, fullPeriods: 20, daysToNextCoupon: 182, daysInPeriod: 182)
        let base = 0.05
        let shift = 0.0010                                   // ten basis points

        let before = Bond.price(terms, yield: base)
        let after = Bond.price(terms, yield: base + shift)
        let actualPct = Percent.change(from: before, to: after)

        // The Terms-based duration: the one that describes THIS security's price curve.
        let duration = Bond.modifiedDuration(terms, yield: base)
        let predictedPct = -duration * shift * 100
        #expect(actualPct < 0, "a higher yield means a lower price")
        #expect(abs(actualPct - predictedPct) <= 0.01,
                "duration predicted \(predictedPct)%, actual \(actualPct)%")
        // Convexity means the actual fall is slightly smaller than the linear prediction.
        #expect(actualPct > predictedPct)
    }

    /// `tax-shield-to-npv`: accelerating depreciation is worth money. The present value of the MACRS tax
    /// shield must exceed straight line's at any positive discount rate, and the two must converge to the
    /// same total undiscounted.
    @Test func taxShieldToNPV() {
        let asset = Depreciation.Asset(cost: 1_000_000, recoveryYears: 7)
        let taxRate = 0.21

        let macrs = Depreciation.macrs(asset).map { $0.depreciation * taxRate }
        let straight = Depreciation.straightLine(asset).map { $0.depreciation * taxRate }

        #expect(abs(macrs.reduce(0, +) - straight.reduce(0, +)) <= 1,
                "the same total shield, differently timed")

        for rate in [0.03, 0.08, 0.15] {
            let macrsPV = CashFlow.npv(rate: rate, flows: [0] + macrs)
            let straightPV = CashFlow.npv(rate: rate, flows: [0] + straight)
            #expect(macrsPV > straightPV,
                    "at \(rate): MACRS \(macrsPV) must beat straight line \(straightPV)")
        }
        // At a zero discount rate the advantage disappears — the invariant's own boundary.
        #expect(abs(CashFlow.npv(rate: 0, flows: [0] + macrs)
                    - CashFlow.npv(rate: 0, flows: [0] + straight)) <= 1)
    }

    /// `percentage-growth-to-compounding`: n years of x% growth is compounding, not multiplication.
    @Test func percentageGrowthToCompounding() throws {
        var value = 100_000.0
        for _ in 0..<5 { value = Percent.applyChange(to: value, percent: 7) }

        let compounded = try TVM.solve(for: .futureValue, .init(
            periods: 5, annualRatePct: 7, presentValue: -100_000,
            paymentsPerYear: 1, compoundsPerYear: 1
        ))
        #expect(abs(value - compounded) <= 1e-6, "\(value) vs \(compounded)")
        #expect(value > 100_000 * 1.35, "five years of 7% beats a naive 35%")
    }

    /// `rate-to-percentage-change`: the other direction — a rate applied over a term must equal the
    /// percentage change it produces, and a *nominal* rate must not be mistaken for one.
    @Test func rateToPercentageChange() {
        let principal = 10_000.0
        let effective = Rate.effectiveAnnualRate(nominalPct: 6, timesPerYear: 12)

        // A year of 6% nominal compounded monthly grows the balance by the effective rate, not by 6%.
        var balance = principal
        for _ in 0..<12 { balance *= (1 + 0.06 / 12) }
        let observed = Percent.change(from: principal, to: balance)
        #expect(abs(observed - effective) <= 1e-9, "observed \(observed)% vs effective \(effective)%")
        #expect(observed > 6, "the nominal rate understates the change: \(observed)% vs 6%")

        // And the APY of that same growth is the same number a third time.
        let apy = Rate.apy(interest: balance - principal, principal: principal, daysInTerm: 365)
        #expect(abs(apy - observed) <= 1e-9)
    }

    /// `percentage-change-to-effective-rate`: a percentage change over a period annualises to an
    /// effective rate, and the two must order the same way.
    @Test func percentageChangeToEffectiveRate() {
        let quarterly = Percent.change(from: 100, to: 103)          // 3% in a quarter
        let effective = Rate.effectiveAnnualRate(nominalPct: quarterly * 4, timesPerYear: 4)
        #expect(effective > quarterly * 4, "compounding adds to the simple annualisation")
        #expect(abs(effective - 100 * (pow(1.03, 4) - 1)) <= 1e-9)
    }

    /// `rent-trend-to-noi`: a fitted rent trend feeding NOI must move net operating income the same way.
    @Test func rentTrendToNOI() throws {
        let years: [Double] = [1, 2, 3, 4, 5]
        let rents: [Double] = [500_000, 515_000, 530_450, 546_363, 562_754]
        let fit = try Stat.fit(x: years, y: rents, model: .exponential)
        #expect(fit.slope > 0, "rents are trending up")

        let projected = Stat.forecastY(x: 6, fit: fit)
        let noiNow = RealEstate.netOperatingIncome(
            grossPotentialRent: rents.last!, vacancyRate: 0.05, operatingExpenses: 197_000
        )
        let noiProjected = RealEstate.netOperatingIncome(
            grossPotentialRent: projected, vacancyRate: 0.05, operatingExpenses: 197_000
        )
        #expect(noiProjected > noiNow, "a rising rent trend must raise NOI")
        // …and NOI is geared: a 3% rent rise moves NOI by more than 3%, because expenses are fixed.
        let rentGrowth = Percent.change(from: rents.last!, to: projected)
        let noiGrowth = Percent.change(from: noiNow, to: noiProjected)
        #expect(noiGrowth > rentGrowth, "operating leverage: \(noiGrowth)% vs \(rentGrowth)%")
    }

    /// `fit-slope-to-percentage-change`: a linear fit's slope, expressed as a share of the mean, must
    /// agree in sign and rough size with the period-on-period percentage change.
    @Test func fitSlopeToPercentageChange() throws {
        let periods: [Double] = [1, 2, 3, 4, 5, 6]
        let values: [Double] = [200, 210, 221, 232, 243, 255]
        let fit = try Stat.fit(x: periods, y: values)
        let meanValue = Stat.summary(values).mean
        let slopeShare = Percent.share(part: fit.slope, whole: meanValue)

        let averageChange = zip(values, values.dropFirst())
            .map { Percent.change(from: $0, to: $1) }
            .reduce(0, +) / Double(values.count - 1)
        #expect(slopeShare > 0 && averageChange > 0)
        let message = "slope as a share of the mean (\(slopeShare)%) should track the average"
            + " change (\(averageChange)%)"
        #expect(abs(slopeShare - averageChange) < 1.0, Comment(rawValue: message))
    }

    /// `cap-rate-to-effective-yield`: a cap rate is an annual simple yield; stated as an effective rate on
    /// monthly income it must be higher, and a property only carries positive leverage above the
    /// mortgage constant.
    @Test func capRateToEffectiveYield() {
        let capRate = 0.0625
        let effective = Rate.effectiveAnnualRate(nominalPct: capRate * 100, timesPerYear: 12)
        #expect(effective > capRate * 100, "monthly income compounds: \(effective)% vs 6.25%")

        let constant = RealEstate.mortgageConstant(annualRatePct: 6.25, amortizationYears: 30)
        #expect(RealEstate.leveragedReturnIsPositive(capRate: 0.09, mortgageConstant: constant))
        #expect(!RealEstate.leveragedReturnIsPositive(capRate: 0.045, mortgageConstant: constant))
    }
}

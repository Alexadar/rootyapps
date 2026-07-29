import Foundation
import TVMKit
import AmortKit
import CashFlowKit
import RateKit
import BondKit
import DepKit
import PercentKit
import StatKit
import RealEstateKit
import DayCountKit

/// Re-derives a tape line's result from its stored inputs.
///
/// This is the single place a stored row becomes a number again. The tape row, the export and the
/// printed sheet all call it, so a line can never read one way on screen and another on paper.
///
/// It stores nothing and caches nothing: given the same inputs it returns the identical `Double`
/// every time, which is what `ParTests` asserts with `==` rather than a tolerance.
public enum TapeSolver {

    /// What one line resolves to. `.none` is a real answer — a solve that legitimately has no result
    /// (no rate balances these flows) — and is rendered as such rather than as a zero.
    public enum Result: Equatable {
        case value(name: String, formatted: String, spoken: String)
        case unavailable(name: String, reason: String)

        public var name: String {
            switch self {
            case .value(let name, _, _), .unavailable(let name, _): return name
            }
        }

        public var formatted: String {
            switch self {
            case .value(_, let formatted, _): return formatted
            case .unavailable: return "—"
            }
        }

        public var spoken: String {
            switch self {
            case .value(_, _, let spoken): return spoken
            case .unavailable(let name, let reason): return "\(name), \(reason)"
            }
        }
    }

    public static func result(for inputs: SolveInputs) -> Result {
        switch inputs {
        case .tvm(let i): return tvm(i)
        case .amortization(let i): return amortization(i)
        case .cashFlow(let i): return cashFlow(i)
        case .bond(let i): return bond(i)
        case .rate(let i): return rate(i)
        case .depreciation(let i): return depreciation(i)
        case .dayCount(let i): return dayCount(i)
        case .percent(let i): return percent(i)
        case .statistics(let i): return statistics(i)
        case .realEstate(let i): return realEstate(i)
        case .damaged:
            return .unavailable(name: "—", reason: "this line can’t be read back")
        }
    }

    // MARK: - One re-solve per tool

    static func tvm(_ i: TVMInputs) -> Result {
        // A stored row is untrusted input: it can come from a hand-edited file or an older build.
        // Every Kit precondition below is a trap, and a trap here would take the app down while
        // merely *drawing* a tape — so each is a guard that yields an unavailable line instead.
        guard i.periods >= 0, i.periods.isFinite,
              i.paymentsPerYear > 0, i.compoundsPerYear > 0 else {
            return .unavailable(name: i.solveFor.uppercased(), reason: "these registers are impossible")
        }
        let registers = TVM.Registers(
            periods: i.periods, annualRatePct: i.annualRatePct, presentValue: i.presentValue,
            payment: i.payment, futureValue: i.futureValue,
            paymentsPerYear: i.paymentsPerYear, compoundsPerYear: i.compoundsPerYear,
            timing: i.timingIsBeginning ? .begin : .end
        )
        guard let variable = TVM.Variable(rawValue: i.solveFor) else {
            return .unavailable(name: i.solveFor.uppercased(), reason: "unknown register")
        }
        let name = symbol(for: variable)
        guard let value = try? TVM.solve(for: variable, registers) else {
            return .unavailable(name: name, reason: "no solution")
        }
        switch variable {
        case .ratePct:
            return .value(name: name, formatted: Fmt.percent(value),
                          spoken: Fmt.spokenPercent(value, label: "annual rate"))
        case .periods:
            return .value(name: name, formatted: Fmt.count(value),
                          spoken: "number of periods, \(Fmt.count(value))")
        default:
            return .value(name: name, formatted: Fmt.money(value),
                          spoken: Fmt.spokenMoney(value, label: name))
        }
    }

    public static func symbol(for variable: TVM.Variable) -> String {
        switch variable {
        case .periods: return "n"
        case .ratePct: return "i%"
        case .presentValue: return "PV"
        case .payment: return "PMT"
        case .futureValue: return "FV"
        }
    }

    static func amortization(_ i: AmortInputs) -> Result {
        guard i.principal > 0, i.principal.isFinite, i.periods > 0, i.periodsPerYear > 0,
              i.balloon >= 0, i.balloon.isFinite,
              i.annualRatePct / 100 / Double(i.periodsPerYear) > -1 else {
            return .unavailable(name: "Payment", reason: "a loan needs a principal and a term")
        }
        let loan = Amortization.Loan(
            principal: i.principal,
            periodicRate: i.annualRatePct / 100 / Double(i.periodsPerYear),
            periods: i.periods,
            rounding: i.roundingDecimals.map { .currency(decimals: $0) } ?? .exact,
            balloon: i.balloon
        )
        if let period = i.balanceAfterPeriod {
            let value = Amortization.balance(loan, after: min(max(period, 0), i.periods))
            return .value(name: "Balance", formatted: Fmt.money(value),
                          spoken: Fmt.spokenMoney(value, label: "balance after \(period) periods"))
        }
        let payment = Amortization.payment(loan)
        return .value(name: "Payment", formatted: Fmt.money(payment),
                      spoken: Fmt.spokenMoney(payment, label: "payment"))
    }

    static func cashFlow(_ i: CashFlowInputs) -> Result {
        let flows = CashFlow.expand(i.groups.map { .init(amount: $0.amount, count: max($0.count, 1)) })
        switch CashFlow.irr(flows: flows) {
        case .unique(let rate):
            let annual = rate * 100
            return .value(name: "IRR", formatted: Fmt.percent(annual),
                          spoken: Fmt.spokenPercent(annual, label: "internal rate of return"))
        case .multiple(let roots):
            // Two rates are the honest answer, and picking one silently is the behaviour Par exists
            // to replace.
            return .unavailable(name: "IRR", reason: "\(roots.count) rates satisfy these flows")
        case .none:
            return .unavailable(name: "IRR", reason: "no rate satisfies these flows")
        }
    }

    static func bond(_ i: BondInputs) -> Result {
        guard i.daysInPeriod > 0, i.daysToNextCoupon >= 0,
              i.fullPeriods >= 0, i.couponPct >= 0, i.couponPct.isFinite, i.price > 0 else {
            return .unavailable(name: "YTM", reason: "these terms are impossible")
        }
        // The first-period case selects which of Appendix B's five formulas prices the line. Reading
        // it back is the difference between reproducing the saved number and a plausible wrong one.
        let terms = Bond.Terms(
            couponPct: i.couponPct, fullPeriods: i.fullPeriods,
            daysToNextCoupon: i.daysToNextCoupon, daysInPeriod: i.daysInPeriod,
            firstPeriod: Bond.FirstPeriod(rawValue: i.firstPeriodRawValue) ?? .regular
        )
        guard let yield = try? Bond.yieldToMaturity(terms, price: i.price) else {
            return .unavailable(name: "YTM", reason: "no yield produces that price")
        }
        let pct = yield * 100
        return .value(name: "YTM", formatted: Fmt.percent(pct),
                      spoken: Fmt.spokenPercent(pct, label: "yield to maturity"))
    }

    static func rate(_ i: RateInputs) -> Result {
        switch i.mode {
        case "apy":
            guard i.principal > 0, i.daysInTerm > 0 else {
                return .unavailable(name: "APY", reason: "a deposit needs a balance and a term")
            }
            let apy = Rate.apy(interest: i.interest, principal: i.principal, daysInTerm: i.daysInTerm)
            return .value(name: "APY", formatted: Fmt.percent(apy),
                          spoken: Fmt.spokenPercent(apy, label: "annual percentage yield"))
        case "convert":
            guard i.timesPerYear > 0,
                  i.nominalPct.isFinite,
                  i.nominalPct / 100 / Double(i.timesPerYear) > -1 else {
                return .unavailable(name: "Effective", reason: "that rate cannot be compounded")
            }
            let effective = Rate.effectiveAnnualRate(nominalPct: i.nominalPct, timesPerYear: i.timesPerYear)
            return .value(name: "Effective", formatted: Fmt.percent(effective),
                          spoken: Fmt.spokenPercent(effective, label: "effective annual rate"))
        default:
            guard i.advance > 0, i.paymentCount >= 1, i.unitPeriodsPerYear > 0 else {
                return .unavailable(name: "APR", reason: "an advance needs payments against it")
            }
            let payments = Rate.series(amount: i.payment, count: i.paymentCount,
                                       firstAtFullPeriods: i.firstPaymentAtPeriod)
            guard let apr = try? Rate.aprActuarial(
                advances: [.init(amount: i.advance, fullPeriods: 0)],
                payments: payments, unitPeriodsPerYear: i.unitPeriodsPerYear
            ) else {
                return .unavailable(name: "APR", reason: "these payments never balance the advance")
            }
            return .value(name: "APR", formatted: Fmt.percent(apr),
                          spoken: Fmt.spokenPercent(apr, label: "annual percentage rate"))
        }
    }

    static func depreciation(_ i: DepInputs) -> Result {
        guard i.cost > 0, i.cost.isFinite, i.recoveryYears >= 1, i.recoveryYears <= 100,
              i.salvage >= 0, i.salvage <= i.cost, i.factor > 0, i.factor.isFinite else {
            return .unavailable(name: "Year 1", reason: "check the cost, salvage and recovery period")
        }
        guard let method = Depreciation.Method(rawValue: i.methodRawValue),
              let convention = Depreciation.Convention(rawValue: i.conventionRawValue) else {
            return .unavailable(name: "Year 1", reason: "unknown method")
        }
        // MACRS ignores salvage by statute, so an asset carrying one cannot be run through it.
        let salvage = method == .macrsGDS ? 0 : i.salvage
        let asset = Depreciation.Asset(cost: i.cost, salvage: salvage,
                                       recoveryYears: i.recoveryYears, factor: i.factor)
        let schedule = Depreciation.schedule(asset, method: method, convention: convention)
        guard let first = schedule.first else {
            return .unavailable(name: "Year 1", reason: "no schedule")
        }
        return .value(name: "Year 1", formatted: Fmt.money(first.depreciation),
                      spoken: Fmt.spokenMoney(first.depreciation, label: "first year deduction"))
    }

    static func dayCount(_ i: DayCountInputs) -> Result {
        guard let start = DayCount.YearMonthDay(encoded: i.start),
              let end = DayCount.YearMonthDay(encoded: i.end),
              let convention = DayCount.Convention(rawValue: i.conventionRawValue) else {
            return .unavailable(name: "Days", reason: "check the dates")
        }
        let termination = i.terminationDate.flatMap { DayCount.YearMonthDay(encoded: $0) }
        let days = DayCount.days(from: start, to: end, convention: convention,
                                 terminationDate: termination)
        return .value(name: "Days", formatted: "\(days)",
                      spoken: "\(days) days, \(convention.displayName)")
    }

    static func percent(_ i: PercentInputs) -> Result {
        switch i.mode {
        case "breakEven":
            guard i.pricePerUnitIsAboveVariableCost,
                  i.fixedCosts >= 0, i.targetProfit >= 0,
                  i.fixedCosts + i.targetProfit >= 0 else {
                return .unavailable(name: "Break-even",
                                    reason: "the price must exceed the variable cost")
            }
            let units = Percent.unitsForTargetProfit(
                fixedCosts: i.fixedCosts, pricePerUnit: i.price,
                variableCostPerUnit: i.variableCostPerUnit, targetProfit: i.targetProfit
            )
            return .value(name: "Break-even", formatted: Fmt.count(units),
                          spoken: "break-even at \(Fmt.count(units)) units")
        case "change":
            // `cost` and `price` carry the from and to values in this mode. `Percent.change` traps
            // on a zero base, so the guard is the Kit's precondition restated.
            guard i.cost != 0 else {
                return .unavailable(name: "Change",
                                    reason: "a percent change needs a non-zero starting value")
            }
            let change = Percent.change(from: i.cost, to: i.price)
            return .value(name: "Change", formatted: Fmt.percent(change, digits: 2),
                          spoken: Fmt.spokenPercent(change, label: "percent change"))
        default:
            guard i.price != 0 else {
                return .unavailable(name: "Margin", reason: "a margin needs a selling price")
            }
            let margin = Percent.marginOnPrice(cost: i.cost, price: i.price)
            return .value(name: "Margin", formatted: Fmt.percent(margin, digits: 2),
                          spoken: Fmt.spokenPercent(margin, label: "gross margin"))
        }
    }

    static func statistics(_ i: StatInputs) -> Result {
        guard let model = Stat.Model(rawValue: i.modelRawValue),
              let fit = try? Stat.fit(x: i.xs, y: i.ys, model: model) else {
            return .unavailable(name: "Forecast", reason: "these points do not support a fit")
        }
        guard !(model.requiresPositive.x && i.forecastX <= 0) else {
            return .unavailable(name: "Forecast",
                                reason: "\(model.displayName.lowercased()) needs a positive x")
        }
        let forecast = Stat.forecastY(x: i.forecastX, fit: fit)
        return .value(name: "Forecast", formatted: Fmt.money(forecast),
                      spoken: Fmt.spokenMoney(forecast, label: "forecast at \(Fmt.count(i.forecastX))"))
    }

    static func realEstate(_ i: RealEstateInputs) -> Result {
        guard i.grossPotentialRent >= 0, i.vacancyPct >= 0, i.vacancyPct < 100,
              i.operatingExpenses >= 0, i.reserves >= 0, i.maxLTVPct > 0,
              i.annualRatePct >= 0, i.value > 0, i.targetDSCR > 0, i.amortizationYears > 0 else {
            return .unavailable(name: "Loan", reason: "check the rent roll and the loan terms")
        }
        let noi = RealEstate.netOperatingIncome(
            grossPotentialRent: i.grossPotentialRent, vacancyRate: i.vacancyPct / 100,
            otherIncome: i.otherIncome, operatingExpenses: i.operatingExpenses, reserves: i.reserves
        )
        guard noi > 0 else {
            return .unavailable(name: "Loan", reason: "this property has no net operating income")
        }
        let sizing = RealEstate.sizeLoan(
            netOperatingIncome: noi, value: i.value, targetDSCR: i.targetDSCR,
            maxLTV: i.maxLTVPct / 100, annualRatePct: i.annualRatePct,
            amortizationYears: i.amortizationYears
        )
        return .value(name: "Max loan", formatted: Fmt.money(sizing.loan, digits: 0),
                      spoken: Fmt.spokenMoney(sizing.loan, label: "maximum loan"))
    }
}

private extension PercentInputs {
    var pricePerUnitIsAboveVariableCost: Bool { price > variableCostPerUnit }
}

public extension DayCount.YearMonthDay {
    /// yyyyMMdd, the form the tape stores dates in.
    init?(encoded: Int) {
        let year = encoded / 10_000, month = (encoded / 100) % 100, day = encoded % 100
        guard month >= 1, month <= 12,
              day >= 1, day <= DayCount.daysInMonth(year: year, month: month) else { return nil }
        self.init(year, month, day)
    }

    var encoded: Int { year * 10_000 + month * 100 + day }
}

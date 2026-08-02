import Foundation

/// A tape line is a solved problem, not a keystroke.
///
/// The document stores INPUTS ONLY. Reopening re-runs the Kit and must reproduce
/// the stored result exactly; the Kits guarantee their half (every input type
/// round-trips losslessly, decoding validates and throws instead of trapping,
/// solves are bit-for-bit deterministic — see `ReplayTests.swift` in each Kit).
/// Our half: never cache a result we cannot regenerate, and never let a decode
/// failure crash — surface it as a damaged line the user can see and fix.
public struct TapeRow: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    /// Free text, empty most of the time and long occasionally. This is what
    /// turns a tape into a client record.
    public var label: String
    public var inputs: SolveInputs
    public let createdAt: Date

    public init(id: UUID = UUID(), label: String = "", inputs: SolveInputs, createdAt: Date = .now) {
        self.id = id
        self.label = label
        self.inputs = inputs
        self.createdAt = createdAt
    }
}

/// The input payload for each Kit surface. One case per tool; never a case that
/// stores a computed number.
public enum SolveInputs: Codable, Equatable, Sendable {
    case tvm(TVMInputs)
    case amortization(AmortInputs)
    case cashFlow(CashFlowInputs)
    case bond(BondInputs)
    case rate(RateInputs)
    case depreciation(DepInputs)
    case dayCount(DayCountInputs)
    case percent(PercentInputs)
    case statistics(StatInputs)
    case realEstate(RealEstateInputs)
    /// A line whose stored inputs failed to decode. It is kept, shown, and made
    /// fixable — never silently dropped and never replaced with a guess.
    case damaged(DamagedLine)

    public var toolName: String {
        switch self {
        case .tvm: return "TVM"
        case .amortization: return "Amort"
        case .cashFlow: return "Cash Flow"
        case .bond: return "Bond"
        case .rate: return "Rate"
        case .depreciation: return "Depreciation"
        case .dayCount: return "Dates"
        case .percent: return "Percent"
        case .statistics: return "Statistics"
        case .realEstate: return "Real Estate"
        case .damaged: return "Damaged"
        }
    }
}

public struct TVMInputs: Codable, Equatable, Sendable {
    public var periods: Double
    public var annualRatePct: Double
    public var presentValue: Double
    public var payment: Double
    public var futureValue: Double
    public var paymentsPerYear: Int
    public var compoundsPerYear: Int
    public var timingIsBeginning: Bool
    /// Which of the five is derived. The other four are the givens.
    public var solveFor: String

    public init(periods: Double, annualRatePct: Double, presentValue: Double, payment: Double,
                futureValue: Double, paymentsPerYear: Int = 12, compoundsPerYear: Int = 12,
                timingIsBeginning: Bool = false, solveFor: String) {
        self.periods = periods
        self.annualRatePct = annualRatePct
        self.presentValue = presentValue
        self.payment = payment
        self.futureValue = futureValue
        self.paymentsPerYear = paymentsPerYear
        self.compoundsPerYear = compoundsPerYear
        self.timingIsBeginning = timingIsBeginning
        self.solveFor = solveFor
    }
}

public struct AmortInputs: Codable, Equatable, Sendable {
    public var principal: Double
    public var annualRatePct: Double
    public var periods: Int
    public var periodsPerYear: Int
    public var balloon: Double
    /// nil = `Amortization.Rounding.exact`; a value = `.currency(decimals:)`. The rounding policy
    /// changes every figure in the schedule, so it is part of the stored input, not a preference.
    public var roundingDecimals: Int?
    /// nil = whole-schedule totals; set = "balance after k".
    public var balanceAfterPeriod: Int?

    public init(principal: Double, annualRatePct: Double, periods: Int, periodsPerYear: Int,
                balloon: Double = 0, roundingDecimals: Int? = 2, balanceAfterPeriod: Int? = nil) {
        self.principal = principal
        self.annualRatePct = annualRatePct
        self.periods = periods
        self.periodsPerYear = periodsPerYear
        self.balloon = balloon
        self.roundingDecimals = roundingDecimals
        self.balanceAfterPeriod = balanceAfterPeriod
    }
}

public struct CashFlowInputs: Codable, Equatable, Sendable {
    public struct Group: Codable, Equatable, Sendable {
        public var amount: Double
        public var count: Int
        public init(amount: Double, count: Int) {
            self.amount = amount
            self.count = count
        }
    }
    public var groups: [Group]
    public var discountRatePct: Double
    public var financeRatePct: Double
    public var reinvestRatePct: Double

    public init(groups: [Group], discountRatePct: Double,
                financeRatePct: Double = 0, reinvestRatePct: Double = 0) {
        self.groups = groups
        self.discountRatePct = discountRatePct
        self.financeRatePct = financeRatePct
        self.reinvestRatePct = reinvestRatePct
    }
}

/// Day counts rather than dates: 31 CFR 356 Appendix B states its formulas in r and s, and BondKit
/// takes them that way so it can stay free of calendar assumptions.
public struct BondInputs: Codable, Equatable, Sendable {
    public var couponPct: Double
    public var price: Double
    public var fullPeriods: Int
    public var daysToNextCoupon: Int
    public var daysInPeriod: Int
    public var conventionRawValue: String
    /// Which of Appendix B's five price formulas applies. Stored because it *selects the formula*:
    /// a line reopened as `.regular` when it was priced as a reopening is a silently wrong number,
    /// and the default exists only so older files keep decoding.
    public var firstPeriodRawValue: String

    public init(couponPct: Double, price: Double, fullPeriods: Int, daysToNextCoupon: Int,
                daysInPeriod: Int, conventionRawValue: String,
                firstPeriodRawValue: String = "regular") {
        self.couponPct = couponPct
        self.price = price
        self.fullPeriods = fullPeriods
        self.daysToNextCoupon = daysToNextCoupon
        self.daysInPeriod = daysInPeriod
        self.conventionRawValue = conventionRawValue
        self.firstPeriodRawValue = firstPeriodRawValue
    }

    private enum CodingKeys: String, CodingKey {
        case couponPct, price, fullPeriods, daysToNextCoupon, daysInPeriod
        case conventionRawValue, firstPeriodRawValue
    }

    /// A file written before the first-period case was stored still opens: it reads as `.regular`,
    /// which is what those lines were priced as.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            couponPct: try c.decode(Double.self, forKey: .couponPct),
            price: try c.decode(Double.self, forKey: .price),
            fullPeriods: try c.decode(Int.self, forKey: .fullPeriods),
            daysToNextCoupon: try c.decode(Int.self, forKey: .daysToNextCoupon),
            daysInPeriod: try c.decode(Int.self, forKey: .daysInPeriod),
            conventionRawValue: try c.decode(String.self, forKey: .conventionRawValue),
            firstPeriodRawValue: try c.decodeIfPresent(String.self, forKey: .firstPeriodRawValue)
                ?? "regular"
        )
    }
}

public struct RateInputs: Codable, Equatable, Sendable {
    /// "apr", "apy" or "convert" — which of RateKit's three questions this line asked.
    public var mode: String
    public var advance: Double
    public var payment: Double
    public var paymentCount: Int
    public var firstPaymentAtPeriod: Int
    public var unitPeriodsPerYear: Double
    public var interest: Double
    public var principal: Double
    public var daysInTerm: Double
    public var nominalPct: Double
    public var timesPerYear: Int

    public init(mode: String, advance: Double = 5_000, payment: Double = 230, paymentCount: Int = 24,
                firstPaymentAtPeriod: Int = 1, unitPeriodsPerYear: Double = 12,
                interest: Double = 61.68, principal: Double = 1_000, daysInTerm: Double = 365,
                nominalPct: Double = 6, timesPerYear: Int = 12) {
        self.mode = mode
        self.advance = advance
        self.payment = payment
        self.paymentCount = paymentCount
        self.firstPaymentAtPeriod = firstPaymentAtPeriod
        self.unitPeriodsPerYear = unitPeriodsPerYear
        self.interest = interest
        self.principal = principal
        self.daysInTerm = daysInTerm
        self.nominalPct = nominalPct
        self.timesPerYear = timesPerYear
    }
}

public struct DepInputs: Codable, Equatable, Sendable {
    public var cost: Double
    public var salvage: Double
    public var recoveryYears: Int
    public var factor: Double
    public var methodRawValue: String
    public var conventionRawValue: String

    public init(cost: Double, salvage: Double, recoveryYears: Int, factor: Double,
                methodRawValue: String, conventionRawValue: String) {
        self.cost = cost
        self.salvage = salvage
        self.recoveryYears = recoveryYears
        self.factor = factor
        self.methodRawValue = methodRawValue
        self.conventionRawValue = conventionRawValue
    }
}

/// Dates are stored as yyyyMMdd integers: a calendar date with no time zone, which is exactly what
/// `DayCount.YearMonthDay` is. A `Date` here would drag a time zone into a settlement date.
public struct DayCountInputs: Codable, Equatable, Sendable {
    public var start: Int
    public var end: Int
    public var conventionRawValue: String
    public var terminationDate: Int?

    public init(start: Int, end: Int, conventionRawValue: String, terminationDate: Int? = nil) {
        self.start = start
        self.end = end
        self.conventionRawValue = conventionRawValue
        self.terminationDate = terminationDate
    }
}

public struct PercentInputs: Codable, Equatable, Sendable {
    /// "margin" (cost/sell/margin) or "breakEven".
    public var mode: String
    public var cost: Double
    public var price: Double
    public var fixedCosts: Double
    public var variableCostPerUnit: Double
    public var targetProfit: Double

    public init(mode: String, cost: Double = 60, price: Double = 100, fixedCosts: Double = 10_000,
                variableCostPerUnit: Double = 15, targetProfit: Double = 0) {
        self.mode = mode
        self.cost = cost
        self.price = price
        self.fixedCosts = fixedCosts
        self.variableCostPerUnit = variableCostPerUnit
        self.targetProfit = targetProfit
    }
}

public struct StatInputs: Codable, Equatable, Sendable {
    public var xs: [Double]
    public var ys: [Double]
    public var modelRawValue: String
    public var forecastX: Double

    public init(xs: [Double], ys: [Double], modelRawValue: String, forecastX: Double) {
        self.xs = xs
        self.ys = ys
        self.modelRawValue = modelRawValue
        self.forecastX = forecastX
    }
}

public struct RealEstateInputs: Codable, Equatable, Sendable {
    public var grossPotentialRent: Double
    public var vacancyPct: Double
    public var otherIncome: Double
    public var operatingExpenses: Double
    public var reserves: Double
    public var value: Double
    public var targetDSCR: Double
    public var maxLTVPct: Double
    public var annualRatePct: Double
    public var amortizationYears: Double

    public init(grossPotentialRent: Double, vacancyPct: Double, otherIncome: Double,
                operatingExpenses: Double, reserves: Double, value: Double, targetDSCR: Double,
                maxLTVPct: Double, annualRatePct: Double, amortizationYears: Double) {
        self.grossPotentialRent = grossPotentialRent
        self.vacancyPct = vacancyPct
        self.otherIncome = otherIncome
        self.operatingExpenses = operatingExpenses
        self.reserves = reserves
        self.value = value
        self.targetDSCR = targetDSCR
        self.maxLTVPct = maxLTVPct
        self.annualRatePct = annualRatePct
        self.amortizationYears = amortizationYears
    }
}

/// What we keep when a line will not decode. Enough to show the user what broke
/// and to let them repair it in place.
public struct DamagedLine: Codable, Equatable, Sendable {
    public var toolName: String
    public var reason: String
    public var rawSummary: String

    public init(toolName: String, reason: String, rawSummary: String) {
        self.toolName = toolName
        self.reason = reason
        self.rawSummary = rawSummary
    }
}

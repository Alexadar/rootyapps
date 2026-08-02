import Foundation

/// Amortization: the schedule a loan actually follows, period by period. Pure, stateless.
///
/// The incumbents hide this behind registers you step through one period at a time. Par computes the
/// whole schedule as data, so the app can show it as a table.
///
/// MODEL CAVEAT (sign convention): balances and payments are stated as **positive magnitudes** here —
/// a $400,000 loan has `principal: 400_000` and a positive `payment`. This differs deliberately from
/// TVMKit's signed cash-flow convention: a schedule is a ledger, not a cash-flow vector.
///
/// MODEL CAVEAT (rounding): real lenders round each payment to the cent, which leaves a residue that
/// the final payment absorbs. `.exact` keeps full precision (the mathematical schedule); `.currency`
/// rounds the payment and every period's interest to the given number of decimals and lets the last
/// payment differ. Both close exactly — that is asserted, not assumed.
public enum Amortization {

    // MARK: - Model

    public enum Timing: String, CaseIterable, Sendable, Codable {
        case end, begin
    }

    /// How money is rounded as the schedule is built.
    public enum Rounding: Equatable, Sendable, Codable {
        /// No rounding: the schedule mathematics, to full `Double` precision.
        case exact
        /// Round the payment and each period's interest to `decimals` places, as a lender would.
        /// The final payment absorbs whatever residue is left so the balance still reaches zero.
        case currency(decimals: Int)

        func round(_ x: Double) -> Double {
            switch self {
            case .exact:
                return x
            case .currency(let decimals):
                let scale = pow(10.0, Double(decimals))
                return (x * scale).rounded() / scale
            }
        }

        /// The largest error a single rounded figure can carry — the tolerance a closure check earns.
        var epsilon: Double {
            switch self {
            case .exact: return 0
            case .currency(let decimals): return 0.5 * pow(10.0, Double(-decimals))
            }
        }
    }

    /// One row of the schedule.
    public struct Period: Equatable, Sendable, Codable {
        /// 1-based period number.
        public let index: Int
        public let payment: Double
        public let interest: Double
        public let principal: Double
        /// Balance remaining *after* this payment.
        public let balance: Double

        public init(index: Int, payment: Double, interest: Double, principal: Double, balance: Double) {
            self.index = index
            self.payment = payment
            self.interest = interest
            self.principal = principal
            self.balance = balance
        }
    }

    /// A loan, as the schedule builder needs it.
    ///
    /// `Codable` because a saved tape stores a loan and rebuilds its schedule on reopening rather than
    /// storing the rows (see `par/plan_tape.md`). Decoding validates and throws — a tape file is
    /// untrusted input, so an impossible loan must surface as an error, not a trap.
    public struct Loan: Equatable, Sendable, Codable {
        public var principal: Double
        /// Interest rate for one **period**, as a decimal (0.005 for 6% nominal paid monthly).
        public var periodicRate: Double
        public var periods: Int
        public var timing: Timing
        public var rounding: Rounding
        /// Balance still owed at the end of the term (a balloon). Zero for a fully amortising loan.
        public var balloon: Double

        public init(
            principal: Double,
            periodicRate: Double,
            periods: Int,
            timing: Timing = .end,
            rounding: Rounding = .exact,
            balloon: Double = 0
        ) {
            precondition(principal > 0, "principal must be > 0")
            precondition(periodicRate > -1, "periodic rate must be > -1")
            precondition(periods > 0, "periods must be > 0")
            precondition(balloon >= 0, "balloon must be >= 0")
            self.principal = principal
            self.periodicRate = periodicRate
            self.periods = periods
            self.timing = timing
            self.rounding = rounding
            self.balloon = balloon
        }

        private enum CodingKeys: String, CodingKey {
            case principal, periodicRate, periods, timing, rounding, balloon
        }

        /// Decoding validates and throws: a persisted loan is untrusted input, and an impossible one
        /// must surface as a `DecodingError` the app can report rather than a precondition trap.
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let principal = try c.decode(Double.self, forKey: .principal)
            let periodicRate = try c.decode(Double.self, forKey: .periodicRate)
            let periods = try c.decode(Int.self, forKey: .periods)
            let balloon = try c.decode(Double.self, forKey: .balloon)
            guard principal > 0, principal.isFinite else {
                throw DecodingError.dataCorruptedError(
                    forKey: .principal, in: c, debugDescription: "principal must be finite and > 0")
            }
            guard periodicRate > -1, periodicRate.isFinite else {
                throw DecodingError.dataCorruptedError(
                    forKey: .periodicRate, in: c, debugDescription: "periodic rate must be > -1")
            }
            guard periods > 0 else {
                throw DecodingError.dataCorruptedError(
                    forKey: .periods, in: c, debugDescription: "periods must be > 0")
            }
            guard balloon >= 0, balloon.isFinite else {
                throw DecodingError.dataCorruptedError(
                    forKey: .balloon, in: c, debugDescription: "balloon must be finite and >= 0")
            }
            self.init(
                principal: principal, periodicRate: periodicRate, periods: periods,
                timing: try c.decode(Timing.self, forKey: .timing),
                rounding: try c.decode(Rounding.self, forKey: .rounding),
                balloon: balloon
            )
        }
    }

    /// Totals over a range of periods — what a tax form or a year-end statement asks for.
    public struct Totals: Equatable, Sendable, Codable {
        public let interest: Double
        public let principal: Double
        public let payments: Double
        /// Balance after the last period in the range.
        public let closingBalance: Double
    }

    // MARK: - Payment

    /// The level payment that retires `principal` (down to `balloon`) over `periods`.
    ///
    /// `PMT = (P − B·vⁿ)·i / (1 − vⁿ)`, with the annuity-due variant divided by `(1+i)`, and the
    /// zero-rate case degenerating to `(P − B)/n`. Written out here rather than borrowed, because a
    /// Kit takes no dependencies; TVMKit solves the same equation from the other side and the tests
    /// check the two agree.
    public static func payment(_ loan: Loan) -> Double {
        let i = loan.periodicRate
        let n = Double(loan.periods)
        let raw: Double
        if i == 0 {
            raw = (loan.principal - loan.balloon) / n
        } else {
            let v = exp(-n * log1p(i))                   // (1+i)⁻ⁿ
            let annuity = -expm1(-n * log1p(i)) / i      // (1 − (1+i)⁻ⁿ)/i
            raw = (loan.principal - loan.balloon * v) / annuity
        }
        let adjusted = loan.timing == .begin ? raw / (1 + i) : raw
        return loan.rounding.round(adjusted)
    }

    // MARK: - Schedule

    /// The full schedule, one row per period.
    ///
    /// Under `.currency` the last row absorbs the rounding residue, so the closing balance is exactly
    /// zero (or exactly the balloon) in every case. Under `.exact` it is zero to floating-point
    /// precision. Both are asserted by the test suite rather than trusted.
    public static func schedule(_ loan: Loan) -> [Period] {
        let i = loan.periodicRate
        let level = payment(loan)
        var balance = loan.principal
        var rows: [Period] = []
        rows.reserveCapacity(loan.periods)

        for index in 1...loan.periods {
            // An annuity-due payment lands at the *start* of the period, so interest for that period
            // accrues on the already-reduced balance: Bₖ = (Bₖ₋₁ − PMT)(1+i). Interest is therefore
            // (balance − payment)·i, not balance·i — and not zero.
            let interestBase = loan.timing == .begin ? balance - level : balance
            let interest = loan.rounding.round(max(interestBase, 0) * i)
            var pay = level
            var principalPart = pay - interest

            if index == loan.periods {
                // Final period: pay off exactly what is left, plus the interest on it.
                principalPart = balance - loan.balloon
                pay = loan.rounding.round(principalPart + interest)
                principalPart = pay - interest
            }

            balance = loan.rounding.round(balance - principalPart)
            rows.append(
                Period(index: index, payment: pay, interest: interest,
                       principal: principalPart, balance: balance)
            )
        }
        return rows
    }

    /// Balance after `period` payments, in closed form — no schedule walked.
    ///
    /// `B_k = P(1+i)^k − PMT·((1+i)^k − 1)/i`, the standard remaining-balance identity. Only exact
    /// for `.exact` rounding; under `.currency` the schedule is authoritative and this is the
    /// mathematical reference the test compares against.
    public static func balance(_ loan: Loan, after period: Int) -> Double {
        precondition(period >= 0 && period <= loan.periods, "period must be within the term")
        let i = loan.periodicRate
        if period == 0 { return loan.principal }
        var level = payment(loan)
        if loan.timing == .begin { level *= (1 + i) }
        let k = Double(period)
        if i == 0 { return loan.principal - level * k }
        let growth = exp(k * log1p(i))                  // (1+i)^k
        return loan.principal * growth - level * (growth - 1) / i
    }

    /// Totals across an inclusive range of 1-based period numbers.
    public static func totals(_ loan: Loan, from first: Int, through last: Int) -> Totals {
        precondition(first >= 1 && last <= loan.periods && first <= last, "range must be within the term")
        let rows = schedule(loan)[(first - 1)...(last - 1)]
        return Totals(
            interest: rows.reduce(0) { $0 + $1.interest },
            principal: rows.reduce(0) { $0 + $1.principal },
            payments: rows.reduce(0) { $0 + $1.payment },
            closingBalance: rows.last?.balance ?? loan.principal
        )
    }

    /// Totals for a calendar-style year of `periodsPerYear` periods, 1-based.
    public static func totals(_ loan: Loan, year: Int, periodsPerYear: Int) -> Totals {
        precondition(year >= 1, "year must be >= 1")
        precondition(periodsPerYear > 0, "periodsPerYear must be > 0")
        let first = (year - 1) * periodsPerYear + 1
        let last = min(year * periodsPerYear, loan.periods)
        return totals(loan, from: first, through: last)
    }

    /// Total interest over the whole term — the number that sells a shorter mortgage.
    public static func totalInterest(_ loan: Loan) -> Double {
        schedule(loan).reduce(0) { $0 + $1.interest }
    }
}

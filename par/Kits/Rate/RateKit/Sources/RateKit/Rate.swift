import Foundation

/// Interest-rate conversions and the two regulated rate disclosures: the annual percentage rate of
/// Regulation Z and the annual percentage yield of Regulation DD. Pure, stateless.
///
/// These are the numbers a lender or a bank is *required* to quote, so they are defined by regulation
/// rather than by taste — and the regulations publish worked examples, which is what pins this Kit.
public enum Rate {

    // MARK: - Nominal, effective, continuous

    /// Effective annual rate from a nominal annual rate compounded `timesPerYear`.
    /// `(1 + r/m)^m − 1`, through `log1p`/`expm1`.
    public static func effectiveAnnualRate(nominalPct: Double, timesPerYear: Int) -> Double {
        precondition(timesPerYear > 0, "timesPerYear must be > 0")
        let r = nominalPct / 100
        precondition(r / Double(timesPerYear) > -1, "rate implies a compounding factor <= 0")
        return 100 * expm1(Double(timesPerYear) * log1p(r / Double(timesPerYear)))
    }

    /// Nominal annual rate that produces `effectivePct` when compounded `timesPerYear`.
    public static func nominalAnnualRate(effectivePct: Double, timesPerYear: Int) -> Double {
        precondition(timesPerYear > 0, "timesPerYear must be > 0")
        let e = effectivePct / 100
        precondition(e > -1, "effective rate must be > -100%")
        return 100 * Double(timesPerYear) * expm1(log1p(e) / Double(timesPerYear))
    }

    /// Effective annual rate under continuous compounding: `e^r − 1`. The limit of the above as
    /// `timesPerYear → ∞`.
    public static func effectiveAnnualRateContinuous(nominalPct: Double) -> Double {
        100 * expm1(nominalPct / 100)
    }

    /// The nominal rate whose continuous compounding gives `effectivePct`: `ln(1 + e)`.
    public static func nominalAnnualRateContinuous(effectivePct: Double) -> Double {
        precondition(effectivePct / 100 > -1, "effective rate must be > -100%")
        return 100 * log1p(effectivePct / 100)
    }

    /// An add-on rate expressed as the simple-interest rate a borrower actually pays.
    ///
    /// MODEL CAVEAT: add-on interest charges `principal × rate × years` up front and then divides the
    /// total by the number of payments; the borrower repays principal along the way but pays interest
    /// on all of it, so the true rate is roughly double. This returns the periodic rate that
    /// amortises the same payment stream, found the same way an APR is.
    public static func addOnToActuarialAPR(
        principal: Double, addOnRatePct: Double, years: Double, paymentsPerYear: Int
    ) throws -> Double {
        precondition(principal > 0, "principal must be > 0")
        precondition(years > 0, "years must be > 0")
        precondition(paymentsPerYear > 0, "paymentsPerYear must be > 0")
        let count = Int((years * Double(paymentsPerYear)).rounded())
        precondition(count >= 1, "the loan must have at least one payment")
        let total = principal * (1 + addOnRatePct / 100 * years)
        let payment = total / Double(count)
        return try aprActuarial(
            advances: [Advance(amount: principal, fullPeriods: 0, fraction: 0)],
            payments: (1...count).map { Payment(amount: payment, fullPeriods: $0, fraction: 0) },
            unitPeriodsPerYear: Double(paymentsPerYear)
        )
    }

    // MARK: - Regulation Z: annual percentage rate

    /// One advance in Appendix J's general equation: `Aₖ`, `qₖ` full unit-periods and a leading
    /// fraction `eₖ` of a unit-period from the start of the term.
    public struct Advance: Equatable, Sendable, Codable {
        public let amount: Double
        public let fullPeriods: Int
        public let fraction: Double

        public init(amount: Double, fullPeriods: Int, fraction: Double = 0) {
            precondition(amount != 0, "an advance of zero is not an advance")
            precondition(fullPeriods >= 0, "fullPeriods must be >= 0")
            precondition(fraction >= 0 && fraction < 1, "fraction must be in [0, 1)")
            self.amount = amount
            self.fullPeriods = fullPeriods
            self.fraction = fraction
        }

        private enum CodingKeys: String, CodingKey { case amount, fullPeriods, fraction }

        /// Decoding validates and throws — a persisted schedule is untrusted input.
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let amount = try c.decode(Double.self, forKey: .amount)
            let fullPeriods = try c.decode(Int.self, forKey: .fullPeriods)
            let fraction = try c.decode(Double.self, forKey: .fraction)
            guard amount.isFinite, amount != 0 else {
                throw DecodingError.dataCorruptedError(
                    forKey: .amount, in: c, debugDescription: "invalid amount")
            }
            guard fullPeriods >= 0 else {
                throw DecodingError.dataCorruptedError(
                    forKey: .fullPeriods, in: c, debugDescription: "fullPeriods must be >= 0")
            }
            guard fraction >= 0, fraction < 1 else {
                throw DecodingError.dataCorruptedError(
                    forKey: .fraction, in: c, debugDescription: "fraction must be in [0, 1)")
            }
            self.init(amount: amount, fullPeriods: fullPeriods, fraction: fraction)
        }
    }

    /// One payment in Appendix J's general equation: `Pⱼ`, `tⱼ` full unit-periods and a leading
    /// fraction `fⱼ`.
    public struct Payment: Equatable, Sendable, Codable {
        public let amount: Double
        public let fullPeriods: Int
        public let fraction: Double

        public init(amount: Double, fullPeriods: Int, fraction: Double = 0) {
            precondition(fullPeriods >= 0, "fullPeriods must be >= 0")
            precondition(fraction >= 0 && fraction < 1, "fraction must be in [0, 1)")
            self.amount = amount
            self.fullPeriods = fullPeriods
            self.fraction = fraction
        }

        private enum CodingKeys: String, CodingKey { case amount, fullPeriods, fraction }

        /// Decoding validates and throws — a persisted schedule is untrusted input.
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let amount = try c.decode(Double.self, forKey: .amount)
            let fullPeriods = try c.decode(Int.self, forKey: .fullPeriods)
            let fraction = try c.decode(Double.self, forKey: .fraction)
            guard amount.isFinite else {
                throw DecodingError.dataCorruptedError(
                    forKey: .amount, in: c, debugDescription: "invalid amount")
            }
            guard fullPeriods >= 0 else {
                throw DecodingError.dataCorruptedError(
                    forKey: .fullPeriods, in: c, debugDescription: "fullPeriods must be >= 0")
            }
            guard fraction >= 0, fraction < 1 else {
                throw DecodingError.dataCorruptedError(
                    forKey: .fraction, in: c, debugDescription: "fraction must be in [0, 1)")
            }
            self.init(amount: amount, fullPeriods: fullPeriods, fraction: fraction)
        }
    }

    public enum RateError: Error, Equatable, CustomStringConvertible {
        case noSignChange
        case didNotConverge
        case emptySchedule

        public var description: String {
            switch self {
            case .noSignChange: return "advances and payments never balance at any rate"
            case .didNotConverge: return "the rate solve did not converge"
            case .emptySchedule: return "there are no advances or no payments"
            }
        }
    }

    /// A run of equal payments one unit-period apart, all sharing the same leading fraction — how
    /// Appendix J describes a payment series.
    public static func series(
        amount: Double, count: Int, firstAtFullPeriods: Int, fraction: Double = 0
    ) -> [Payment] {
        precondition(count >= 1, "a series needs at least one payment")
        return (0..<count).map {
            Payment(amount: amount, fullPeriods: firstAtFullPeriods + $0, fraction: fraction)
        }
    }

    /// Present value of one amount under Appendix J (b)(8): `amount / [(1 + f·i)(1+i)^t]`.
    ///
    /// MODEL CAVEAT: the fractional unit-period earns **simple** interest — `(1 + f·i)` — not
    /// compound `(1+i)^f`. Regulation Z says so, and it is the difference between reproducing
    /// Appendix J's published rates and being wrong in the second decimal on nine of its examples.
    public static func appendixJPresentValue(
        amount: Double, fullPeriods: Int, fraction: Double, periodicRate i: Double
    ) -> Double {
        precondition(i > -1, "periodic rate must be > -1")
        let simple = 1 + fraction * i
        precondition(simple > 0, "fractional-period factor must be positive")
        return amount / (simple * exp(Double(fullPeriods) * log1p(i)))
    }

    /// The annual percentage rate by the actuarial method of Regulation Z, Appendix J.
    ///
    /// Solves `Σ Aₖ/[(1+eₖi)(1+i)^qₖ] = Σ Pⱼ/[(1+fⱼi)(1+i)^tⱼ]` for the unit-period rate `i`, then
    /// returns `100 · w · i` per Appendix J (b)(1).
    ///
    /// - Note: Regulation Z §1026.22(a)(2) allows a disclosed APR to be off by ⅛ of one percentage
    ///   point. That is a *compliance* tolerance for the discloser, not a licence for this Kit: the
    ///   value returned here converges to the full precision of the equation.
    public static func aprActuarial(
        advances: [Advance], payments: [Payment], unitPeriodsPerYear: Double
    ) throws -> Double {
        guard !advances.isEmpty, !payments.isEmpty else { throw RateError.emptySchedule }
        precondition(unitPeriodsPerYear > 0, "unitPeriodsPerYear must be > 0")

        func residual(_ i: Double) -> Double {
            let advanced = advances.reduce(0.0) {
                $0 + appendixJPresentValue(amount: $1.amount, fullPeriods: $1.fullPeriods,
                                           fraction: $1.fraction, periodicRate: i)
            }
            let repaid = payments.reduce(0.0) {
                $0 + appendixJPresentValue(amount: $1.amount, fullPeriods: $1.fullPeriods,
                                           fraction: $1.fraction, periodicRate: i)
            }
            return advanced - repaid
        }

        // A zero rate is a legitimate answer — an interest-free loan repaid exactly on schedule — and
        // it sits at the boundary of the search, so test it before hunting for a bracket. The
        // tolerance is relative to the money involved, not absolute.
        let scale = max(advances.reduce(0) { $0 + abs($1.amount) },
                        payments.reduce(0) { $0 + abs($1.amount) }, 1)
        let atZero = residual(0)
        if abs(atZero) <= 1e-12 * scale { return 0 }

        // Bracket outward from zero in both directions: a schedule that repays less than it advanced
        // has a genuinely negative rate (a rebated 0% promotion), and refusing to look there would
        // report "no solution" for a real loan.
        var lo = 0.0, hi = 0.0
        var fLo = atZero, fHi = atZero
        var step = 1e-6
        var bracketed = false
        while step <= 1e4 {
            hi = step
            fHi = residual(hi)
            if fLo * fHi <= 0 { lo = 0; fLo = atZero; bracketed = true; break }
            let negative = -step
            if negative > -1 {
                let fNegative = residual(negative)
                if atZero * fNegative <= 0 {
                    lo = negative; fLo = fNegative; hi = 0; fHi = atZero; bracketed = true; break
                }
            }
            step *= 2
        }
        guard bracketed else { throw RateError.noSignChange }

        for _ in 0..<200 {
            let mid = 0.5 * (lo + hi)
            let fMid = residual(mid)
            if fMid == 0 { lo = mid; hi = mid; break }
            if fLo * fMid <= 0 { hi = mid; fHi = fMid } else { lo = mid; fLo = fMid }
        }
        let i = 0.5 * (lo + hi)
        guard i.isFinite else { throw RateError.didNotConverge }
        return 100 * unitPeriodsPerYear * i
    }

    /// The United States Rule method, Regulation Z's other permitted APR basis.
    ///
    /// MODEL CAVEAT: under the US Rule, a payment smaller than the interest earned does **not**
    /// capitalise — the shortfall waits, uncompounded, and is settled out of later payments. That is
    /// the entire difference from the actuarial method, and it only shows up when a payment fails to
    /// cover the period's interest.
    ///
    /// Returns the nominal annual rate at which the schedule's final balance is exactly zero.
    public static func aprUnitedStatesRule(
        principal: Double, payments: [Double], unitPeriodsPerYear: Double
    ) throws -> Double {
        precondition(principal > 0, "principal must be > 0")
        guard !payments.isEmpty else { throw RateError.emptySchedule }
        precondition(unitPeriodsPerYear > 0, "unitPeriodsPerYear must be > 0")

        /// Final balance under the US Rule at periodic rate `i`; zero at the answer.
        func finalBalance(_ i: Double) -> Double {
            var balance = principal
            var unpaidInterest = 0.0
            for payment in payments {
                let earned = balance * i + unpaidInterest
                if payment < earned {
                    unpaidInterest = earned - payment      // waits, does not compound
                } else {
                    unpaidInterest = 0
                    balance -= (payment - earned)
                }
            }
            return balance + unpaidInterest
        }

        var lo = 1e-12, hi = 1e-12
        var fLo = finalBalance(lo)
        if abs(fLo) < 1e-12 * principal { return 0 }
        var step = 1e-6
        var bracketed = false
        while step <= 1e4 {
            hi = step
            if fLo * finalBalance(hi) <= 0 { bracketed = true; break }
            step *= 2
        }
        guard bracketed else { throw RateError.noSignChange }
        for _ in 0..<200 {
            let mid = 0.5 * (lo + hi)
            let fMid = finalBalance(mid)
            if fMid == 0 { lo = mid; hi = mid; break }
            if fLo * fMid <= 0 { hi = mid } else { lo = mid; fLo = fMid }
        }
        return 100 * unitPeriodsPerYear * 0.5 * (lo + hi)
    }

    // MARK: - Regulation DD: annual percentage yield

    /// Annual percentage yield, 12 CFR part 1030 Appendix A:
    /// `APY = 100[(1 + interest/principal)^(365/days) − 1]`.
    ///
    /// MODEL CAVEAT: the exponent's numerator is **365 even in a leap year** — Appendix A fixes it, so
    /// this is not a day-count convention question.
    public static func apy(interest: Double, principal: Double, daysInTerm: Double) -> Double {
        precondition(principal > 0, "principal must be > 0")
        precondition(daysInTerm > 0, "daysInTerm must be > 0")
        precondition(interest / principal > -1, "interest cannot destroy more than the principal")
        return 100 * expm1((365.0 / daysInTerm) * log1p(interest / principal))
    }

    /// Annual percentage yield earned, Appendix A part II:
    /// `APY Earned = 100[(1 + interest/balance)^(365/days) − 1]`, on the average daily balance for a
    /// statement period.
    public static func apyEarned(
        interestEarned: Double, averageDailyBalance: Double, daysInPeriod: Double
    ) -> Double {
        precondition(averageDailyBalance > 0, "average daily balance must be > 0")
        precondition(daysInPeriod > 0, "daysInPeriod must be > 0")
        return 100 * expm1((365.0 / daysInPeriod) * log1p(interestEarned / averageDailyBalance))
    }

    /// The interest a balance earns over a term at a given APY — the inverse of `apy`.
    public static func interestFromAPY(
        apyPct: Double, principal: Double, daysInTerm: Double
    ) -> Double {
        precondition(principal > 0, "principal must be > 0")
        precondition(daysInTerm > 0, "daysInTerm must be > 0")
        precondition(apyPct / 100 > -1, "APY must be > -100%")
        return principal * expm1((daysInTerm / 365.0) * log1p(apyPct / 100))
    }
}

import Foundation

/// Bond and bill mathematics, following the formulas the US Treasury publishes for its own securities.
/// Pure, stateless.
///
/// MODEL CAVEAT (the fractional first period earns **simple** interest): every price formula here
/// multiplies the price by `[1 + (r/s)(i/2)]`, not by `(1+i/2)^(r/s)`. That is what 31 CFR part 356
/// Appendix B specifies, and the difference is invisible on a settlement date that falls on a coupon
/// date (where r = s) and worth 0.008 per 100 the moment it does not. Compound discounting of the
/// stub is a different convention, used elsewhere in the market; Par states which one it uses and
/// reproduces Treasury's published examples exactly.
///
/// MODEL CAVEAT (quantities are per 100 of par): prices, coupons and accrued interest are all per 100.
/// Multiply by par/100 for a money amount, as Treasury does in its own examples.
///
/// MODEL CAVEAT (r and s are day counts, not dates): `r` is the days from settlement to the next
/// interest payment and `s` the days in that semiannual period, both on an actual/actual basis. Keeping
/// them as integers is deliberate — it is how Appendix B states the formulas, and it keeps this Kit free
/// of calendar assumptions. Use `DayCountKit` to produce them from dates.
public enum Bond {

    // MARK: - Model

    /// Which of Appendix B section II's five cases a security is in. They are genuinely different
    /// formulas, not variations of presentation, and choosing the wrong one is a silent pricing error.
    public enum FirstPeriod: String, CaseIterable, Sendable, Codable {
        /// §II.A — a regular first interest payment period.
        case regular
        /// §II.B — a short first interest payment period.
        case short
        /// §II.C — a long first interest payment period.
        case long
        /// §II.D — reopened during a regular interest period, or accruing from the coupon frequency
        /// date preceding the issue date, so the purchase price includes predetermined accrued interest.
        case reopenedRegular
        /// §II.E — reopened during the regular portion of a long first payment period.
        case reopenedLongRegularPortion

        /// True for the two cases where the price is quoted net of accrued interest the buyer pays.
        public var includesAccruedInterest: Bool {
            self == .reopenedRegular || self == .reopenedLongRegularPortion
        }
    }

    /// Everything Appendix B's section II formulas take. Field names follow the regulation's own
    /// symbols, because that is what makes an implementation auditable against it.
    ///
    /// `Codable` for tape replay (`par/plan_tape.md`); decoding validates and throws.
    public struct Terms: Equatable, Sendable, Codable {
        /// `C` — the regular annual interest per 100 of par, e.g. 8.75 for an 8¾% security.
        public var couponPct: Double
        /// `n` — full semiannual periods from the issue (or settlement) date to maturity. Appendix B:
        /// when the issue date is a coupon frequency date, n is one **less** than the number of full
        /// semiannual periods remaining.
        public var fullPeriods: Int
        /// `r` — days from settlement to the next interest payment.
        public var daysToNextCoupon: Int
        /// `s` — days in the semiannual period ending on that payment.
        public var daysInPeriod: Int
        public var firstPeriod: FirstPeriod
        /// `r′` — days in the fractional ("initial short") portion of a long first payment period.
        /// Only used by `.reopenedLongRegularPortion`.
        public var fractionalPortionDays: Int
        /// `s″` — days in the semiannual period ending at the start of the regular portion of a long
        /// first payment period. Only used by `.reopenedLongRegularPortion`.
        public var fractionalPortionPeriodDays: Int

        public init(
            couponPct: Double,
            fullPeriods: Int,
            daysToNextCoupon: Int,
            daysInPeriod: Int,
            firstPeriod: FirstPeriod = .regular,
            fractionalPortionDays: Int = 0,
            fractionalPortionPeriodDays: Int = 1
        ) {
            precondition(couponPct >= 0, "coupon must be >= 0")
            precondition(fullPeriods >= 0, "n must be >= 0")
            precondition(daysInPeriod > 0, "s must be > 0")
            precondition(daysToNextCoupon >= 0, "r must be >= 0")
            precondition(fractionalPortionDays >= 0, "r′ must be >= 0")
            precondition(fractionalPortionPeriodDays > 0, "s″ must be > 0")
            self.couponPct = couponPct
            self.fullPeriods = fullPeriods
            self.daysToNextCoupon = daysToNextCoupon
            self.daysInPeriod = daysInPeriod
            self.firstPeriod = firstPeriod
            self.fractionalPortionDays = fractionalPortionDays
            self.fractionalPortionPeriodDays = fractionalPortionPeriodDays
        }

        private enum CodingKeys: String, CodingKey {
            case couponPct, fullPeriods, daysToNextCoupon, daysInPeriod, firstPeriod
            case fractionalPortionDays, fractionalPortionPeriodDays
        }

        /// Decoding validates and throws — persisted terms are untrusted input.
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let couponPct = try c.decode(Double.self, forKey: .couponPct)
            let fullPeriods = try c.decode(Int.self, forKey: .fullPeriods)
            let daysToNextCoupon = try c.decode(Int.self, forKey: .daysToNextCoupon)
            let daysInPeriod = try c.decode(Int.self, forKey: .daysInPeriod)
            let fractionalPortionDays = try c.decode(Int.self, forKey: .fractionalPortionDays)
            let fractionalPortionPeriodDays = try c.decode(
                Int.self, forKey: .fractionalPortionPeriodDays
            )
            guard couponPct >= 0, couponPct.isFinite else {
                throw DecodingError.dataCorruptedError(
                    forKey: .couponPct, in: c, debugDescription: "coupon must be finite and >= 0")
            }
            guard fullPeriods >= 0 else {
                throw DecodingError.dataCorruptedError(
                    forKey: .fullPeriods, in: c, debugDescription: "n must be >= 0")
            }
            guard daysInPeriod > 0 else {
                throw DecodingError.dataCorruptedError(
                    forKey: .daysInPeriod, in: c, debugDescription: "s must be > 0")
            }
            guard daysToNextCoupon >= 0 else {
                throw DecodingError.dataCorruptedError(
                    forKey: .daysToNextCoupon, in: c, debugDescription: "r must be >= 0")
            }
            guard fractionalPortionDays >= 0 else {
                throw DecodingError.dataCorruptedError(
                    forKey: .fractionalPortionDays, in: c, debugDescription: "r′ must be >= 0")
            }
            guard fractionalPortionPeriodDays > 0 else {
                throw DecodingError.dataCorruptedError(
                    forKey: .fractionalPortionPeriodDays, in: c, debugDescription: "s″ must be > 0")
            }
            self.init(
                couponPct: couponPct, fullPeriods: fullPeriods,
                daysToNextCoupon: daysToNextCoupon, daysInPeriod: daysInPeriod,
                firstPeriod: try c.decode(FirstPeriod.self, forKey: .firstPeriod),
                fractionalPortionDays: fractionalPortionDays,
                fractionalPortionPeriodDays: fractionalPortionPeriodDays
            )
        }
    }

    /// A price quote and the accrued interest that goes with it, per 100 of par.
    public struct Quote: Equatable, Sendable, Codable {
        /// The price Treasury calls `P` — net of accrued interest.
        public let price: Double
        /// `A` — accrued interest the buyer pays on top.
        public let accruedInterest: Double
        /// What the buyer actually pays: `P + A`.
        public var settlementAmount: Double { price + accruedInterest }
    }

    // MARK: - Factors (Appendix B section II definitions)

    /// `vⁿ = 1/(1 + i/2)ⁿ` — the present value of 1 due in n semiannual periods.
    public static func discountFactor(yield i: Double, periods n: Int) -> Double {
        precondition(i > -2, "a semiannual yield of i/2 <= -1 has no meaning")
        if i == 0 { return 1 }
        return exp(-Double(n) * log1p(i / 2))
    }

    /// `aₙ = (1 − vⁿ)/(i/2)` — the present value of 1 per period for n periods.
    ///
    /// Appendix B spells out the degenerate case in words: "If i = 0, then aₙ = n. Furthermore, when
    /// i = 0, aₙ cannot be calculated using the formula (1 − vⁿ)/(i/2)." Honouring that is why a
    /// zero-yield price is a number here rather than a NaN.
    public static func annuityFactor(yield i: Double, periods n: Int) -> Double {
        precondition(i > -2, "a semiannual yield of i/2 <= -1 has no meaning")
        if i == 0 { return Double(n) }
        return -expm1(-Double(n) * log1p(i / 2)) / (i / 2)
    }

    // MARK: - Accrued interest (section I)

    /// `A = [(s − r)/s](C/2)` — accrued interest per 100, section I.
    public static func accruedInterest(_ terms: Terms) -> Double {
        let s = Double(terms.daysInPeriod), r = Double(terms.daysToNextCoupon)
        return ((s - r) / s) * (terms.couponPct / 2)
    }

    /// Accrued interest per 100 for a reopening whose accrual spans the fractional and regular portions
    /// of a long first payment period: `A = AI′ + AI` with `AI′ = (r′/s″)(C/2)` — section II.E.
    public static func accruedInterestAcrossLongFirstPeriod(_ terms: Terms) -> Double {
        let aiPrime = (Double(terms.fractionalPortionDays)
            / Double(terms.fractionalPortionPeriodDays)) * (terms.couponPct / 2)
        return aiPrime + accruedInterest(terms)
    }

    /// Accrued interest in **money** for a holding that spans two half-years of different length, the
    /// way section I.D(2) computes it: a daily accrual per par amount, rounded to nine decimals, then
    /// multiplied by the days in each half-year.
    ///
    /// MODEL CAVEAT: the nine-decimal rounding of the daily figure is Treasury's, not ours. Without it
    /// the exact product differs in the eighth decimal from the published example — small, but the
    /// difference between reproducing a cited number and approximating it.
    public static func accruedInterestAcrossTwoHalfYears(
        couponPct: Double,
        par: Double,
        firstHalfYearDays: Int, firstHalfYearLength: Int,
        secondHalfYearDays: Int, secondHalfYearLength: Int,
        roundDailyAccrualToNineDecimals: Bool = true
    ) -> Double {
        precondition(par > 0, "par must be > 0")
        precondition(firstHalfYearLength > 0 && secondHalfYearLength > 0, "half-years must be non-empty")
        let semiannualCoupon = par * (couponPct / 100) / 2
        var daily1 = semiannualCoupon / Double(firstHalfYearLength)
        var daily2 = semiannualCoupon / Double(secondHalfYearLength)
        if roundDailyAccrualToNineDecimals {
            daily1 = (daily1 * 1e9).rounded() / 1e9
            daily2 = (daily2 * 1e9).rounded() / 1e9
        }
        return daily1 * Double(firstHalfYearDays) + daily2 * Double(secondHalfYearDays)
    }

    // MARK: - Price from yield (section II)

    /// Price per 100 from a nominal annual yield, for whichever of Appendix B's five cases applies.
    ///
    /// - §II.A / §II.B: `P[1 + (r/s)(i/2)] = (C/2)(r/s) + (C/2)aₙ + 100vⁿ`
    /// - §II.C: `P[1 + (r/s)(i/2)] = [(C/2)(r/s)]v + (C/2)aₙ + 100vⁿ`
    /// - §II.D: `(P + A)[1 + (r/s)(i/2)] = C/2 + (C/2)aₙ + 100vⁿ`
    /// - §II.E: `(P + A)[1 + (r/s)(i/2)] = (r′/s″)(C/2) + C/2 + (C/2)aₙ + 100vⁿ`
    public static func quote(_ terms: Terms, yield i: Double) -> Quote {
        let c2 = terms.couponPct / 2
        let ratio = Double(terms.daysToNextCoupon) / Double(terms.daysInPeriod)
        let vn = discountFactor(yield: i, periods: terms.fullPeriods)
        let an = annuityFactor(yield: i, periods: terms.fullPeriods)
        let stub = 1 + ratio * (i / 2)                       // the simple-interest factor
        let deferred = c2 * an + 100 * vn

        switch terms.firstPeriod {
        case .regular, .short:
            return Quote(price: (c2 * ratio + deferred) / stub, accruedInterest: 0)

        case .long:
            let v = discountFactor(yield: i, periods: 1)
            return Quote(price: ((c2 * ratio) * v + deferred) / stub, accruedInterest: 0)

        case .reopenedRegular:
            let a = accruedInterest(terms)
            return Quote(price: (c2 + deferred) / stub - a, accruedInterest: a)

        case .reopenedLongRegularPortion:
            let aiPrime = (Double(terms.fractionalPortionDays)
                / Double(terms.fractionalPortionPeriodDays)) * c2
            let a = aiPrime + accruedInterest(terms)
            return Quote(price: (aiPrime + c2 + deferred) / stub - a, accruedInterest: a)
        }
    }

    /// Just the price, per 100.
    public static func price(_ terms: Terms, yield i: Double) -> Double {
        quote(terms, yield: i).price
    }

    // MARK: - Yield from price

    public enum YieldError: Error, Equatable, CustomStringConvertible {
        /// No yield in the searched range produces this price.
        case priceOutOfRange
        public var description: String { "no yield in the searched range produces that price" }
    }

    /// The nominal annual yield to maturity implied by a price, inverting `price(_:yield:)`.
    ///
    /// Price is strictly decreasing in yield over any sane range, so bracketing then bisecting is both
    /// sufficient and unfoolable; the measured round-trip error is below 1e-9 (par/scratch/treasury_356.py).
    public static func yieldToMaturity(
        _ terms: Terms, price target: Double, lowerBound: Double = -0.99, upperBound: Double = 2.0
    ) throws -> Double {
        precondition(upperBound > lowerBound, "invalid search range")
        var lo = lowerBound, hi = upperBound
        let atLo = price(terms, yield: lo) - target
        let atHi = price(terms, yield: hi) - target
        guard atLo * atHi <= 0 else { throw YieldError.priceOutOfRange }

        var fLo = atLo
        for _ in 0..<200 {
            let mid = 0.5 * (lo + hi)
            let fMid = price(terms, yield: mid) - target
            if fMid == 0 { return mid }
            if fLo * fMid <= 0 { hi = mid } else { lo = mid; fLo = fMid }
        }
        return 0.5 * (lo + hi)
    }

    /// Current yield: annual coupon over price. A quote, not a return.
    public static func currentYield(couponPct: Double, price: Double) -> Double {
        precondition(price > 0, "price must be > 0")
        return couponPct / price
    }

    // MARK: - Duration and convexity

    /// Macaulay duration in **years**, the coupon-weighted average time to the cash flows.
    ///
    /// MODEL CAVEAT: this is a definition, not a market convention, so it has no published Treasury
    /// example behind it. It is asserted against its own definition and against a numerical derivative
    /// of the price function — which is the honest check, since modified duration *is* that derivative.
    /// Computed on the regular-period model (settlement on a coupon date is the reference case).
    public static func macaulayDuration(couponPct: Double, periods n: Int, yield i: Double) -> Double {
        precondition(n >= 1, "duration needs at least one period")
        let c2 = couponPct / 2
        var weighted = 0.0
        var value = 0.0
        for k in 1...n {
            let flow = k == n ? c2 + 100 : c2
            let pv = flow * discountFactor(yield: i, periods: k)
            weighted += Double(k) * pv
            value += pv
        }
        precondition(value > 0, "price must be positive")
        return (weighted / value) / 2      // periods → years
    }

    /// Modified duration in years: Macaulay duration divided by `(1 + i/2)`.
    public static func modifiedDuration(couponPct: Double, periods n: Int, yield i: Double) -> Double {
        macaulayDuration(couponPct: couponPct, periods: n, yield: i) / (1 + i / 2)
    }

    /// Macaulay duration for a security described by `Terms`.
    ///
    /// **Use this, not the `periods:` form, when you already have `Terms`.** Appendix B's `n` is one less
    /// than the number of coupons remaining when the issue date is a coupon frequency date, so a security
    /// with `fullPeriods: 59` pays **60** more coupons. Passing that 59 to the `periods:` form below
    /// measures a different bond and lands half a year short — which is invisible until you compare the
    /// duration against the price curve it is supposed to describe.
    ///
    /// MODEL CAVEAT: computed on the coupon-date model (`fullPeriods + 1` coupons, redemption with the
    /// last). Exact for `.regular` terms, where settlement is a coupon date; for a stub period it is the
    /// duration of the equivalent whole-period security, since duration is a sensitivity measure rather
    /// than a settlement calculation.
    public static func macaulayDuration(_ terms: Terms, yield i: Double) -> Double {
        macaulayDuration(couponPct: terms.couponPct, periods: terms.fullPeriods + 1, yield: i)
    }

    /// Modified duration for a security described by `Terms`. See `macaulayDuration(_:yield:)`.
    public static func modifiedDuration(_ terms: Terms, yield i: Double) -> Double {
        modifiedDuration(couponPct: terms.couponPct, periods: terms.fullPeriods + 1, yield: i)
    }

    /// Convexity for a security described by `Terms`. See `macaulayDuration(_:yield:)`.
    public static func convexity(_ terms: Terms, yield i: Double) -> Double {
        convexity(couponPct: terms.couponPct, periods: terms.fullPeriods + 1, yield: i)
    }

    /// Convexity in years², the second-order sensitivity of price to yield.
    public static func convexity(couponPct: Double, periods n: Int, yield i: Double) -> Double {
        precondition(n >= 1, "convexity needs at least one period")
        let c2 = couponPct / 2
        var weighted = 0.0
        var value = 0.0
        for k in 1...n {
            let flow = k == n ? c2 + 100 : c2
            let pv = flow * discountFactor(yield: i, periods: k)
            weighted += Double(k) * Double(k + 1) * pv
            value += pv
        }
        precondition(value > 0, "price must be positive")
        return (weighted / value) / pow(1 + i / 2, 2) / 4     // periods² → years²
    }

    // MARK: - Treasury bills (section VI)

    /// §VI.A — price per 100 from a discount rate: `P = 100[1 − d·r/360]`.
    public static func billPrice(discountRate d: Double, daysToMaturity r: Int) -> Double {
        precondition(r > 0, "days to maturity must be > 0")
        return 100 * (1 - d * Double(r) / 360)
    }

    /// The inverse: the discount rate implied by a bill price.
    public static func billDiscountRate(price: Double, daysToMaturity r: Int) -> Double {
        precondition(r > 0, "days to maturity must be > 0")
        precondition(price > 0, "price must be > 0")
        return (1 - price / 100) * 360 / Double(r)
    }

    /// §VI.D — the investment rate (coupon-equivalent yield) of a bill.
    ///
    /// Two branches, and the boundary is real: at or inside half a year the rate is simple
    /// (`i = [(100−P)/P](y/r)`); beyond it the security compounds once, so `P[1 + (r − y/2)(i/y)](1 + i/2)
    /// = 100`, solved as a quadratic with `a = r/2y − 0.25`, `b = r/y`, `c = (P − 100)/P`.
    ///
    /// - Parameter daysInYear: `y` — 365, or 366 when the year following the issue date contains
    ///   February 29. Appendix B defines it that way explicitly, so it is a parameter, not a constant.
    public static func billInvestmentRate(
        price: Double, daysToMaturity r: Int, daysInYear y: Int = 365
    ) -> Double {
        precondition(price > 0, "price must be > 0")
        precondition(r > 0, "days to maturity must be > 0")
        precondition(y == 365 || y == 366, "Appendix B defines y as 365 or 366")

        let rd = Double(r), yd = Double(y)
        if rd <= yd / 2 {
            return ((100 - price) / price) * (yd / rd)
        }
        let a = rd / (2 * yd) - 0.25
        let b = rd / yd
        let c = (price - 100) / price
        let discriminant = b * b - 4 * a * c
        precondition(discriminant >= 0, "no real investment rate for that price")
        return (-b + sqrt(discriminant)) / (2 * a)
    }

    // MARK: - Inflation-indexed securities (section III)

    /// §III — the index ratio, **truncated** to six decimals in the regulation's general definition and
    /// shown to five in its worked example.
    ///
    /// MODEL CAVEAT: truncated, not rounded, and that is deliberate in the source. `decimals` defaults
    /// to 5 to match the published example.
    public static func indexRatio(
        referenceCPI: Double, referenceCPIAtIssue: Double, decimals: Int = 5
    ) -> Double {
        precondition(referenceCPIAtIssue > 0, "reference CPI at issue must be > 0")
        precondition(decimals >= 0 && decimals <= 12, "decimals out of range")
        let scale = pow(10.0, Double(decimals))
        return (referenceCPI / referenceCPIAtIssue * scale).rounded(.down) / scale
    }

    /// Inflation-adjusted principal: par × index ratio.
    public static func adjustedPrincipal(par: Double, indexRatio: Double) -> Double {
        precondition(par > 0, "par must be > 0")
        precondition(indexRatio > 0, "index ratio must be > 0")
        return par * indexRatio
    }
}

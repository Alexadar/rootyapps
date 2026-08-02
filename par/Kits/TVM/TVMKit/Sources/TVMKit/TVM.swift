import Foundation

/// Time value of money: the five-register model every finance professional already carries in their
/// head — n, i%, PV, PMT, FV — solved for whichever one you leave out. Pure, stateless.
///
/// MODEL CAVEAT (sign convention): money **out** is negative and money **in** is positive, from the
/// point of view of the person holding the calculator. A $400,000 mortgage is `presentValue: 400_000`
/// with a negative `payment`. The cash-flow equation Par solves is therefore homogeneous:
///
///     PV + PMT · ä(n, i) + FV · (1+i)⁻ⁿ = 0
///
/// with `ä = (1 − (1+i)⁻ⁿ)/i` for payments at period end, multiplied by `(1+i)` for payments at
/// period start, and `ä = n` when i = 0.
///
/// MODEL CAVEAT (rate conversion): when `paymentsPerYear != compoundsPerYear` the periodic rate is
/// `(1 + r/(100·c))^(c/p) − 1`, i.e. the compounding is converted to the payment frequency. This is
/// the case a Canadian mortgage lives in (monthly payments, semiannual compounding) and the single
/// most common implementation error in the domain.
public enum TVM {

    // MARK: - Model

    /// Which register to solve for.
    public enum Variable: String, CaseIterable, Sendable, Codable {
        case periods, ratePct, presentValue, payment, futureValue
    }

    /// Payments at the end of each period (ordinary annuity) or the start (annuity due).
    public enum Timing: String, CaseIterable, Sendable, Codable {
        case end, begin
    }

    /// Why a solve could not produce a finite answer. These are genuine domain failures, not UI
    /// validation: the Kit refuses to guess.
    public enum SolveError: Error, Equatable, CustomStringConvertible {
        /// The cash flows never change sign, so no rate or term can balance them.
        case noSignChange
        /// Solving for `n` requires a positive log argument; these registers give none.
        case termHasNoSolution
        /// Solving for PMT with i = 0 and n = 0, or similar degenerate input.
        case degenerate(String)
        /// The rate solve bracketed a root but could not converge to the requested tolerance.
        case didNotConverge

        public var description: String {
            switch self {
            case .noSignChange:
                return "cash flows never change sign — no rate balances them"
            case .termHasNoSolution:
                return "no positive number of periods satisfies these registers"
            case .degenerate(let why):
                return "degenerate input: \(why)"
            case .didNotConverge:
                return "rate solve did not converge"
            }
        }
    }

    /// The five registers plus the three settings that give them meaning.
    ///
    /// `Codable` because a saved tape stores the registers of every solved problem and re-solves them
    /// on reopening rather than storing the answer (see `par/plan_tape.md`). Doubles encode through
    /// `JSONEncoder` losslessly, so a replayed solve is bit-for-bit identical — which is a test, not a
    /// hope. Decoding validates and throws rather than trapping: a tape file is untrusted input.
    public struct Registers: Equatable, Sendable, Codable {
        public var periods: Double
        public var annualRatePct: Double
        public var presentValue: Double
        public var payment: Double
        public var futureValue: Double
        public var paymentsPerYear: Int
        public var compoundsPerYear: Int
        public var timing: Timing

        /// - Precondition: both frequencies must be positive; periods must be non-negative.
        public init(
            periods: Double = 0,
            annualRatePct: Double = 0,
            presentValue: Double = 0,
            payment: Double = 0,
            futureValue: Double = 0,
            paymentsPerYear: Int = 12,
            compoundsPerYear: Int = 12,
            timing: Timing = .end
        ) {
            precondition(paymentsPerYear > 0, "paymentsPerYear must be > 0")
            precondition(compoundsPerYear > 0, "compoundsPerYear must be > 0")
            precondition(periods >= 0, "periods must be >= 0")
            self.periods = periods
            self.annualRatePct = annualRatePct
            self.presentValue = presentValue
            self.payment = payment
            self.futureValue = futureValue
            self.paymentsPerYear = paymentsPerYear
            self.compoundsPerYear = compoundsPerYear
            self.timing = timing
        }

        private enum CodingKeys: String, CodingKey {
            case periods, annualRatePct, presentValue, payment, futureValue
            case paymentsPerYear, compoundsPerYear, timing
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let periods = try c.decode(Double.self, forKey: .periods)
            let paymentsPerYear = try c.decode(Int.self, forKey: .paymentsPerYear)
            let compoundsPerYear = try c.decode(Int.self, forKey: .compoundsPerYear)
            guard periods >= 0, periods.isFinite else {
                throw DecodingError.dataCorruptedError(
                    forKey: .periods, in: c, debugDescription: "periods must be finite and >= 0"
                )
            }
            guard paymentsPerYear > 0 else {
                throw DecodingError.dataCorruptedError(
                    forKey: .paymentsPerYear, in: c, debugDescription: "must be > 0"
                )
            }
            guard compoundsPerYear > 0 else {
                throw DecodingError.dataCorruptedError(
                    forKey: .compoundsPerYear, in: c, debugDescription: "must be > 0"
                )
            }
            self.init(
                periods: periods,
                annualRatePct: try c.decode(Double.self, forKey: .annualRatePct),
                presentValue: try c.decode(Double.self, forKey: .presentValue),
                payment: try c.decode(Double.self, forKey: .payment),
                futureValue: try c.decode(Double.self, forKey: .futureValue),
                paymentsPerYear: paymentsPerYear,
                compoundsPerYear: compoundsPerYear,
                timing: try c.decode(Timing.self, forKey: .timing)
            )
        }

        /// Replace one register, keeping everything else — how a solve result is applied.
        public func setting(_ variable: Variable, to value: Double) -> Registers {
            var copy = self
            switch variable {
            case .periods: copy.periods = value
            case .ratePct: copy.annualRatePct = value
            case .presentValue: copy.presentValue = value
            case .payment: copy.payment = value
            case .futureValue: copy.futureValue = value
            }
            return copy
        }

        public func value(of variable: Variable) -> Double {
            switch variable {
            case .periods: return periods
            case .ratePct: return annualRatePct
            case .presentValue: return presentValue
            case .payment: return payment
            case .futureValue: return futureValue
            }
        }
    }

    // MARK: - Rate conversion

    /// The rate for one payment period, from the annual nominal rate and the two frequencies.
    ///
    /// `(1 + r/(100·c))^(c/p) − 1`, computed through `log1p`/`expm1` so that tiny rates keep their
    /// significant digits instead of being lost to `1 + ε`.
    public static func periodicRate(
        annualRatePct: Double, paymentsPerYear: Int, compoundsPerYear: Int
    ) -> Double {
        precondition(paymentsPerYear > 0 && compoundsPerYear > 0, "frequencies must be > 0")
        let nominal = annualRatePct / 100.0
        if nominal == 0 { return 0 }
        let perCompound = nominal / Double(compoundsPerYear)
        precondition(perCompound > -1, "rate implies a compounding factor <= 0")
        let exponent = Double(compoundsPerYear) / Double(paymentsPerYear)
        return expm1(exponent * log1p(perCompound))
    }

    /// The inverse of `periodicRate`: back to an annual nominal percentage.
    public static func annualRatePct(
        periodicRate i: Double, paymentsPerYear: Int, compoundsPerYear: Int
    ) -> Double {
        precondition(paymentsPerYear > 0 && compoundsPerYear > 0, "frequencies must be > 0")
        if i == 0 { return 0 }
        precondition(i > -1, "periodic rate must be > -1")
        let exponent = Double(paymentsPerYear) / Double(compoundsPerYear)
        return 100.0 * Double(compoundsPerYear) * expm1(exponent * log1p(i))
    }

    /// The periodic rate implied by a `Registers` value.
    public static func periodicRate(_ r: Registers) -> Double {
        periodicRate(
            annualRatePct: r.annualRatePct,
            paymentsPerYear: r.paymentsPerYear,
            compoundsPerYear: r.compoundsPerYear
        )
    }

    // MARK: - Factors

    /// `(1+i)⁻ⁿ` — the present value of 1 due in n periods.
    public static func discountFactor(periodicRate i: Double, periods n: Double) -> Double {
        precondition(i > -1, "periodic rate must be > -1")
        if i == 0 { return 1 }
        return exp(-n * log1p(i))
    }

    /// The annuity factor: present value of 1 per period for n periods, at the given timing.
    ///
    /// `(1 − (1+i)⁻ⁿ)/i`, times `(1+i)` for `.begin`. Degenerates to `n` at i = 0 — the same special
    /// case 31 CFR 356 App B spells out for its own `aₙ` ("if i = 0, then aₙ = n").
    public static func annuityFactor(
        periodicRate i: Double, periods n: Double, timing: Timing = .end
    ) -> Double {
        precondition(i > -1, "periodic rate must be > -1")
        let base: Double
        if i == 0 {
            base = n
        } else {
            base = -expm1(-n * log1p(i)) / i     // (1 − (1+i)⁻ⁿ)/i, stable for tiny i
        }
        return timing == .begin ? base * (1 + i) : base
    }

    // MARK: - The balance equation

    /// `PV + PMT·ä + FV·(1+i)⁻ⁿ`, which is zero for a consistent set of registers.
    /// Exposed because it is the honest way to check a solve, and the residual tests use it.
    public static func residual(_ r: Registers) -> Double {
        let i = periodicRate(r)
        return r.presentValue
            + r.payment * annuityFactor(periodicRate: i, periods: r.periods, timing: r.timing)
            + r.futureValue * discountFactor(periodicRate: i, periods: r.periods)
    }

    // MARK: - Solve

    /// Solve for one register from the other four.
    ///
    /// - Throws: `SolveError` when no finite solution exists. Nothing is clamped and nothing is
    ///   guessed — a caller that wants a fallback must choose it themselves.
    public static func solve(for variable: Variable, _ r: Registers) throws -> Double {
        let i = periodicRate(r)
        switch variable {
        case .presentValue:
            let a = annuityFactor(periodicRate: i, periods: r.periods, timing: r.timing)
            let v = discountFactor(periodicRate: i, periods: r.periods)
            return -(r.payment * a + r.futureValue * v)

        case .futureValue:
            let a = annuityFactor(periodicRate: i, periods: r.periods, timing: r.timing)
            let v = discountFactor(periodicRate: i, periods: r.periods)
            guard v != 0 else { throw SolveError.degenerate("discount factor is zero") }
            return -(r.presentValue + r.payment * a) / v

        case .payment:
            let a = annuityFactor(periodicRate: i, periods: r.periods, timing: r.timing)
            guard a != 0 else { throw SolveError.degenerate("annuity factor is zero (n = 0?)") }
            let v = discountFactor(periodicRate: i, periods: r.periods)
            return -(r.presentValue + r.futureValue * v) / a

        case .periods:
            return try solveForPeriods(r, periodicRate: i)

        case .ratePct:
            return try solveForRate(r)
        }
    }

    /// n from the other four, in closed form.
    ///
    /// At i = 0 the annuity degenerates and `n = −(PV + FV)/PMT`. Otherwise, writing
    /// `A = PMT·k/i` with `k = 1` (end) or `1+i` (begin), the equation collapses to
    /// `(1+i)⁻ⁿ = (PV + A)/(A − FV)`, so n follows from one logarithm.
    private static func solveForPeriods(_ r: Registers, periodicRate i: Double) throws -> Double {
        if i == 0 {
            guard r.payment != 0 else {
                throw SolveError.degenerate("zero rate and zero payment cannot amortise anything")
            }
            let n = -(r.presentValue + r.futureValue) / r.payment
            guard n.isFinite, n > 0 else { throw SolveError.termHasNoSolution }
            return n
        }
        let k = r.timing == .begin ? (1 + i) : 1
        let a = r.payment * k / i
        let numerator = r.presentValue + a
        let denominator = a - r.futureValue
        guard denominator != 0 else { throw SolveError.termHasNoSolution }
        let x = numerator / denominator
        guard x > 0, x.isFinite else { throw SolveError.termHasNoSolution }
        let n = -log(x) / log1p(i)
        guard n.isFinite, n > 0 else { throw SolveError.termHasNoSolution }
        return n
    }

    /// The annual nominal rate, found numerically — there is no closed form for i.
    ///
    /// The residual is monotone in i for any conventional set of registers, so bracketing then
    /// bisecting is both sufficient and unconditionally safe; a Newton step would be faster and
    /// would occasionally leave the bracket. Correctness beats speed at this scale.
    private static func solveForRate(_ r: Registers) throws -> Double {
        guard r.periods > 0 else { throw SolveError.degenerate("n must be > 0 to solve for a rate") }

        func residualAt(_ i: Double) -> Double {
            r.presentValue
                + r.payment * annuityFactor(periodicRate: i, periods: r.periods, timing: r.timing)
                + r.futureValue * discountFactor(periodicRate: i, periods: r.periods)
        }

        // A zero rate is a legitimate answer; check it before hunting for a bracket.
        let atZero = residualAt(0)
        let scale = max(abs(r.presentValue), abs(r.futureValue), abs(r.payment) * r.periods, 1)
        if abs(atZero) <= 1e-14 * scale { return 0 }

        // Expand outward from 0 in both directions until the residual changes sign. The upper limit
        // of 1e6 per period is absurd for finance and exists only to terminate.
        var lo = 0.0, hi = 0.0
        var fLo = atZero, fHi = atZero
        var step = 1e-7
        var bracketed = false
        while step < 1e6 {
            hi = step
            fHi = residualAt(hi)
            if fLo * fHi <= 0 { lo = 0; fLo = atZero; bracketed = true; break }
            let negative = -step
            if negative > -1 {
                let fNeg = residualAt(negative)
                if atZero * fNeg <= 0 { lo = negative; fLo = fNeg; hi = 0; fHi = atZero; bracketed = true; break }
            }
            step *= 2
        }
        guard bracketed else { throw SolveError.noSignChange }

        for _ in 0..<200 {
            let mid = 0.5 * (lo + hi)
            let fMid = residualAt(mid)
            if fMid == 0 { lo = mid; hi = mid; break }
            if fLo * fMid <= 0 { hi = mid; fHi = fMid } else { lo = mid; fLo = fMid }
        }
        let i = 0.5 * (lo + hi)
        guard i.isFinite else { throw SolveError.didNotConverge }
        return annualRatePct(
            periodicRate: i,
            paymentsPerYear: r.paymentsPerYear,
            compoundsPerYear: r.compoundsPerYear
        )
    }
}

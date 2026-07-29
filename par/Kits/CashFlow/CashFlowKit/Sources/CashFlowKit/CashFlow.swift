import Foundation

/// Uneven cash flows: net present value, internal rate of return and the measures built on them.
/// Pure, stateless.
///
/// MODEL CAVEAT (sign convention): money out is negative, money in is positive. `flows[0]` occurs at
/// time zero and is not discounted; `flows[k]` occurs at the end of period k.
///
/// MODEL CAVEAT (periods): every flow sits on an integer period boundary. A cash flow that falls part
/// way through a period (Regulation Z's odd first period, for instance) is a different model and lives
/// in RateKit, which implements Appendix J's fractional unit-period explicitly.
public enum CashFlow {

    // MARK: - Grouped entry

    /// A run of equal consecutive flows — the CFj/Nj entry model, so 360 equal payments are three
    /// numbers rather than 360.
    public struct Group: Equatable, Sendable, Codable {
        public let amount: Double
        public let count: Int

        public init(amount: Double, count: Int) {
            precondition(count >= 1, "a group must contain at least one flow")
            self.amount = amount
            self.count = count
        }

        private enum CodingKeys: String, CodingKey { case amount, count }

        /// Decoding validates and throws — a persisted tape line is untrusted input.
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let count = try c.decode(Int.self, forKey: .count)
            let amount = try c.decode(Double.self, forKey: .amount)
            guard count >= 1 else {
                throw DecodingError.dataCorruptedError(
                    forKey: .count, in: c, debugDescription: "a group needs at least one flow")
            }
            guard amount.isFinite else {
                throw DecodingError.dataCorruptedError(
                    forKey: .amount, in: c, debugDescription: "amount must be finite")
            }
            self.init(amount: amount, count: count)
        }
    }

    /// Expand grouped entry into a flat flow vector.
    public static func expand(_ groups: [Group]) -> [Double] {
        groups.flatMap { Array(repeating: $0.amount, count: $0.count) }
    }

    // MARK: - Discounting

    /// `(1 + rate)⁻ᵏ`, via `log1p` so tiny rates keep their digits.
    public static func discountFactor(rate: Double, period: Double) -> Double {
        precondition(rate > -1, "rate must be > -1")
        if rate == 0 { return 1 }
        return exp(-period * log1p(rate))
    }

    /// Present value of 1 per period for n periods, paid at period end: `(1 − (1+r)⁻ⁿ)/r`.
    /// Degenerates to `n` at r = 0.
    public static func uniformPresentValue(rate: Double, periods: Double) -> Double {
        precondition(rate > -1, "rate must be > -1")
        if rate == 0 { return periods }
        return -expm1(-periods * log1p(rate)) / rate
    }

    /// Net present value at `rate`, with `flows[0]` undiscounted.
    public static func npv(rate: Double, flows: [Double]) -> Double {
        precondition(rate > -1, "rate must be > -1")
        guard !flows.isEmpty else { return 0 }
        // Horner from the tail: numerically better than summing independent powers, and exact at r = 0.
        let v = 1.0 / (1.0 + rate)
        var acc = 0.0
        for flow in flows.reversed() { acc = acc * v + flow }
        return acc
    }

    /// Net future value: the NPV carried forward to the last period.
    public static func nfv(rate: Double, flows: [Double]) -> Double {
        guard !flows.isEmpty else { return 0 }
        let n = Double(flows.count - 1)
        return npv(rate: rate, flows: flows) * exp(n * log1p(rate))
    }

    // MARK: - IRR

    /// What an IRR search found. There is no honest single `Double` here: conventional flows have one
    /// root, flows with several sign changes can have several or none, and returning one of them
    /// silently is how a calculator lies.
    public enum IRRResult: Equatable, Sendable, Codable {
        /// Exactly one rate in the searched range sets NPV to zero.
        case unique(Double)
        /// More than one rate does. All of them, ascending — the caller must choose knowingly.
        case multiple([Double])
        /// No rate in the searched range does.
        case none

        /// The single rate, when there is exactly one. Nil for `.multiple` and `.none` — deliberately,
        /// so a caller has to handle the ambiguous cases rather than defaulting through them.
        public var rate: Double? {
            if case .unique(let r) = self { return r }
            return nil
        }
    }

    /// Internal rate of return: the rate at which NPV is zero.
    ///
    /// Scans `[lowerBound, upperBound]` on a fine grid, then bisects every sign change it finds. That
    /// is slower than Newton from a guess and cannot be fooled by a bad starting point into converging
    /// on the wrong root of a multi-root problem, which is the failure that matters here.
    ///
    /// - Parameters:
    ///   - lowerBound: most negative rate considered (default −0.9999, just above total loss).
    ///   - upperBound: most positive rate considered (default 10.0, i.e. 1000% per period).
    public static func irr(
        flows: [Double],
        lowerBound: Double = -0.9999,
        upperBound: Double = 10.0,
        samples: Int = 2_000
    ) -> IRRResult {
        precondition(lowerBound > -1 && upperBound > lowerBound, "invalid search range")
        precondition(samples >= 2, "need at least two samples")
        guard flows.count >= 2, flows.contains(where: { $0 > 0 }), flows.contains(where: { $0 < 0 })
        else { return .none }

        var roots: [Double] = []
        var previousRate = lowerBound
        var previousValue = npv(rate: previousRate, flows: flows)
        if previousValue == 0 { roots.append(previousRate) }

        for step in 1...samples {
            let rate = lowerBound + (upperBound - lowerBound) * Double(step) / Double(samples)
            let value = npv(rate: rate, flows: flows)
            if value == 0 {
                roots.append(rate)
            } else if previousValue != 0 && (previousValue < 0) != (value < 0) {
                roots.append(bisect(flows: flows, lo: previousRate, hi: rate))
            }
            previousRate = rate
            previousValue = value
        }

        // Collapse roots that are the same root found twice at the grid resolution.
        var distinct: [Double] = []
        for root in roots.sorted() where distinct.last.map({ abs(root - $0) > 1e-9 }) ?? true {
            distinct.append(root)
        }
        switch distinct.count {
        case 0: return .none
        case 1: return .unique(distinct[0])
        default: return .multiple(distinct)
        }
    }

    private static func bisect(flows: [Double], lo: Double, hi: Double) -> Double {
        var lo = lo, hi = hi
        var fLo = npv(rate: lo, flows: flows)
        for _ in 0..<200 {
            let mid = 0.5 * (lo + hi)
            let fMid = npv(rate: mid, flows: flows)
            if fMid == 0 { return mid }
            if (fLo < 0) != (fMid < 0) { hi = mid } else { lo = mid; fLo = fMid }
        }
        return 0.5 * (lo + hi)
    }

    /// Modified internal rate of return: negatives discounted at `financeRate`, positives compounded
    /// at `reinvestRate`. Single-valued by construction, which is the point of it.
    ///
    /// MODEL CAVEAT: MIRR is a *definition*, not a market convention — it answers "what constant rate
    /// turns the present value of the costs into the future value of the benefits". It has no published
    /// worked example in this Kit's sources, so it is asserted against its own definition and against
    /// IRR in the case where the two must agree (financeRate = reinvestRate = IRR).
    public static func mirr(flows: [Double], financeRate: Double, reinvestRate: Double) -> Double? {
        precondition(financeRate > -1 && reinvestRate > -1, "rates must be > -1")
        guard flows.count >= 2 else { return nil }
        let n = Double(flows.count - 1)

        var pvNegative = 0.0
        var fvPositive = 0.0
        for (index, flow) in flows.enumerated() {
            let k = Double(index)
            if flow < 0 {
                pvNegative += flow * discountFactor(rate: financeRate, period: k)
            } else if flow > 0 {
                fvPositive += flow * exp((n - k) * log1p(reinvestRate))
            }
        }
        guard pvNegative < 0, fvPositive > 0, n > 0 else { return nil }
        return exp(log(fvPositive / -pvNegative) / n) - 1
    }

    // MARK: - Payback

    /// Periods until cumulative undiscounted flows first turn non-negative, interpolated within the
    /// period in which it happens. Nil when they never do.
    public static func payback(flows: [Double]) -> Double? {
        payback(flows: flows, rate: 0)
    }

    /// Discounted payback: the same measure on flows discounted at `rate`.
    public static func discountedPayback(flows: [Double], rate: Double) -> Double? {
        payback(flows: flows, rate: rate)
    }

    private static func payback(flows: [Double], rate: Double) -> Double? {
        guard !flows.isEmpty else { return nil }
        var cumulative = 0.0
        for (index, flow) in flows.enumerated() {
            let discounted = flow * discountFactor(rate: rate, period: Double(index))
            let previous = cumulative
            cumulative += discounted
            if cumulative >= 0 && index > 0 && previous < 0 {
                // Linear interpolation inside the period that crosses zero.
                let fraction = discounted == 0 ? 0 : -previous / discounted
                return Double(index - 1) + fraction
            }
            if index == 0 && cumulative >= 0 { return 0 }
        }
        return nil
    }
}

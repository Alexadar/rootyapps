import Foundation

/// One- and two-variable statistics, regression and forecasting. Pure, stateless.
///
/// MODEL CAVEAT (numerically stable by construction): variance is computed with Welford's one-pass
/// recurrence and regression with a two-pass centred formula, **not** `Σx² − n·x̄²`. The textbook form
/// loses catastrophically when the data has a large mean relative to its spread — NIST publishes a
/// dataset (`NumAcc2`: 1001 values of 1.1/1.2/1.3, whose exact standard deviation is 0.1) precisely to
/// expose it, and this Kit is tested against it.
///
/// MODEL CAVEAT (sample vs population): `sampleStandardDeviation` divides by n − 1, which is what the
/// NIST certified values and every finance convention use; `populationStandardDeviation` divides by n.
/// Both are offered because both are asked for, and mixing them silently is a common error.
public enum Stat {

    // MARK: - One variable

    /// Summary statistics for a single variable.
    public struct Summary: Equatable, Sendable, Codable {
        public let count: Int
        public let sum: Double
        public let sumOfSquares: Double
        public let mean: Double
        /// Divides by n − 1. Zero when there is a single observation.
        public let sampleStandardDeviation: Double
        /// Divides by n.
        public let populationStandardDeviation: Double
        public let minimum: Double
        public let maximum: Double

        public var sampleVariance: Double { sampleStandardDeviation * sampleStandardDeviation }
        public var populationVariance: Double { populationStandardDeviation * populationStandardDeviation }
        public var range: Double { maximum - minimum }
    }

    /// Summarise one variable in a single pass, via Welford's recurrence.
    ///
    /// - Precondition: at least one observation. An empty summary would have to invent a mean.
    public static func summary(_ values: [Double]) -> Summary {
        precondition(!values.isEmpty, "need at least one observation")
        var count = 0
        var mean = 0.0
        var m2 = 0.0          // Σ(x − x̄)², accumulated stably
        var sum = 0.0
        var sumOfSquares = 0.0
        var minimum = Double.infinity
        var maximum = -Double.infinity

        for x in values {
            count += 1
            let delta = x - mean
            mean += delta / Double(count)
            m2 += delta * (x - mean)          // uses both the old and new mean: this is the stable form
            sum += x
            sumOfSquares += x * x
            minimum = Swift.min(minimum, x)
            maximum = Swift.max(maximum, x)
        }

        let n = Double(count)
        return Summary(
            count: count,
            sum: sum,
            sumOfSquares: sumOfSquares,
            mean: mean,
            sampleStandardDeviation: count > 1 ? (m2 / (n - 1)).squareRoot() : 0,
            populationStandardDeviation: (m2 / n).squareRoot(),
            minimum: minimum,
            maximum: maximum
        )
    }

    /// The median, by sorting a copy. Averages the middle pair for an even count.
    public static func median(_ values: [Double]) -> Double {
        precondition(!values.isEmpty, "need at least one observation")
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count % 2 == 1 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2
    }

    /// Lag-`k` sample autocorrelation, in the form NIST's StRD univariate datasets certify:
    /// `Σ(xᵢ − x̄)(xᵢ₊ₖ − x̄) / Σ(xᵢ − x̄)²`.
    public static func autocorrelation(_ values: [Double], lag k: Int = 1) -> Double {
        precondition(k >= 1, "lag must be >= 1")
        precondition(values.count > k, "need more observations than the lag")
        let mean = summary(values).mean
        var numerator = 0.0
        var denominator = 0.0
        for index in values.indices {
            let centred = values[index] - mean
            denominator += centred * centred
            if index + k < values.count {
                numerator += centred * (values[index + k] - mean)
            }
        }
        precondition(denominator > 0, "a constant series has no autocorrelation")
        return numerator / denominator
    }

    // MARK: - Two variables

    /// Which curve is fitted. Each non-linear model is a linear fit on transformed data, which is what
    /// makes it a *linear* regression of something — stated here rather than implied.
    public enum Model: String, CaseIterable, Sendable, Codable {
        /// y = a + b·x
        case linear
        /// y = a + b·ln(x) — requires x > 0.
        case logarithmic
        /// y = a·e^(b·x) — requires y > 0. Fitted as ln(y) on x.
        case exponential
        /// y = a·x^b — requires x > 0 and y > 0. Fitted as ln(y) on ln(x).
        case power

        public var displayName: String {
            switch self {
            case .linear: return "Linear"
            case .logarithmic: return "Logarithmic"
            case .exponential: return "Exponential"
            case .power: return "Power"
            }
        }

        /// Whether the model requires strictly positive x, y, or both.
        public var requiresPositive: (x: Bool, y: Bool) {
            switch self {
            case .linear: return (false, false)
            case .logarithmic: return (true, false)
            case .exponential: return (false, true)
            case .power: return (true, true)
            }
        }
    }

    /// A fitted model, with the diagnostics NIST certifies for a linear least-squares fit.
    public struct Fit: Equatable, Sendable, Codable {
        public let model: Model
        /// The `a` of the model as written in `Model` — already back-transformed for the
        /// exponential and power fits, so it can be used directly.
        public let intercept: Double
        /// The `b` of the model as written in `Model`.
        public let slope: Double
        /// Standard deviation of the intercept estimate (on the fitted, possibly transformed, scale).
        public let interceptStandardDeviation: Double
        /// Standard deviation of the slope estimate (on the fitted scale).
        public let slopeStandardDeviation: Double
        /// Residual standard deviation on the fitted scale, with n − 2 degrees of freedom.
        public let residualStandardDeviation: Double
        /// Coefficient of determination on the fitted scale.
        public let rSquared: Double
        /// Correlation coefficient on the fitted scale, carrying the sign of the slope.
        public let correlation: Double
        public let count: Int
    }

    public enum FitError: Error, Equatable, CustomStringConvertible {
        case tooFewObservations
        case mismatchedLengths
        case nonPositiveInput(Model)
        case noVarianceInX

        public var description: String {
            switch self {
            case .tooFewObservations: return "a two-parameter fit needs at least three observations"
            case .mismatchedLengths: return "x and y must have the same number of observations"
            case .nonPositiveInput(let model):
                return "\(model.displayName) regression requires strictly positive inputs"
            case .noVarianceInX: return "x is constant: no line can be fitted"
            }
        }
    }

    /// Fit a model by least squares.
    ///
    /// The linear fit uses the centred two-pass form `b = Σ(xᵢ − x̄)(yᵢ − ȳ) / Σ(xᵢ − x̄)²`, which is
    /// what lets it reproduce NIST's certified coefficients to the limit of `Double`.
    public static func fit(x: [Double], y: [Double], model: Model = .linear) throws -> Fit {
        guard x.count == y.count else { throw FitError.mismatchedLengths }
        guard x.count >= 3 else { throw FitError.tooFewObservations }

        let needs = model.requiresPositive
        if needs.x && x.contains(where: { $0 <= 0 }) { throw FitError.nonPositiveInput(model) }
        if needs.y && y.contains(where: { $0 <= 0 }) { throw FitError.nonPositiveInput(model) }

        let tx = (model == .logarithmic || model == .power) ? x.map(log) : x
        let ty = (model == .exponential || model == .power) ? y.map(log) : y

        let n = Double(tx.count)
        let meanX = tx.reduce(0, +) / n
        let meanY = ty.reduce(0, +) / n

        var sxx = 0.0, sxy = 0.0, syy = 0.0
        for index in tx.indices {
            let dx = tx[index] - meanX
            let dy = ty[index] - meanY
            sxx += dx * dx
            sxy += dx * dy
            syy += dy * dy
        }
        guard sxx > 0 else { throw FitError.noVarianceInX }

        let slope = sxy / sxx
        let intercept = meanY - slope * meanX

        var residualSumOfSquares = 0.0
        for index in tx.indices {
            let residual = ty[index] - (intercept + slope * tx[index])
            residualSumOfSquares += residual * residual
        }
        let degreesOfFreedom = n - 2
        let residualVariance = degreesOfFreedom > 0 ? residualSumOfSquares / degreesOfFreedom : 0
        let residualSD = residualVariance.squareRoot()
        let slopeSD = (residualVariance / sxx).squareRoot()
        let interceptSD = (residualVariance * (1 / n + meanX * meanX / sxx)).squareRoot()
        let rSquared = syy > 0 ? 1 - residualSumOfSquares / syy : 1
        let correlation = syy > 0 ? sxy / (sxx * syy).squareRoot() : 0

        // Back-transform the intercept so callers can use the model as written.
        let reportedIntercept = (model == .exponential || model == .power) ? exp(intercept) : intercept

        return Fit(
            model: model,
            intercept: reportedIntercept,
            slope: slope,
            interceptStandardDeviation: interceptSD,
            slopeStandardDeviation: slopeSD,
            residualStandardDeviation: residualSD,
            rSquared: rSquared,
            correlation: correlation,
            count: tx.count
        )
    }

    /// Predict y at a given x under a fitted model.
    public static func forecastY(x: Double, fit: Fit) -> Double {
        switch fit.model {
        case .linear: return fit.intercept + fit.slope * x
        case .logarithmic:
            precondition(x > 0, "logarithmic forecast requires x > 0")
            return fit.intercept + fit.slope * log(x)
        case .exponential: return fit.intercept * exp(fit.slope * x)
        case .power:
            precondition(x > 0, "power forecast requires x > 0")
            return fit.intercept * pow(x, fit.slope)
        }
    }

    /// Invert the fit: the x at which the model predicts a given y.
    ///
    /// - Precondition: the slope must be non-zero — a flat model predicts the same y everywhere and
    ///   cannot be inverted.
    public static func forecastX(y: Double, fit: Fit) -> Double {
        precondition(fit.slope != 0, "a zero slope cannot be inverted")
        switch fit.model {
        case .linear: return (y - fit.intercept) / fit.slope
        case .logarithmic: return exp((y - fit.intercept) / fit.slope)
        case .exponential:
            precondition(y / fit.intercept > 0, "exponential inversion requires y/a > 0")
            return log(y / fit.intercept) / fit.slope
        case .power:
            precondition(y / fit.intercept > 0, "power inversion requires y/a > 0")
            return pow(y / fit.intercept, 1 / fit.slope)
        }
    }

    /// Pearson correlation of two variables, computed the stable way.
    public static func correlation(x: [Double], y: [Double]) throws -> Double {
        try fit(x: x, y: y, model: .linear).correlation
    }

    /// Σxy — one of the registers a two-variable calculator exposes directly.
    public static func sumOfProducts(x: [Double], y: [Double]) throws -> Double {
        guard x.count == y.count else { throw FitError.mismatchedLengths }
        return zip(x, y).reduce(0) { $0 + $1.0 * $1.1 }
    }
}

// MARK: - Decoding a fit or a summary that was never produced by this Kit

extension Stat.Fit {
    /// A stored fit is untrusted input.
    ///
    /// The synthesized decoder accepts any nine well-formed numbers, so a hand-edited tape can
    /// present a fit with two observations, a negative standard deviation, or a correlation of 9 —
    /// none of which `Stat.fit` can produce — and the app would draw it as a result. The properties
    /// that hold for every fit this Kit computes are re-checked here.
    ///
    /// Bounds carry a small tolerance because `rSquared` and `correlation` are computed, not stored:
    /// a legitimate near-perfect fit can land a few ulps outside [0, 1] and that is arithmetic, not
    /// corruption.
    ///
    /// Declared in an extension so the memberwise initialiser `fit` uses is still synthesized.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let model = try c.decode(Stat.Model.self, forKey: .model)
        let intercept = try c.decode(Double.self, forKey: .intercept)
        let slope = try c.decode(Double.self, forKey: .slope)
        let interceptSD = try c.decode(Double.self, forKey: .interceptStandardDeviation)
        let slopeSD = try c.decode(Double.self, forKey: .slopeStandardDeviation)
        let residualSD = try c.decode(Double.self, forKey: .residualStandardDeviation)
        let rSquared = try c.decode(Double.self, forKey: .rSquared)
        let correlation = try c.decode(Double.self, forKey: .correlation)
        let count = try c.decode(Int.self, forKey: .count)

        func fail(_ why: String) -> DecodingError {
            DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: why))
        }
        let slack = 1e-9
        guard count >= 3 else { throw fail("a fit needs at least three observations, not \(count)") }
        guard intercept.isFinite, slope.isFinite, interceptSD.isFinite, slopeSD.isFinite,
              residualSD.isFinite, rSquared.isFinite, correlation.isFinite else {
            throw fail("a fit must be finite")
        }
        guard interceptSD >= 0, slopeSD >= 0, residualSD >= 0 else {
            throw fail("a standard deviation cannot be negative")
        }
        guard rSquared >= -slack, rSquared <= 1 + slack else {
            throw fail("r squared must lie in [0, 1], not \(rSquared)")
        }
        guard correlation >= -1 - slack, correlation <= 1 + slack else {
            throw fail("a correlation must lie in [-1, 1], not \(correlation)")
        }
        self.init(model: model, intercept: intercept, slope: slope,
                  interceptStandardDeviation: interceptSD, slopeStandardDeviation: slopeSD,
                  residualStandardDeviation: residualSD, rSquared: rSquared,
                  correlation: correlation, count: count)
    }
}

extension Stat.Summary {
    /// As above: a summary of no observations, or one whose minimum exceeds its maximum, is a
    /// corrupt file rather than a degenerate sample.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let count = try c.decode(Int.self, forKey: .count)
        let sum = try c.decode(Double.self, forKey: .sum)
        let sumOfSquares = try c.decode(Double.self, forKey: .sumOfSquares)
        let mean = try c.decode(Double.self, forKey: .mean)
        let sampleSD = try c.decode(Double.self, forKey: .sampleStandardDeviation)
        let populationSD = try c.decode(Double.self, forKey: .populationStandardDeviation)
        let minimum = try c.decode(Double.self, forKey: .minimum)
        let maximum = try c.decode(Double.self, forKey: .maximum)

        func fail(_ why: String) -> DecodingError {
            DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: why))
        }
        guard count >= 1 else { throw fail("a summary needs at least one observation") }
        guard sum.isFinite, sumOfSquares.isFinite, mean.isFinite, sampleSD.isFinite,
              populationSD.isFinite, minimum.isFinite, maximum.isFinite else {
            throw fail("a summary must be finite")
        }
        guard sampleSD >= 0, populationSD >= 0 else {
            throw fail("a standard deviation cannot be negative")
        }
        guard sumOfSquares >= 0 else { throw fail("a sum of squares cannot be negative") }
        guard minimum <= maximum else { throw fail("the minimum exceeds the maximum") }
        self.init(count: count, sum: sum, sumOfSquares: sumOfSquares, mean: mean,
                  sampleStandardDeviation: sampleSD, populationStandardDeviation: populationSD,
                  minimum: minimum, maximum: maximum)
    }
}

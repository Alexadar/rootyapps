import Testing
import Foundation
import StatKit

/// Enforcement guard for the oracle corpus, per `calculators/VALIDATION.md`.
///
/// ORACLES:
///  • GUARD — structural only.
@Suite("Oracle corpus integrity")
struct OracleGuardTests {

    @Test func everyOracleCitesAnExternalSource() {
        for o in Oracles.all {
            #expect(!o.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            #expect(o.source.contains("NIST") && o.source.contains("http"),
                    "oracle '\(o.id)' must cite a locatable document")
            #expect(!o.inputs.isEmpty)
            #expect(!o.precision.isEmpty, "oracle '\(o.id)' has no precision rationale")
        }
    }

    @Test func everyValueHasAMatchingTolerance() {
        for o in Oracles.all {
            #expect(!o.values.isEmpty)
            for key in o.values.keys {
                #expect(o.tolerances[key] != nil, "'\(o.id)'.\(key) has no tolerance")
                #expect((o.tolerances[key] ?? -1) > 0, "'\(o.id)'.\(key) tolerance must be positive")
            }
            for key in o.tolerances.keys { #expect(o.values[key] != nil) }
        }
    }

    @Test func oracleIDsAreUniqueAndResolvable() {
        let ids = Oracles.all.map(\.id)
        #expect(Set(ids).count == ids.count)
        for o in Oracles.all { #expect(Oracles.require(o.id).id == o.id) }
    }

    /// The datasets must be the size NIST says they are — a truncated transcription would make every
    /// certified value meaningless while still looking green.
    @Test func datasetsAreComplete() {
        #expect(Oracles.norrisX.count == 36)
        #expect(Oracles.norrisY.count == 36)
        #expect(Oracles.lewValues.count == 200)
        #expect(Oracles.numAcc2Values.count == 1001)
        #expect(Oracles.require("nist-strd-norris").input("observations") == 36)
        #expect(Oracles.require("nist-strd-lew").input("observations") == 200)
    }

    /// Coverage guard: every regression model the app can offer must be exercised. The three non-linear
    /// models have no NIST dataset, so they are covered by exact-fit reconstruction instead — and that
    /// distinction is recorded here rather than left implicit.
    @Test func everyModelIsClassified() {
        let publishedModels: Set<Stat.Model> = [.linear]                       // NIST Norris
        let reconstructionModels: Set<Stat.Model> = [.logarithmic, .exponential, .power]
        #expect(publishedModels.union(reconstructionModels) == Set(Stat.Model.allCases))
        #expect(publishedModels.isDisjoint(with: reconstructionModels))
    }
}

// Oracle = NIST/ITL Statistical Reference Datasets (public domain),
//          https://www.itl.nist.gov/div898/strd/.  oracle-backed.
/// Regression and summary statistics against NIST's certified values.
///
/// ORACLES:
///  • PUBLISHED — Norris (linear least squares, 36 observations): intercept, slope, both standard
///    deviations, the residual standard deviation and R², all certified by NIST in extended precision.
///  • PUBLISHED — Lew (200 observations): mean, sample standard deviation and lag-1 autocorrelation.
///  • PUBLISHED — NumAcc2 (1001 observations): a dataset NIST built to break the textbook variance
///    formula, with exact certified values.
@Suite("NIST StRD — oracle-backed")
struct NISTOracles {

    @Test func norrisLinearLeastSquares() throws {
        let o = Oracles.require("nist-strd-norris")
        let fit = try Stat.fit(x: Oracles.norrisX, y: Oracles.norrisY, model: .linear)

        #expect(fit.count == 36)
        #expect(o.matches("intercept", fit.intercept), "intercept \(fit.intercept)")
        #expect(o.matches("slope", fit.slope), "slope \(fit.slope)")
        #expect(o.matches("interceptStandardDeviation", fit.interceptStandardDeviation),
                "intercept sd \(fit.interceptStandardDeviation)")
        #expect(o.matches("slopeStandardDeviation", fit.slopeStandardDeviation),
                "slope sd \(fit.slopeStandardDeviation)")
        #expect(o.matches("residualStandardDeviation", fit.residualStandardDeviation),
                "residual sd \(fit.residualStandardDeviation)")
        #expect(o.matches("rSquared", fit.rSquared), "R² \(fit.rSquared)")

        // r² must equal R², and r must carry the slope's sign — the pair the UI shows together.
        #expect(abs(fit.correlation * fit.correlation - fit.rSquared) <= 1e-12)
        #expect(fit.correlation > 0, "Norris is a positive calibration relationship")
    }

    @Test func lewUnivariateSummary() {
        let o = Oracles.require("nist-strd-lew")
        let summary = Stat.summary(Oracles.lewValues)

        #expect(summary.count == 200)
        #expect(o.matches("mean", summary.mean), "mean \(summary.mean)")
        #expect(o.matches("sampleStandardDeviation", summary.sampleStandardDeviation),
                "sd \(summary.sampleStandardDeviation)")
        #expect(o.matches("autocorrelationLag1", Stat.autocorrelation(Oracles.lewValues, lag: 1)),
                "r(1) \(Stat.autocorrelation(Oracles.lewValues, lag: 1))")
    }

    /// NumAcc2 exists to break the textbook formula. Par's stable form must pass it, **and** the
    /// textbook form must visibly fail — otherwise the choice of algorithm is unproven.
    @Test func numAcc2DefeatsTheTextbookVarianceFormula() {
        let o = Oracles.numAcc2Row
        let values = Oracles.numAcc2Values
        let summary = Stat.summary(values)

        #expect(o.matches("mean", summary.mean), "mean \(summary.mean)")
        #expect(o.matches("sampleStandardDeviation", summary.sampleStandardDeviation),
                "stable sd \(summary.sampleStandardDeviation), certified exactly 0.1")
        #expect(o.matches("autocorrelationLag1", Stat.autocorrelation(values, lag: 1)))

        // The textbook form: √((Σx² − n·x̄²)/(n−1)). On this dataset it loses most of its digits.
        let n = Double(values.count)
        let naiveVariance = (summary.sumOfSquares - n * summary.mean * summary.mean) / (n - 1)
        let naiveSD = naiveVariance > 0 ? naiveVariance.squareRoot() : .nan
        let stableError = abs(summary.sampleStandardDeviation - 0.1)
        let naiveError = naiveSD.isNaN ? .infinity : abs(naiveSD - 0.1)
        let message = "the naive form should be far worse or fail outright: naive \(naiveSD),"
            + " stable \(summary.sampleStandardDeviation)"
        #expect(naiveError > stableError * 1e3 || naiveSD.isNaN, Comment(rawValue: message))
    }
}

/// Identities and invariants: exact fits, transformations, and the boundaries.
///
/// ORACLES:
///  • IDENTITY — a fit through points that lie exactly on a curve recovers that curve's parameters; the
///    forecast inverts; r ∈ [−1, 1]; population and sample deviations relate by √((n−1)/n).
///  • INVARIANT — shifting or scaling the data moves the coefficients the way it must; degenerate inputs
///    throw rather than returning a plausible line.
@Suite("Stat — identity and invariant")
struct StatIdentities {

    @Test func summaryOfASingleObservation() {
        let summary = Stat.summary([42])
        #expect(summary.count == 1)
        #expect(summary.mean == 42)
        #expect(summary.sampleStandardDeviation == 0, "n − 1 = 0: no sample spread is defined")
        #expect(summary.populationStandardDeviation == 0)
        #expect(summary.minimum == 42 && summary.maximum == 42)
        #expect(summary.range == 0)
    }

    @Test func sampleAndPopulationDeviationsRelateExactly() {
        let values: [Double] = [2, 4, 4, 4, 5, 5, 7, 9]
        let summary = Stat.summary(values)
        #expect(abs(summary.mean - 5) <= 1e-15)
        #expect(abs(summary.populationStandardDeviation - 2) <= 1e-15, "the textbook example")
        let n = Double(values.count)
        #expect(abs(summary.sampleStandardDeviation
                    - summary.populationStandardDeviation * (n / (n - 1)).squareRoot()) <= 1e-12)
        #expect(summary.sampleStandardDeviation > summary.populationStandardDeviation)
        #expect(abs(Stat.median(values) - 4.5) <= 1e-15)
        #expect(abs(Stat.median([3, 1, 2]) - 2) <= 1e-15, "odd counts take the middle value")
    }

    @Test func constantDataHasZeroSpread() {
        let summary = Stat.summary(Array(repeating: 7.5, count: 50))
        #expect(summary.sampleStandardDeviation == 0)
        #expect(summary.populationStandardDeviation == 0)
        #expect(summary.mean == 7.5)
        #expect(summary.range == 0)
    }

    /// Each model must recover the parameters of a curve its own points lie exactly on. This is the only
    /// oracle available for the three non-linear fits, and it is a strong one: an error in the transform
    /// shows up immediately.
    @Test func everyModelRecoversAnExactCurve() throws {
        let x: [Double] = [1, 2, 3, 4, 5, 6, 7, 8]

        // Linear: y = 3 + 2x
        let linear = try Stat.fit(x: x, y: x.map { 3 + 2 * $0 }, model: .linear)
        #expect(abs(linear.intercept - 3) <= 1e-9)
        #expect(abs(linear.slope - 2) <= 1e-9)
        #expect(abs(linear.rSquared - 1) <= 1e-12)

        // Logarithmic: y = 3 + 2·ln(x)
        let logarithmic = try Stat.fit(x: x, y: x.map { 3 + 2 * log($0) }, model: .logarithmic)
        #expect(abs(logarithmic.intercept - 3) <= 1e-9)
        #expect(abs(logarithmic.slope - 2) <= 1e-9)

        // Exponential: y = 3·e^(0.4x) — the intercept comes back back-transformed.
        let exponential = try Stat.fit(x: x, y: x.map { 3 * exp(0.4 * $0) }, model: .exponential)
        #expect(abs(exponential.intercept - 3) <= 1e-9)
        #expect(abs(exponential.slope - 0.4) <= 1e-9)

        // Power: y = 3·x^1.7
        let power = try Stat.fit(x: x, y: x.map { 3 * pow($0, 1.7) }, model: .power)
        #expect(abs(power.intercept - 3) <= 1e-9)
        #expect(abs(power.slope - 1.7) <= 1e-9)

        // Every exact fit has R² = 1 and |r| = 1.
        for fit in [linear, logarithmic, exponential, power] {
            #expect(abs(fit.rSquared - 1) <= 1e-12, "\(fit.model.displayName) R² = \(fit.rSquared)")
            #expect(abs(abs(fit.correlation) - 1) <= 1e-12)
            #expect(fit.residualStandardDeviation < 1e-9)
        }
    }

    @Test func forecastInvertsForEveryModel() throws {
        let x: [Double] = [1, 2, 3, 4, 5, 6]
        let builders: [(Stat.Model, (Double) -> Double)] = [
            (.linear, { 3 + 2 * $0 }),
            (.logarithmic, { 3 + 2 * log($0) }),
            (.exponential, { 3 * exp(0.4 * $0) }),
            (.power, { 3 * pow($0, 1.7) }),
        ]
        for (model, builder) in builders {
            let fit = try Stat.fit(x: x, y: x.map(builder), model: model)
            for probe in [1.5, 2.75, 4.0, 7.25] {
                let predicted = Stat.forecastY(x: probe, fit: fit)
                #expect(abs(predicted - builder(probe)) <= 1e-6 * max(abs(builder(probe)), 1),
                        "\(model.displayName) predicted \(predicted) at x=\(probe)")
                let recovered = Stat.forecastX(y: predicted, fit: fit)
                #expect(abs(recovered - probe) <= 1e-6 * probe,
                        "\(model.displayName) inverted to \(recovered), expected \(probe)")
            }
        }
    }

    @Test func correlationIsBoundedAndSigned() throws {
        let x: [Double] = [1, 2, 3, 4, 5]
        #expect(abs(try Stat.correlation(x: x, y: [2, 4, 6, 8, 10]) - 1) <= 1e-12)
        #expect(abs(try Stat.correlation(x: x, y: [10, 8, 6, 4, 2]) + 1) <= 1e-12)
        let noisy = try Stat.correlation(x: x, y: [2, 5, 4, 9, 8])
        #expect(noisy > 0 && noisy < 1)
        #expect(abs(try Stat.sumOfProducts(x: x, y: [2, 4, 6, 8, 10]) - 110) <= 1e-12)
    }

    /// Shifting x moves the intercept but never the slope; scaling y scales both.
    @Test func fitsTransformAsTheyMust() throws {
        let x: [Double] = [1, 2, 3, 4, 5, 6, 7]
        let y: [Double] = [2.1, 3.9, 6.2, 7.8, 10.1, 12.2, 13.8]
        let base = try Stat.fit(x: x, y: y)

        let shifted = try Stat.fit(x: x.map { $0 + 100 }, y: y)
        #expect(abs(shifted.slope - base.slope) <= 1e-9, "shifting x must not move the slope")
        #expect(abs(shifted.intercept - (base.intercept - 100 * base.slope)) <= 1e-6)
        #expect(abs(shifted.rSquared - base.rSquared) <= 1e-12)

        let scaled = try Stat.fit(x: x, y: y.map { $0 * 3 })
        #expect(abs(scaled.slope - base.slope * 3) <= 1e-9)
        #expect(abs(scaled.intercept - base.intercept * 3) <= 1e-9)
        #expect(abs(scaled.rSquared - base.rSquared) <= 1e-12, "R² is scale-invariant")
    }

    @Test func degenerateFitsThrowRatherThanGuess() {
        #expect(throws: Stat.FitError.mismatchedLengths) {
            _ = try Stat.fit(x: [1, 2, 3], y: [1, 2])
        }
        #expect(throws: Stat.FitError.tooFewObservations) {
            _ = try Stat.fit(x: [1, 2], y: [1, 2])
        }
        #expect(throws: Stat.FitError.noVarianceInX) {
            _ = try Stat.fit(x: [5, 5, 5, 5], y: [1, 2, 3, 4])
        }
        #expect(throws: Stat.FitError.nonPositiveInput(.logarithmic)) {
            _ = try Stat.fit(x: [0, 1, 2, 3], y: [1, 2, 3, 4], model: .logarithmic)
        }
        #expect(throws: Stat.FitError.nonPositiveInput(.exponential)) {
            _ = try Stat.fit(x: [1, 2, 3, 4], y: [0, 2, 3, 4], model: .exponential)
        }
        #expect(throws: Stat.FitError.nonPositiveInput(.power)) {
            _ = try Stat.fit(x: [1, 2, 3, -4], y: [1, 2, 3, 4], model: .power)
        }
    }

    @Test func autocorrelationOfAnAlternatingSeriesIsNearlyMinusOne() {
        var alternating: [Double] = []
        for index in 0..<200 { alternating.append(index % 2 == 0 ? 1 : -1) }
        #expect(Stat.autocorrelation(alternating, lag: 1) < -0.98)
        // Lag 2 on the same series is nearly +1.
        #expect(Stat.autocorrelation(alternating, lag: 2) > 0.98)
    }

    @Test func modelMetadataIsComplete() {
        #expect(Stat.Model.allCases.count == 4)
        for model in Stat.Model.allCases {
            #expect(!model.displayName.isEmpty)
            #expect(!model.rawValue.isEmpty)
        }
        #expect(Stat.Model.linear.requiresPositive == (false, false))
        #expect(Stat.Model.power.requiresPositive == (true, true))
    }
}

// The replay suite that used to live here now has its own file, `ReplayTests.swift`, matching the
// other nine Kits — and carrying the INVARIANT half it lacked while it was a tail on this one.

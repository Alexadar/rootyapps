import Testing
import Foundation
import RateKit

/// Enforcement guard for the oracle corpus, per `calculators/VALIDATION.md`.
///
/// ORACLES:
///  • GUARD — structural only.
@Suite("Oracle corpus integrity")
struct OracleGuardTests {

    @Test func everyOracleCitesAnExternalSource() {
        for o in Oracles.all {
            #expect(!o.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            #expect(o.source.contains("CFR") && o.source.contains("http"),
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

    /// Coverage guard: Appendix J's examples exist to cover distinct *shapes*, and the corpus must
    /// carry all of them — otherwise a Kit could pass on level loans and be wrong on every real one.
    @Test func appendixJCorpusCoversEveryPublishedShape() {
        #expect(Oracles.appendixJCases.count == 17, "Appendix J (c)(1)-(c)(6) publishes 17 examples")

        let cases = Oracles.appendixJCases
        #expect(cases.contains { !$0.hasFractionalFirstPeriod && $0.series.count == 1 }, "level")
        #expect(cases.contains { $0.hasFractionalFirstPeriod }, "fractional first period")
        #expect(cases.contains { $0.series.count == 2 }, "irregular first or final payment")
        #expect(cases.contains { $0.series.count == 3 }, "irregular first AND final payment")
        #expect(cases.contains { $0.series.count == 4 }, "multi-series skipped-payment loan")
        #expect(cases.contains { $0.totalPayments == 1 }, "single payment")

        // Every unit-period Appendix J uses: weekly, biweekly, 4-weekly, semimonthly, monthly,
        // bimonthly, quarterly, semiannual, annual, and the odd 365/255.
        let frequencies = Set(cases.map { $0.unitPeriodsPerYear })
        #expect(frequencies.count >= 8, "only \(frequencies.count) distinct unit-period frequencies")

        // And each case must have a matching corpus row carrying its published rate.
        for example in cases {
            #expect(Oracles.all.contains { $0.id == example.id && $0.values["aprPct"] != nil })
        }
    }
}

// Oracle = 12 CFR 1026 App J (c)(1)-(c)(6) (CFPB, public domain),
//          https://www.govinfo.gov/content/pkg/CFR-2024-title12-vol9/pdf/CFR-2024-title12-vol9-part1026-appJ.pdf
//          oracle-backed.
/// The actuarial APR against every published Appendix J example.
///
/// ORACLES:
///  • PUBLISHED — all seventeen examples of (c)(1) through (c)(6), each to the two decimals the
///    regulation states. Nine of them have a leading fractional unit-period, which only reproduces
///    with the *simple* interest factor (1 + f·i) the regulation specifies; a compound (1+i)^f passes
///    the level examples and fails these.
@Suite("Regulation Z APR — oracle-backed")
struct AppendixJOracles {

    private func schedule(_ example: AppendixJCase) -> (advances: [Rate.Advance], payments: [Rate.Payment]) {
        let advances = [Rate.Advance(amount: example.advance, fullPeriods: 0, fraction: 0)]
        let payments = example.series.flatMap {
            Rate.series(amount: $0.amount, count: $0.count,
                        firstAtFullPeriods: $0.fullPeriods, fraction: $0.fraction)
        }
        return (advances, payments)
    }

    @Test("published annual percentage rates", arguments: Oracles.appendixJCases.map(\.id))
    func publishedAPRs(id: String) throws {
        let example = Oracles.requireCase(id)
        let o = Oracles.require(id)
        let (advances, payments) = schedule(example)

        let apr = try Rate.aprActuarial(
            advances: advances, payments: payments,
            unitPeriodsPerYear: example.unitPeriodsPerYear
        )
        #expect(o.matches("aprPct", apr),
                "\(example.label): got \(apr)%, published \(o.value("aprPct"))%")
        #expect((apr * 100).rounded() / 100 == o.value("aprPct"),
                "rounded to two decimals it must equal the published rate exactly")
    }

    /// The fractional period earns simple, not compound, interest. Recompute the ten examples that
    /// have one using a compound factor instead: every one of them moves, and three move far enough to
    /// break the published two decimals. That is the honest strength of this claim — measured, not
    /// asserted. (The other seven differ by 0.002-0.004 pp, inside Appendix J's own rounding: the
    /// convention still matters, it just isn't visible at two decimals on those examples.)
    @Test func compoundFractionalPeriodChangesEveryFractionalRate() throws {
        func aprWithCompoundFraction(_ example: AppendixJCase) -> Double {
            func residual(_ i: Double) -> Double {
                let advanced = example.advance
                let repaid = example.series.reduce(0.0) { total, series in
                    total + (0..<series.count).reduce(0.0) { inner, step in
                        let t = Double(series.fullPeriods + step) + series.fraction   // compound
                        return inner + series.amount / pow(1 + i, t)
                    }
                }
                return advanced - repaid
            }
            var lo = 1e-12, hi = 1.0
            for _ in 0..<200 {
                let mid = 0.5 * (lo + hi)
                if residual(lo) * residual(mid) <= 0 { hi = mid } else { lo = mid }
            }
            return 100 * example.unitPeriodsPerYear * 0.5 * (lo + hi)
        }

        let fractional = Oracles.appendixJCases.filter(\.hasFractionalFirstPeriod)
        #expect(fractional.count == 10, "ten of the published examples have a fractional period")

        var brokenAtTwoDecimals = 0
        for example in fractional {
            let (advances, payments) = schedule(example)
            let correct = try Rate.aprActuarial(advances: advances, payments: payments,
                                                unitPeriodsPerYear: example.unitPeriodsPerYear)
            let wrong = aprWithCompoundFraction(example)

            // The convention is load-bearing: swapping it always moves the answer.
            let moved = abs(wrong - correct)
            #expect(moved > 1e-6,
                    Comment(rawValue: "\(example.id): compound vs simple moved only \(moved) pp"))
            // Regulation Z's factor is the one that reproduces the published rate.
            #expect(abs(correct - example.publishedAPR) <= 0.005)
            if abs(wrong - example.publishedAPR) > 0.005 { brokenAtTwoDecimals += 1 }
        }
        #expect(brokenAtTwoDecimals >= 3,
                Comment(rawValue: "only \(brokenAtTwoDecimals) examples visibly break at two decimals"))
    }
}

// Oracle = 12 CFR 1030 App A (CFPB, public domain).  oracle-backed.
/// Annual percentage yield against Regulation DD's own examples.
///
/// ORACLES:
///  • PUBLISHED — the NOW-account and six-month-CD yields from part I, and an APY-earned figure from
///    part II. The 182-day CD is the one that proves the 365/days exponent is applied.
@Suite("Regulation DD APY — oracle-backed")
struct RegDDOracles {

    @Test("published annual percentage yields", arguments: ["regdd-appA-now-account", "regdd-appA-six-month-cd"])
    func publishedAPY(id: String) {
        let o = Oracles.require(id)
        let apy = Rate.apy(
            interest: o.input("interest"),
            principal: o.input("principal"),
            daysInTerm: o.input("daysInTerm")
        )
        #expect(o.matches("apyPct", apy), "\(id): got \(apy)%, published \(o.value("apyPct"))%")
    }

    @Test func publishedAPYEarned() {
        let o = Oracles.require("regdd-appA-apy-earned-statement-period")
        let earned = Rate.apyEarned(
            interestEarned: o.input("interestEarned"),
            averageDailyBalance: o.input("averageDailyBalance"),
            daysInPeriod: o.input("daysInPeriod")
        )
        #expect(o.matches("apyEarnedPct", earned), "got \(earned)%")
    }

    /// A 365-day term makes the exponent 1, so APY is simply interest/principal — Appendix A says so
    /// explicitly, and the NOW-account example is that case.
    @Test func aFullYearTermMakesAPYTheSimpleRatio() {
        let o = Oracles.require("regdd-appA-now-account")
        let simple = 100 * o.input("interest") / o.input("principal")
        let apy = Rate.apy(interest: o.input("interest"), principal: o.input("principal"), daysInTerm: 365)
        #expect(abs(apy - simple) <= 1e-12)
    }

    /// APY inverts: the interest implied by a published APY reproduces the published interest.
    @Test func apyInvertsToInterest() {
        for id in ["regdd-appA-now-account", "regdd-appA-six-month-cd"] {
            let o = Oracles.require(id)
            let apy = Rate.apy(interest: o.input("interest"), principal: o.input("principal"),
                               daysInTerm: o.input("daysInTerm"))
            let back = Rate.interestFromAPY(apyPct: apy, principal: o.input("principal"),
                                            daysInTerm: o.input("daysInTerm"))
            #expect(abs(back - o.input("interest")) <= 1e-9)
        }
    }
}

/// Rate conversions and the US Rule, by identity and invariant.
///
/// ORACLES:
///  • IDENTITY — nominal↔effective round trips at every frequency, including the continuous limit.
///  • INVARIANT — more frequent compounding yields more; the US Rule differs from the actuarial method
///    exactly when a payment fails to cover the interest; add-on rates are roughly double.
@Suite("Rate conversion and the US Rule — identity and invariant")
struct RateIdentities {

    @Test func nominalAndEffectiveRoundTrip() {
        for nominal in [0.0, 0.25, 5.0, 6.5, 18.99, 120.0] {
            for m in [1, 2, 4, 12, 26, 52, 365] {
                let effective = Rate.effectiveAnnualRate(nominalPct: nominal, timesPerYear: m)
                let back = Rate.nominalAnnualRate(effectivePct: effective, timesPerYear: m)
                #expect(abs(back - nominal) <= 1e-10, "round trip failed at \(nominal)%, m=\(m)")
                if nominal > 0 && m > 1 {
                    #expect(effective > nominal, "compounding must add something")
                }
            }
            let continuous = Rate.effectiveAnnualRateContinuous(nominalPct: nominal)
            #expect(abs(Rate.nominalAnnualRateContinuous(effectivePct: continuous) - nominal) <= 1e-10)
            // Continuous compounding is the limit from above of discrete compounding.
            #expect(continuous >= Rate.effectiveAnnualRate(nominalPct: nominal, timesPerYear: 365) - 1e-9)
        }
        // Annual compounding changes nothing.
        #expect(abs(Rate.effectiveAnnualRate(nominalPct: 7, timesPerYear: 1) - 7) <= 1e-12)
        // 12% monthly is the textbook 12.6825%.
        #expect(abs(Rate.effectiveAnnualRate(nominalPct: 12, timesPerYear: 12) - 12.682503013196973) <= 1e-9)
    }

    @Test func effectiveRateRisesWithFrequency() {
        var previous = 0.0
        for m in [1, 2, 4, 12, 52, 365, 8760] {
            let effective = Rate.effectiveAnnualRate(nominalPct: 10, timesPerYear: m)
            #expect(effective > previous)
            previous = effective
        }
        #expect(previous < Rate.effectiveAnnualRateContinuous(nominalPct: 10))
    }

    /// The US Rule and the actuarial method agree whenever every payment covers its period's interest —
    /// there is nothing to defer, so the two definitions coincide.
    @Test func usRuleMatchesActuarialWhenEveryPaymentCoversInterest() throws {
        let example = Oracles.requireCase("regz-appJ-c1-i")
        let payments = Array(repeating: 230.0, count: 24)
        let usRule = try Rate.aprUnitedStatesRule(
            principal: example.advance, payments: payments, unitPeriodsPerYear: 12
        )
        let actuarial = try Rate.aprActuarial(
            advances: [.init(amount: example.advance, fullPeriods: 0)],
            payments: Rate.series(amount: 230, count: 24, firstAtFullPeriods: 1),
            unitPeriodsPerYear: 12
        )
        #expect(abs(usRule - actuarial) <= 1e-6, "US Rule \(usRule) vs actuarial \(actuarial)")
        #expect(abs(usRule - example.publishedAPR) <= 0.005)
    }

    /// …and they diverge exactly when a payment does not cover the interest: under the US Rule the
    /// shortfall waits without compounding, so the same schedule implies a *higher* rate.
    @Test func usRuleDivergesWhenAPaymentIsTooSmall() throws {
        // A token first payment, then twelve real ones.
        var payments = [1.0]
        payments.append(contentsOf: Array(repeating: 950.0, count: 12))

        let usRule = try Rate.aprUnitedStatesRule(
            principal: 10_000, payments: payments, unitPeriodsPerYear: 12
        )
        var appendixJPayments = [Rate.Payment(amount: 1.0, fullPeriods: 1)]
        appendixJPayments.append(contentsOf: Rate.series(amount: 950, count: 12, firstAtFullPeriods: 2))
        let actuarial = try Rate.aprActuarial(
            advances: [.init(amount: 10_000, fullPeriods: 0)],
            payments: appendixJPayments,
            unitPeriodsPerYear: 12
        )
        #expect(usRule > actuarial,
                "deferring uncompounded interest implies a higher rate: \(usRule) vs \(actuarial)")
        #expect(usRule - actuarial > 0.01, "the divergence must be material, not noise")
    }

    /// An add-on rate is roughly twice the true rate, because interest is charged on the whole
    /// principal for the whole term while the borrower repays it along the way.
    @Test func addOnRateIsRoughlyDoubleTheActuarialRate() throws {
        let apr = try Rate.addOnToActuarialAPR(
            principal: 10_000, addOnRatePct: 6, years: 4, paymentsPerYear: 12
        )
        #expect(apr > 10.5 && apr < 11.5, "6% add-on over 4 years is about 11% APR — got \(apr)")
        // The rule of thumb, stated as an invariant rather than a magic number.
        #expect(apr > 1.7 * 6 && apr < 2.0 * 6)
    }

    /// A schedule that repays far less than it advanced has a real, hugely negative rate — and saying
    /// so is more honest than refusing. What must throw is a schedule with no root at all.
    @Test func aprReportsNegativeRatesAndRefusesRootlessSchedules() throws {
        let disastrous = try Rate.aprActuarial(
            advances: [.init(amount: 10_000, fullPeriods: 0)],
            payments: Rate.series(amount: 1, count: 12, firstAtFullPeriods: 1),
            unitPeriodsPerYear: 12
        )
        #expect(disastrous < -100, "repaying $12 of a $10,000 advance is a catastrophic negative rate")

        // Payments of zero can never balance an advance at any rate: no root exists.
        #expect(throws: Rate.RateError.noSignChange) {
            _ = try Rate.aprActuarial(
                advances: [.init(amount: 10_000, fullPeriods: 0)],
                payments: Rate.series(amount: 0, count: 12, firstAtFullPeriods: 1),
                unitPeriodsPerYear: 12
            )
        }
        #expect(throws: Rate.RateError.emptySchedule) {
            _ = try Rate.aprActuarial(advances: [.init(amount: 100, fullPeriods: 0)],
                                      payments: [], unitPeriodsPerYear: 12)
        }
    }

    /// A zero-interest loan — pay back exactly what you borrowed, on schedule — is 0% APR, not an error.
    @Test func zeroInterestLoanIsZeroAPR() throws {
        let apr = try Rate.aprActuarial(
            advances: [.init(amount: 1200, fullPeriods: 0)],
            payments: Rate.series(amount: 100, count: 12, firstAtFullPeriods: 1),
            unitPeriodsPerYear: 12
        )
        #expect(abs(apr) <= 1e-6, "got \(apr)")
    }

    /// Appendix J's present-value factor, checked against its own definition at the boundaries.
    @Test func appendixJPresentValueFactorBehaves() {
        // No fraction, no periods: the amount is undiscounted.
        #expect(Rate.appendixJPresentValue(amount: 100, fullPeriods: 0, fraction: 0, periodicRate: 0.01) == 100)
        // A fraction discounts by simple interest only.
        let half = Rate.appendixJPresentValue(amount: 100, fullPeriods: 0, fraction: 0.5, periodicRate: 0.10)
        #expect(abs(half - 100 / 1.05) <= 1e-12, "simple: 1 + 0.5×0.10")
        #expect(abs(half - 100 / pow(1.10, 0.5)) > 1e-3, "…and not compound")
        // Full periods compound.
        let year = Rate.appendixJPresentValue(amount: 100, fullPeriods: 12, fraction: 0, periodicRate: 0.01)
        #expect(abs(year - 100 / pow(1.01, 12)) <= 1e-12)
    }
}

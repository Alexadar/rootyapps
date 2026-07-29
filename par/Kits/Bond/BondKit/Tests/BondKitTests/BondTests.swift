import Testing
import Foundation
import BondKit

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

    /// Coverage guard: Appendix B publishes a *different formula* for each first-period case, so every
    /// case the app can select must have a published price behind it. Adding a case without an oracle
    /// fails here — which is the only thing standing between "we support reopenings" and a silent
    /// mispricing.
    @Test func everyFirstPeriodCaseHasAPublishedPrice() {
        let covered: [Bond.FirstPeriod: String] = [
            .regular: "treasury-II-A-price",
            .short: "treasury-II-B-price-short-first",
            .long: "treasury-II-C-price-long-first",
            .reopenedRegular: "treasury-II-D-price-reopening",
            .reopenedLongRegularPortion: "treasury-II-E-price-reopening-long",
        ]
        for firstPeriod in Bond.FirstPeriod.allCases {
            guard let id = covered[firstPeriod] else {
                Issue.record("no published oracle covers \(firstPeriod.rawValue)")
                continue
            }
            #expect(Oracles.all.contains { $0.id == id && $0.values["price"] != nil })
        }
        #expect(covered.count == Bond.FirstPeriod.allCases.count)
    }

    /// Both bill branches, and the boundary between them, must be covered.
    @Test func bothBillBranchesHavePublishedRates() {
        let short = Oracles.require("treasury-VI-D-1-investment-rate")
        let long = Oracles.require("treasury-VI-D-2-investment-rate")
        #expect(short.input("r") <= short.input("y") / 2, "the simple branch")
        #expect(long.input("r") > long.input("y") / 2, "the quadratic branch")
    }
}

// Oracle = 31 CFR 356 App B (US Treasury, public domain),
//          https://www.govinfo.gov/content/pkg/CFR-2024-title31-vol2/pdf/CFR-2024-title31-vol2-part356-appB.pdf
//          oracle-backed.
/// Price from yield, against Treasury's own five worked examples.
///
/// ORACLES:
///  • PUBLISHED — §II.A, §II.B, §II.C, §II.D and §II.E: a regular period, a short first period, a long
///    first period, a reopening in a regular period, and a reopening in the regular portion of a long
///    first period. Five formulas, five published prices.
///  • PUBLISHED — the vⁿ and aₙ Treasury prints alongside, to ten decimals.
@Suite("Price from yield — oracle-backed")
struct PriceOracles {

    private func terms(_ o: Oracle, firstPeriod: Bond.FirstPeriod) -> Bond.Terms {
        Bond.Terms(
            couponPct: o.input("couponPct"),
            fullPeriods: Int(o.input("n")),
            daysToNextCoupon: Int(o.input("r")),
            daysInPeriod: Int(o.input("s")),
            firstPeriod: firstPeriod,
            fractionalPortionDays: Int(o.inputs["rPrime"] ?? 0),
            fractionalPortionPeriodDays: Int(o.inputs["sDoublePrime"] ?? 1)
        )
    }

    @Test func regularFirstPeriod() {
        let o = Oracles.require("treasury-II-A-price")
        let t = terms(o, firstPeriod: .regular)
        let quote = Bond.quote(t, yield: o.input("yield"))
        #expect(o.matches("price", quote.price), "got \(quote.price)")
        #expect(quote.accruedInterest == 0, "settlement on a coupon date accrues nothing")
        #expect(o.matches("discountFactor",
                          Bond.discountFactor(yield: o.input("yield"), periods: Int(o.input("n")))))
        #expect(o.matches("annuityFactor",
                          Bond.annuityFactor(yield: o.input("yield"), periods: Int(o.input("n")))))
    }

    @Test func shortFirstPeriod() {
        let o = Oracles.require("treasury-II-B-price-short-first")
        let quote = Bond.quote(terms(o, firstPeriod: .short), yield: o.input("yield"))
        #expect(o.matches("price", quote.price), "got \(quote.price)")
    }

    @Test func longFirstPeriod() {
        let o = Oracles.require("treasury-II-C-price-long-first")
        let quote = Bond.quote(terms(o, firstPeriod: .long), yield: o.input("yield"))
        #expect(o.matches("price", quote.price), "got \(quote.price)")
        #expect(o.matches("onePeriodDiscount", Bond.discountFactor(yield: o.input("yield"), periods: 1)))

        // The long-first formula must differ from the regular one on the same terms — otherwise the
        // case distinction is decorative.
        let asRegular = Bond.price(terms(o, firstPeriod: .regular), yield: o.input("yield"))
        #expect(abs(asRegular - quote.price) > 1e-4, "the long-first stub discount must bite")
    }

    @Test func reopeningInARegularPeriod() {
        let o = Oracles.require("treasury-II-D-price-reopening")
        let t = terms(o, firstPeriod: .reopenedRegular)
        let quote = Bond.quote(t, yield: o.input("yield"))
        #expect(o.matches("accruedInterest", quote.accruedInterest))
        #expect(o.matches("price", quote.price), "got \(quote.price)")
        #expect(o.matches("settlementAmount", quote.settlementAmount))
        #expect(Bond.accruedInterest(t) == quote.accruedInterest)
    }

    @Test func reopeningInALongFirstPeriod() {
        let o = Oracles.require("treasury-II-E-price-reopening-long")
        let t = terms(o, firstPeriod: .reopenedLongRegularPortion)
        let quote = Bond.quote(t, yield: o.input("yield"))
        #expect(o.matches("accruedInterest", quote.accruedInterest), "got \(quote.accruedInterest)")
        #expect(o.matches("price", quote.price), "got \(quote.price)")
        #expect(o.matches("settlementAmount", quote.settlementAmount))
        #expect(Bond.accruedInterestAcrossLongFirstPeriod(t) == quote.accruedInterest)
    }

    /// The fractional first period earns **simple** interest. Price §II.D with a compound stub instead
    /// and it misses the published figure by ~7.7e-3 per 100 — while §II.A, where r = s, still matches.
    /// That asymmetry is exactly why this convention has to be pinned by a case with r ≠ s.
    @Test func compoundStubDiscountingBreaksTheReopeningPrice() {
        let o = Oracles.require("treasury-II-D-price-reopening")
        let t = terms(o, firstPeriod: .reopenedRegular)
        let i = o.input("yield")
        let ratio = Double(t.daysToNextCoupon) / Double(t.daysInPeriod)
        let c2 = t.couponPct / 2
        let deferred = c2 * Bond.annuityFactor(yield: i, periods: t.fullPeriods)
            + 100 * Bond.discountFactor(yield: i, periods: t.fullPeriods)

        let compound = (c2 + deferred) / pow(1 + i / 2, ratio) - Bond.accruedInterest(t)
        let simple = Bond.price(t, yield: i)

        #expect(o.matches("price", simple))
        #expect(!o.matches("price", compound),
                "a compound stub must NOT reproduce the published price — got \(compound)")
        #expect(abs(compound - simple) > 5e-3, "the two conventions differ by \(abs(compound - simple))")
    }
}

// Oracle = 31 CFR 356 App B §I.D(2), §VI, §III (US Treasury, public domain).  oracle-backed.
/// Accrued interest, bills and TIPS.
///
/// ORACLES:
///  • PUBLISHED — the two-half-year reopening accrual (including Treasury's nine-decimal daily figures
///    and the $11,000-par money amount), both bill branches with their published quadratic coefficients,
///    and the TIPS index ratio with its truncation.
@Suite("Accrued interest, bills and TIPS — oracle-backed")
struct AccruedBillsAndTIPSOracles {

    @Test func accruedInterestAcrossTwoHalfYears() {
        let o = Oracles.require("treasury-I-D-accrued-two-half-years")
        let accrued = Bond.accruedInterestAcrossTwoHalfYears(
            couponPct: o.input("couponPct"), par: o.input("par"),
            firstHalfYearDays: Int(o.input("firstHalfYearDays")),
            firstHalfYearLength: Int(o.input("firstHalfYearLength")),
            secondHalfYearDays: Int(o.input("secondHalfYearDays")),
            secondHalfYearLength: Int(o.input("secondHalfYearLength"))
        )
        #expect(o.matches("accruedInterest", accrued), "got \(accrued)")

        // Treasury prints the daily accrual figures it rounds to nine decimals; check those directly.
        let semiannual = o.input("par") * (o.input("couponPct") / 100) / 2
        #expect(o.matches("dailyFirstHalf",
                          (semiannual / o.input("firstHalfYearLength") * 1e9).rounded() / 1e9))
        #expect(o.matches("dailySecondHalf",
                          (semiannual / o.input("secondHalfYearLength") * 1e9).rounded() / 1e9))

        // Treasury's own scaling step: 11 × the per-$1,000 figure, rounded to the cent.
        let elevenThousand = ((accrued * 1e5).rounded() / 1e5) * 11
        #expect(o.matches("elevenThousandPar", elevenThousand), "got \(elevenThousand)")

        // Without Treasury's rounding the answer moves in the eighth decimal — recorded, not hidden.
        let exact = Bond.accruedInterestAcrossTwoHalfYears(
            couponPct: o.input("couponPct"), par: o.input("par"),
            firstHalfYearDays: 44, firstHalfYearLength: 181,
            secondHalfYearDays: 81, secondHalfYearLength: 184,
            roundDailyAccrualToNineDecimals: false
        )
        #expect(abs(exact - o.value("accruedInterest")) > 1e-9)
        #expect(abs(exact - o.value("accruedInterest")) < 1e-7)
    }

    @Test func billPriceFromDiscountRate() {
        let o = Oracles.require("treasury-VI-A-bill-price")
        let price = Bond.billPrice(discountRate: o.input("discountRate"), daysToMaturity: Int(o.input("r")))
        #expect(o.matches("price", price), "got \(price)")
        // And the inverse recovers the published discount rate.
        let back = Bond.billDiscountRate(price: price, daysToMaturity: Int(o.input("r")))
        #expect(abs(back - o.input("discountRate")) <= 1e-15)
    }

    @Test func billInvestmentRateSimpleBranch() {
        let o = Oracles.require("treasury-VI-D-1-investment-rate")
        let rate = Bond.billInvestmentRate(
            price: o.input("price"), daysToMaturity: Int(o.input("r")), daysInYear: Int(o.input("y"))
        )
        #expect(o.matches("investmentRate", rate), "got \(rate)")
    }

    @Test func billInvestmentRateQuadraticBranch() {
        let o = Oracles.require("treasury-VI-D-2-investment-rate")
        let r = o.input("r"), y = o.input("y"), price = o.input("price")
        let rate = Bond.billInvestmentRate(price: price, daysToMaturity: Int(r), daysInYear: Int(y))
        #expect(o.matches("investmentRate", rate), "got \(rate)")

        // Treasury prints a, b and c; check the coefficients, not just the answer.
        #expect(o.matches("a", r / (2 * y) - 0.25))
        #expect(o.matches("b", r / y))
        #expect(o.matches("c", (price - 100) / price))

        // The published rate must satisfy the equation it came from: P[1 + (r − y/2)(i/y)](1 + i/2) = 100.
        let i = o.value("investmentRate")
        let closes = price * (1 + (r - y / 2) * (i / y)) * (1 + i / 2)
        #expect(abs(closes - 100) <= 1e-5, "the quadratic must close: \(closes)")
    }

    @Test func tipsIndexRatioIsTruncated() {
        let o = Oracles.require("treasury-III-index-ratio")
        let ratio = Bond.indexRatio(
            referenceCPI: o.input("referenceCPI"), referenceCPIAtIssue: o.input("referenceCPIAtIssue")
        )
        #expect(o.matches("indexRatio", ratio), "got \(ratio)")

        // Truncation, not rounding: the exact ratio is 1.0107424…, which would round to 1.01074 as well,
        // so prove the behaviour on a value where the two differ.
        #expect(Bond.indexRatio(referenceCPI: 1.0000099, referenceCPIAtIssue: 1, decimals: 5) == 1.00000)
        #expect(Bond.adjustedPrincipal(par: 100_000, indexRatio: ratio) == 100_000 * ratio)
    }
}

/// Identities and invariants: inversion, duration as a derivative, and the boundaries.
///
/// ORACLES:
///  • IDENTITY — yield(price(y)) = y; aₙ = (1 − vⁿ)/(i/2); duration is minus the price derivative.
///  • INVARIANT — price falls as yield rises, par pricing at the coupon rate, the i = 0 special case
///    Appendix B spells out, and the bill branch boundary.
@Suite("Bond — identity and invariant")
struct BondIdentities {

    static let terms: [Bond.Terms] = [
        .init(couponPct: 8.75, fullPeriods: 59, daysToNextCoupon: 184, daysInPeriod: 184),
        .init(couponPct: 9.50, fullPeriods: 19, daysToNextCoupon: 167, daysInPeriod: 181,
              firstPeriod: .reopenedRegular),
        .init(couponPct: 2.00, fullPeriods: 3, daysToNextCoupon: 90, daysInPeriod: 182),
        .init(couponPct: 0.125, fullPeriods: 1, daysToNextCoupon: 1, daysInPeriod: 184),
        .init(couponPct: 0, fullPeriods: 20, daysToNextCoupon: 182, daysInPeriod: 182),   // zero coupon
    ]

    @Test("price inverts to yield", arguments: terms.indices)
    func priceYieldInverts(index: Int) throws {
        let t = Self.terms[index]
        for y in [0.0001, 0.005, 0.0442, 0.0954, 0.15, 0.40] {
            let p = Bond.price(t, yield: y)
            let back = try Bond.yieldToMaturity(t, price: p)
            #expect(abs(back - y) <= 1e-9, "yield(price(\(y))) = \(back)")
        }
    }

    @Test("price falls strictly as yield rises", arguments: terms.indices)
    func priceIsMonotone(index: Int) {
        let t = Self.terms[index]
        var previous = Double.infinity
        for y in [0.0, 0.01, 0.02, 0.05, 0.1, 0.2, 0.5] {
            let p = Bond.price(t, yield: y)
            #expect(p < previous, "price must fall as yield rises")
            previous = p
        }
    }

    /// A bond priced at its own coupon rate, settling on a coupon date, is worth par. The cleanest
    /// sanity check in fixed income, and it catches a whole class of off-by-one errors in n.
    @Test func couponRateYieldsPar() {
        for coupon in [0.5, 2.0, 4.25, 8.75, 15.0] {
            for n in [1, 2, 19, 59, 60] {
                let t = Bond.Terms(couponPct: coupon, fullPeriods: n,
                                   daysToNextCoupon: 182, daysInPeriod: 182)
                let price = Bond.price(t, yield: coupon / 100)
                #expect(abs(price - 100) <= 1e-9,
                        "coupon \(coupon)%, n=\(n): priced \(price), expected par")
            }
        }
    }

    /// Appendix B's own special case, in its own words: "If i = 0, then aₙ = n."
    @Test func zeroYieldIsUndiscountedAndFinite() {
        #expect(Bond.annuityFactor(yield: 0, periods: 12) == 12)
        #expect(Bond.discountFactor(yield: 0, periods: 12) == 1)

        let t = Bond.Terms(couponPct: 5, fullPeriods: 12, daysToNextCoupon: 184, daysInPeriod: 184)
        let price = Bond.price(t, yield: 0)
        // 12 deferred coupons of 2.5 + the stub coupon + 100 redemption, nothing discounted.
        #expect(abs(price - (100 + 2.5 * 13)) <= 1e-9, "got \(price)")
        #expect(price.isFinite)
    }

    @Test func annuityFactorIsItsClosedForm() {
        // Appendix B's own formula, where it is numerically trustworthy.
        for i in [0.001, 0.0442, 0.1047, 1.0] {
            for n in [1, 5, 39, 59] {
                let vn = Bond.discountFactor(yield: i, periods: n)
                let an = Bond.annuityFactor(yield: i, periods: n)
                #expect(abs(an - (1 - vn) / (i / 2)) <= 1e-9 * max(an, 1))
            }
        }

        // At a tiny yield the published form (1 − vⁿ)/(i/2) loses most of its digits to cancellation —
        // 1 − vⁿ is a difference of nearly equal numbers. The Kit computes it through expm1/log1p
        // instead, so here the *series* is the reference: aₙ ≈ n − (i/2)·n(n+1)/2 + O(i²).
        for n in [1, 5, 39, 59] {
            let i = 1e-9
            let an = Bond.annuityFactor(yield: i, periods: n)
            let series = Double(n) - (i / 2) * Double(n * (n + 1)) / 2
            #expect(abs(an - series) <= 1e-12 * Double(n), "aₙ = \(an) vs series \(series)")

            let naive = (1 - Bond.discountFactor(yield: i, periods: n)) / (i / 2)
            #expect(abs(naive - series) > abs(an - series),
                    "the stable form must beat the naive one at i = 1e-9")
        }
    }

    /// Treasury's `n` is one **less** than the number of full semiannual periods remaining when the
    /// issue date is a coupon frequency date — the regulation says so in the definition of n, and it
    /// means a §II.A price with r = s discounts **n + 1** coupons, not n. Pinning it here because it is
    /// the difference between a duration that matches the price curve and one that is half a year out.
    @Test func treasuryNConventionMeansOneMoreCouponThanN() {
        func discountedCashFlowPrice(couponPct: Double, coupons: Int, yield y: Double) -> Double {
            let c2 = couponPct / 2
            var total = 0.0
            for k in 1...coupons { total += c2 * Bond.discountFactor(yield: y, periods: k) }
            return total + 100 * Bond.discountFactor(yield: y, periods: coupons)
        }

        for coupon in [0.0, 2.0, 8.75] {
            for n in [1, 4, 20, 59] {
                for y in [0.02, 0.0442, 0.09] {
                    let t = Bond.Terms(couponPct: coupon, fullPeriods: n,
                                       daysToNextCoupon: 182, daysInPeriod: 182)
                    let treasury = Bond.price(t, yield: y)
                    let dcf = discountedCashFlowPrice(couponPct: coupon, coupons: n + 1, yield: y)
                    #expect(abs(treasury - dcf) <= 1e-9 * max(dcf, 1),
                            "coupon \(coupon), n=\(n), y=\(y): \(treasury) vs \(dcf)")
                }
            }
        }
    }

    /// Modified duration *is* −(1/P)·dP/dy. Checked against a central difference of the same cash-flow
    /// model the duration functions use — n coupons with redemption at n, i.e. settlement on a coupon
    /// date. This is the only honest oracle for a definition with no published Treasury example, and
    /// differentiating the *matching* model is the point: differentiating a §II.A price instead compares
    /// an n-coupon duration against an (n+1)-coupon price curve and is out by exactly half a year.
    @Test func modifiedDurationMatchesTheNumericalDerivative() {
        func price(couponPct: Double, periods n: Int, yield y: Double) -> Double {
            let c2 = couponPct / 2
            var total = 0.0
            for k in 1...n { total += c2 * Bond.discountFactor(yield: y, periods: k) }
            return total + 100 * Bond.discountFactor(yield: y, periods: n)
        }

        for coupon in [0.0, 2.0, 8.75] {
            for n in [4, 20, 60] {
                for y in [0.02, 0.0442, 0.09] {
                    let h = 1e-6
                    let up = price(couponPct: coupon, periods: n, yield: y + h)
                    let down = price(couponPct: coupon, periods: n, yield: y - h)
                    let p = price(couponPct: coupon, periods: n, yield: y)
                    // d/dy in *years*: the model is semiannual, so the derivative of the discount
                    // factor is with respect to the nominal annual yield already.
                    let numerical = -(up - down) / (2 * h) / p

                    let analytic = Bond.modifiedDuration(couponPct: coupon, periods: n, yield: y)
                    #expect(abs(numerical - analytic) <= 1e-4 * max(analytic, 1),
                            "coupon \(coupon), n=\(n), y=\(y): numerical \(numerical) vs \(analytic)")
                }
            }
        }
    }

    /// The `Terms`-based duration must describe the price curve of those same `Terms`. This is the
    /// consistency the `periods:` form cannot give you, because Appendix B's n is one less than the
    /// number of coupons remaining — pass the same n to both and the duration is half a year short.
    @Test func termsBasedDurationMatchesItsOwnPriceCurve() {
        for coupon in [0.0, 4.25, 8.75] {
            for n in [3, 19, 59] {
                for y in [0.02, 0.05, 0.0884] {
                    let terms = Bond.Terms(couponPct: coupon, fullPeriods: n,
                                           daysToNextCoupon: 182, daysInPeriod: 182)
                    let h = 1e-6
                    let p = Bond.price(terms, yield: y)
                    let numerical = -(Bond.price(terms, yield: y + h)
                                      - Bond.price(terms, yield: y - h)) / (2 * h) / p

                    let fromTerms = Bond.modifiedDuration(terms, yield: y)
                    #expect(abs(numerical - fromTerms) <= 1e-4 * max(fromTerms, 1),
                            "coupon \(coupon), n=\(n), y=\(y): curve \(numerical) vs \(fromTerms)")

                    // And the trap this API exists to close: the periods: form measures a shorter
                    // bond, so it does NOT describe this security's price curve. The gap in years is
                    // large for a short bond and small for a long one, so the assertion is about the
                    // curve it fails to match, not about a fixed number of years.
                    let fromPeriods = Bond.modifiedDuration(couponPct: coupon, periods: n, yield: y)
                    #expect(fromTerms > fromPeriods, "one more coupon means a longer duration")
                    #expect(abs(numerical - fromPeriods) > 1e-4 * max(fromPeriods, 1),
                            "the periods: form should NOT match this curve: \(fromPeriods)")
                }
            }
        }
    }

    @Test func durationAndConvexityBehaveAsTheyMust() {
        // A zero-coupon bond's Macaulay duration is exactly its maturity.
        for n in [2, 10, 40] {
            let duration = Bond.macaulayDuration(couponPct: 0, periods: n, yield: 0.05)
            #expect(abs(duration - Double(n) / 2) <= 1e-12, "zero-coupon duration must equal maturity")
        }
        // A coupon bond's duration is shorter than its maturity, and falls as the coupon rises.
        var previous = Double.infinity
        for coupon in [0.0, 2.0, 5.0, 10.0] {
            let duration = Bond.macaulayDuration(couponPct: coupon, periods: 60, yield: 0.05)
            #expect(duration < 30.0)
            #expect(duration < previous)
            previous = duration
        }
        // Macaulay ≥ modified, and convexity is positive.
        let macaulay = Bond.macaulayDuration(couponPct: 4.25, periods: 20, yield: 0.05)
        let modified = Bond.modifiedDuration(couponPct: 4.25, periods: 20, yield: 0.05)
        #expect(macaulay > modified)
        #expect(abs(macaulay / (1 + 0.05 / 2) - modified) <= 1e-12)
        #expect(Bond.convexity(couponPct: 4.25, periods: 20, yield: 0.05) > 0)
    }

    /// The bill investment rate switches branch at exactly half a year, and the two branches must agree
    /// there — a discontinuity would be a visible pricing jump for a 183-day bill.
    @Test func billBranchesMeetAtHalfAYear() {
        let halfYear = 365 / 2      // 182 days: the last day of the simple branch
        let priceAt = 98.0
        let simple = Bond.billInvestmentRate(price: priceAt, daysToMaturity: halfYear)
        let justOver = Bond.billInvestmentRate(price: priceAt, daysToMaturity: halfYear + 1)
        #expect(abs(simple - justOver) < 5e-4,
                "the branches must nearly agree at the boundary: \(simple) vs \(justOver)")
    }

    @Test func billRatesRiseAsPriceFalls() {
        var previousDiscount = -1.0
        var previousInvestment = -1.0
        for price in [99.9, 99.0, 97.5, 95.0, 90.0] {
            let d = Bond.billDiscountRate(price: price, daysToMaturity: 91)
            let i = Bond.billInvestmentRate(price: price, daysToMaturity: 91)
            #expect(d > previousDiscount)
            #expect(i > previousInvestment)
            // The investment rate always exceeds the discount rate: it is measured on the price paid,
            // not on par.
            #expect(i > d)
            previousDiscount = d
            previousInvestment = i
        }
    }

    @Test func yieldSolveRefusesAnUnreachablePrice() {
        let t = Bond.Terms(couponPct: 5, fullPeriods: 20, daysToNextCoupon: 182, daysInPeriod: 182)
        // A negative price is unreachable at any yield in the search range. (10,000 is *not*
        // unreachable: at a yield near −99% the discount factors explode, and a solver that refused it
        // would be wrong about its own domain.)
        #expect(throws: Bond.YieldError.priceOutOfRange) {
            _ = try Bond.yieldToMaturity(t, price: -5)
        }
        #expect(throws: Never.self) { _ = try Bond.yieldToMaturity(t, price: 10_000) }
    }

    @Test func currentYieldIsCouponOverPrice() {
        #expect(abs(Bond.currentYield(couponPct: 4.25, price: 98.75) - 4.25 / 98.75) <= 1e-15)
        #expect(Bond.currentYield(couponPct: 4.25, price: 100) == 0.0425)
    }
}

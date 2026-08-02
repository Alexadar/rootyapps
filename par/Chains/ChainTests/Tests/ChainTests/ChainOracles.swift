import Foundation

/// Published end-to-end values for Kit-to-Kit chains.
///
/// These are the same authorities the individual Kits cite, but read *across* a boundary: Appendix B
/// prints the settlement and maturity dates of every bond example as well as its r and s, so feeding the
/// dates into DayCountKit and the day counts into BondKit must reproduce the published price. A Kit that
/// is right on its own can still be wrong at the seam, and only these tests can see that.
///
/// Policy: ../../../../calculators/VALIDATION.md · ledger: par/scratch/SOURCES.md
struct ChainOracle {
    let chainID: String
    let source: String
    let precision: String
    let values: [String: Double]
    let tolerances: [String: Double]

    func matches(_ key: String, _ actual: Double) -> Bool {
        guard let v = values[key], let t = tolerances[key] else { return false }
        return abs(actual - v) <= t
    }

    func value(_ key: String) -> Double {
        guard let v = values[key] else { fatalError("chain oracle '\(chainID)' has no value '\(key)'") }
        return v
    }
}

/// One Appendix B bond example, stated the way the regulation states it: in **dates**, with the day
/// counts it derives from them. The chain test computes r and s from the dates and checks both the
/// intermediate day counts and the final price.
struct TreasuryDatedExample {
    let id: String
    /// Settlement date — the issue or reopening date in Appendix B's examples.
    let settlement: (Int, Int, Int)
    /// The interest payment date the security's r counts toward.
    let nextCoupon: (Int, Int, Int)
    /// The start of the semiannual period that payment ends — what s counts from.
    let periodStart: (Int, Int, Int)
    let couponPct: Double
    let yield: Double
    let fullPeriods: Int
    /// Published r and s, so the day-count step is checked before the price step.
    let publishedR: Int
    let publishedS: Int
    let publishedPrice: Double
    /// §II.E only: the fractional portion of a long first payment period, and its own semiannual period.
    let fractionalPortion: ((Int, Int, Int), (Int, Int, Int))?
    let publishedRPrime: Int
    let publishedSDoublePrime: Int
    let publishedAccrued: Double
}

enum ChainOracles {
    static let appendixB = """
        31 CFR part 356, Appendix B ("Formulas and Examples"), section II — US Treasury Uniform \
        Offering Circular, 7-1-24 edition, pp. 410-411; \
        https://www.govinfo.gov/content/pkg/CFR-2024-title31-vol2/pdf/CFR-2024-title31-vol2-part356-appB.pdf \
        (US government work, public domain); retrieved 2026-07-27. Each example states its dates in full \
        as well as the r and s derived from them, which is what makes it an end-to-end chain oracle.
        """

    static let regZAppJ = """
        12 CFR part 1026 (Regulation Z), Appendix J, example (c)(1)(i) — CFPB, 1-1-24 edition, p. 435; \
        https://www.govinfo.gov/content/pkg/CFR-2024-title12-vol9/pdf/CFR-2024-title12-vol9-part1026-appJ.pdf \
        (US government work, public domain); retrieved 2026-07-27.
        """

    static let regDDAppA = """
        12 CFR part 1030 (Regulation DD), Appendix A, part I — CFPB; \
        https://www.law.cornell.edu/cfr/text/12/appendix-A_to_part_1030 (US government work, public \
        domain); retrieved 2026-07-27.
        """

    /// The five Appendix B section II examples, in dates.
    ///
    /// §II.A — 8¾% 30-year bond issued 1990-05-15, due 2020-05-15, interest 15 May and 15 November.
    /// §II.B — 8½% 2-year note issued 1990-04-02, due 1992-03-31, interest 30 September and 31 March.
    /// §II.C — 8½% 5-year 2-month note issued 1990-03-01, due 1995-05-15, first payment 1990-11-15.
    /// §II.D — 9½% 10-year note accruing from 1985-11-15, issued 1985-11-29, due 1995-11-15.
    /// §II.E — 10¾% bond issued 1985-07-02, reopened 1985-11-04, first payment 1986-02-15.
    static let treasuryDatedExamples: [TreasuryDatedExample] = [
        .init(id: "II-A", settlement: (1990, 5, 15), nextCoupon: (1990, 11, 15),
              periodStart: (1990, 5, 15), couponPct: 8.75, yield: 0.0884, fullPeriods: 59,
              publishedR: 184, publishedS: 184, publishedPrice: 99.057893,
              fractionalPortion: nil, publishedRPrime: 0, publishedSDoublePrime: 1,
              publishedAccrued: 0),
        .init(id: "II-B", settlement: (1990, 4, 2), nextCoupon: (1990, 9, 30),
              periodStart: (1990, 3, 31), couponPct: 8.50, yield: 0.0859, fullPeriods: 3,
              publishedR: 181, publishedS: 183, publishedPrice: 99.838183,
              fractionalPortion: nil, publishedRPrime: 0, publishedSDoublePrime: 1,
              publishedAccrued: 0),
        .init(id: "II-C", settlement: (1990, 3, 1), nextCoupon: (1990, 5, 15),
              periodStart: (1989, 11, 15), couponPct: 8.50, yield: 0.0853, fullPeriods: 10,
              publishedR: 75, publishedS: 181, publishedPrice: 99.805118,
              fractionalPortion: nil, publishedRPrime: 0, publishedSDoublePrime: 1,
              publishedAccrued: 0),
        .init(id: "II-D", settlement: (1985, 11, 29), nextCoupon: (1986, 5, 15),
              periodStart: (1985, 11, 15), couponPct: 9.50, yield: 0.0954, fullPeriods: 19,
              publishedR: 167, publishedS: 181, publishedPrice: 99.730918,
              fractionalPortion: nil, publishedRPrime: 0, publishedSDoublePrime: 1,
              publishedAccrued: 0.367403),
        .init(id: "II-E", settlement: (1985, 11, 4), nextCoupon: (1986, 2, 15),
              periodStart: (1985, 8, 15), couponPct: 10.75, yield: 0.1047, fullPeriods: 39,
              publishedR: 103, publishedS: 184, publishedPrice: 102.214586,
              fractionalPortion: ((1985, 7, 2), (1985, 2, 15)), publishedRPrime: 44,
              publishedSDoublePrime: 181, publishedAccrued: 3.672798),
    ]

    static let all: [ChainOracle] = [
        ChainOracle(
            chainID: "dates-to-bond-price",
            source: appendixB,
            precision: "±5e-7 on prices (Appendix B rounds P to six places); ±5e-6 on §II.E, whose "
                + "published steps round P + A before subtracting A; day counts exact",
            values: ["exampleCount": 5],
            tolerances: ["exampleCount": 0.5]
        ),
        ChainOracle(
            chainID: "bond-price-as-npv",
            source: appendixB,
            precision: "±5e-7 — the same published price, reached through CashFlowKit's discounting "
                + "instead of BondKit's closed form",
            values: ["price": 99.057893, "periodicYield": 0.0442, "coupons": 60],
            tolerances: ["price": 5e-7, "periodicYield": 1e-15, "coupons": 0.5]
        ),
        ChainOracle(
            chainID: "bond-price-to-flow-vector",
            source: appendixB,
            precision: "±5e-7 — the flow vector BondKit's price implies must re-price to it",
            values: ["price": 99.057893],
            tolerances: ["price": 5e-7]
        ),
        ChainOracle(
            chainID: "accrual-fraction-round-trip",
            source: appendixB,
            precision: "±5e-7 — §II.D's published accrued interest, reached from its dates",
            values: ["accruedInterest": 0.367403, "elapsedDays": 14, "periodDays": 181],
            tolerances: ["accruedInterest": 5e-7, "elapsedDays": 0.5, "periodDays": 0.5]
        ),
        ChainOracle(
            chainID: "tvm-payment-to-schedule",
            source: regZAppJ,
            precision: "±0.012 on the payment — the measured sensitivity of a $5,000 24-month loan to "
                + "the published APR's own ±0.005 pp rounding",
            values: ["principal": 5000, "annualRatePct": 9.69, "periods": 24, "payment": 230],
            tolerances: ["principal": 0, "annualRatePct": 0, "periods": 0, "payment": 0.012]
        ),
        ChainOracle(
            chainID: "schedule-to-apr",
            source: regZAppJ,
            precision: "±0.005 pp — Appendix J publishes the rate to two decimals",
            values: ["aprPct": 9.69],
            tolerances: ["aprPct": 0.005]
        ),
        ChainOracle(
            chainID: "apr-to-schedule",
            source: regZAppJ,
            precision: "±0.012 — same measured payment sensitivity as above",
            values: ["payment": 230],
            tolerances: ["payment": 0.012]
        ),
        ChainOracle(
            chainID: "irr-to-apr",
            source: regZAppJ,
            precision: "±0.005 pp on the APR; the two Kits must agree with each other to 1e-12",
            values: ["aprPct": 9.69, "unitPeriodsPerYear": 12],
            tolerances: ["aprPct": 0.005, "unitPeriodsPerYear": 0]
        ),
        ChainOracle(
            chainID: "apr-to-irr",
            source: regZAppJ,
            precision: "±0.005 pp — the published APR, reached from RateKit's rate through CashFlowKit",
            values: ["aprPct": 9.69],
            tolerances: ["aprPct": 0.005]
        ),
        ChainOracle(
            chainID: "apy-to-tvm-rate",
            source: regDDAppA,
            precision: "±0.005 pp — the published APY to two decimals",
            values: ["interest": 61.68, "principal": 1000, "daysInTerm": 365, "apyPct": 6.17],
            tolerances: ["interest": 0, "principal": 0, "daysInTerm": 0, "apyPct": 0.005]
        ),
    ]

    static func require(_ chainID: String) -> ChainOracle {
        guard let o = all.first(where: { $0.chainID == chainID }) else {
            fatalError("no chain oracle for '\(chainID)'")
        }
        return o
    }
}

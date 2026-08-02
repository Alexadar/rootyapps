import Foundation

/// A ground-truth entry transcribed from an EXTERNAL published authority.
/// The implementer must NOT invent these numbers — every entry cites its `source`.
/// Policy: ../../../../../calculators/VALIDATION.md · ledger: par/scratch/SOURCES.md
struct Oracle {
    let id: String
    let source: String
    let inputs: [String: Double]
    let precision: String
    let values: [String: Double]
    let tolerances: [String: Double]

    func matches(_ key: String, _ actual: Double) -> Bool {
        guard let v = values[key], let t = tolerances[key] else { return false }
        return abs(actual - v) <= t
    }

    func input(_ key: String) -> Double {
        guard let v = inputs[key] else { fatalError("oracle '\(id)' has no input '\(key)'") }
        return v
    }

    func value(_ key: String) -> Double {
        guard let v = values[key] else { fatalError("oracle '\(id)' has no value '\(key)'") }
        return v
    }
}

/// One Regulation Z Appendix J example, in the shape Appendix J itself describes it: a single advance
/// and one or more series of equal payments, each series starting `t` full unit-periods plus a leading
/// fraction `f` after the term begins.
///
/// The published inputs stay structured rather than flattened into a dictionary, because the *shape* of
/// the schedule is part of what is published — collapsing "24 payments of $230" into 24 numbers would
/// lose the thing being transcribed.
struct AppendixJCase {
    struct Series {
        let amount: Double
        let count: Int
        let fullPeriods: Int
        let fraction: Double
    }

    let id: String
    let label: String
    let advance: Double
    let series: [Series]
    let unitPeriodsPerYear: Double
    /// The published annual percentage rate, to the two decimals Appendix J states.
    let publishedAPR: Double

    var totalPayments: Int { series.reduce(0) { $0 + $1.count } }
    var hasFractionalFirstPeriod: Bool { series.contains { $0.fraction != 0 } }
}

enum Oracles {
    static let regZAppJ = """
        12 CFR part 1026 (Regulation Z), Appendix J, "Annual Percentage Rate Computations for \
        Closed-End Credit Transactions", examples (c)(1)-(c)(6) — CFPB, 1-1-24 edition, pp. 435-440; \
        https://www.govinfo.gov/content/pkg/CFR-2024-title12-vol9/pdf/CFR-2024-title12-vol9-part1026-appJ.pdf \
        (US government work, public domain); retrieved 2026-07-27. The examples and equations are page \
        images in both the print CFR and eCFR; these were transcribed from a 150-dpi render and each \
        one is reproduced by par/scratch/regz_appJ.py. Appendix J states its rates were obtained with \
        a ten-digit calculator and are correct when rounded to two decimals.
        """

    static let regDDAppA = """
        12 CFR part 1030 (Regulation DD), Appendix A, "Annual Percentage Yield Calculation", parts I \
        and II — CFPB; https://www.law.cornell.edu/cfr/text/12/appendix-A_to_part_1030 \
        (US government work, public domain); retrieved 2026-07-27.
        """

    /// All seventeen published Appendix J examples: level, long and short first periods, odd first and
    /// final payments, four single-payment forms, and two genuinely irregular multi-series loans.
    static let appendixJCases: [AppendixJCase] = [
        // (c)(1) single advance, otherwise regular
        .init(id: "regz-appJ-c1-i", label: "monthly, regular first period", advance: 5000,
              series: [.init(amount: 230, count: 24, fullPeriods: 1, fraction: 0)],
              unitPeriodsPerYear: 12, publishedAPR: 9.69),
        .init(id: "regz-appJ-c1-ii", label: "monthly, long first period", advance: 6000,
              series: [.init(amount: 200, count: 36, fullPeriods: 1, fraction: 19.0 / 30.0)],
              unitPeriodsPerYear: 12, publishedAPR: 11.82),
        .init(id: "regz-appJ-c1-iii", label: "semimonthly, short first period", advance: 5000,
              series: [.init(amount: 219.17, count: 24, fullPeriods: 0, fraction: 6.0 / 15.0)],
              unitPeriodsPerYear: 24, publishedAPR: 10.34),
        .init(id: "regz-appJ-c1-iv", label: "quarterly, long first period", advance: 10000,
              series: [.init(amount: 385, count: 40, fullPeriods: 1, fraction: 39.0 / 90.0)],
              unitPeriodsPerYear: 4, publishedAPR: 8.97),
        .init(id: "regz-appJ-c1-v", label: "weekly, long first period", advance: 500,
              series: [.init(amount: 17.60, count: 30, fullPeriods: 4, fraction: 4.0 / 7.0)],
              unitPeriodsPerYear: 52, publishedAPR: 14.96),

        // (c)(2) odd first payment
        .init(id: "regz-appJ-c2-i", label: "monthly, irregular first payment", advance: 5000,
              series: [.init(amount: 250, count: 1, fullPeriods: 1, fraction: 0),
                       .init(amount: 230, count: 23, fullPeriods: 2, fraction: 0)],
              unitPeriodsPerYear: 12, publishedAPR: 10.08),
        .init(id: "regz-appJ-c2-ii", label: "every 4 weeks, long first period, irregular first payment",
              advance: 400,
              series: [.init(amount: 39.50, count: 1, fullPeriods: 1, fraction: 5.0 / 28.0),
                       .init(amount: 38.31, count: 11, fullPeriods: 2, fraction: 5.0 / 28.0)],
              unitPeriodsPerYear: 13, publishedAPR: 28.50),

        // (c)(3) odd final payment
        .init(id: "regz-appJ-c3-i", label: "monthly, irregular final payment", advance: 5000,
              series: [.init(amount: 230, count: 23, fullPeriods: 1, fraction: 0),
                       .init(amount: 280, count: 1, fullPeriods: 24, fraction: 0)],
              unitPeriodsPerYear: 12, publishedAPR: 10.50),
        .init(id: "regz-appJ-c3-ii", label: "every 2 weeks, short first period, irregular final",
              advance: 200,
              series: [.init(amount: 9.50, count: 19, fullPeriods: 0, fraction: 8.0 / 14.0),
                       .init(amount: 30, count: 1, fullPeriods: 19, fraction: 8.0 / 14.0)],
              unitPeriodsPerYear: 26, publishedAPR: 12.22),

        // (c)(4) odd first and final payment
        .init(id: "regz-appJ-c4-i", label: "monthly, irregular first and final", advance: 5000,
              series: [.init(amount: 250, count: 1, fullPeriods: 1, fraction: 0),
                       .init(amount: 230, count: 22, fullPeriods: 2, fraction: 0),
                       .init(amount: 280, count: 1, fullPeriods: 24, fraction: 0)],
              unitPeriodsPerYear: 12, publishedAPR: 10.90),
        .init(id: "regz-appJ-c4-ii", label: "every 2 months, short first period, irregular first and final",
              advance: 8000,
              series: [.init(amount: 449.36, count: 1, fullPeriods: 0, fraction: 52.0 / 60.0),
                       .init(amount: 465, count: 18, fullPeriods: 1, fraction: 52.0 / 60.0),
                       .init(amount: 200, count: 1, fullPeriods: 19, fraction: 52.0 / 60.0)],
              unitPeriodsPerYear: 6, publishedAPR: 7.30),

        // (c)(5) single advance, single payment — the four closed forms
        .init(id: "regz-appJ-c5-i", label: "term 255 days", advance: 1000,
              series: [.init(amount: 1080, count: 1, fullPeriods: 1, fraction: 0)],
              unitPeriodsPerYear: 365.0 / 255.0, publishedAPR: 11.45),
        .init(id: "regz-appJ-c5-ii", label: "term 6 months", advance: 1000,
              series: [.init(amount: 1044, count: 1, fullPeriods: 1, fraction: 0)],
              unitPeriodsPerYear: 2, publishedAPR: 8.80),
        .init(id: "regz-appJ-c5-iii", label: "term 18 months, fraction in months", advance: 1000,
              series: [.init(amount: 1135.19, count: 1, fullPeriods: 1, fraction: 6.0 / 12.0)],
              unitPeriodsPerYear: 1, publishedAPR: 8.76),
        .init(id: "regz-appJ-c5-iv", label: "term exactly 2 years", advance: 1000,
              series: [.init(amount: 1240, count: 1, fullPeriods: 2, fraction: 0)],
              unitPeriodsPerYear: 1, publishedAPR: 11.36),

        // (c)(6) complex single advance — the two irregular multi-series loans
        .init(id: "regz-appJ-c6-i", label: "skipped-payment loan, payments every 4 weeks", advance: 2135,
              series: [.init(amount: 100, count: 9, fullPeriods: 0, fraction: 26.0 / 28.0),
                       .init(amount: 100, count: 6, fullPeriods: 10, fraction: 12.0 / 28.0),
                       .init(amount: 100, count: 6, fullPeriods: 16, fraction: 26.0 / 28.0),
                       .init(amount: 100, count: 3, fullPeriods: 23, fraction: 12.0 / 28.0)],
              unitPeriodsPerYear: 13, publishedAPR: 12.00),
        .init(id: "regz-appJ-c6-ii", label: "skipped payments plus single payments", advance: 7350,
              series: [.init(amount: 1000, count: 3, fullPeriods: 6, fraction: 12.0 / 30.0),
                       .init(amount: 2000, count: 1, fullPeriods: 12, fraction: 12.0 / 30.0),
                       .init(amount: 750, count: 3, fullPeriods: 18, fraction: 12.0 / 30.0),
                       .init(amount: 1000, count: 1, fullPeriods: 22, fraction: 29.0 / 30.0)],
              unitPeriodsPerYear: 12, publishedAPR: 10.22),
    ]

    /// The Appendix J cases as corpus entries, so the integrity guard covers them like anything else.
    /// The tolerance is the published rounding itself: par/scratch/regz_appJ.py measures the worst
    /// deviation across all seventeen at 0.00488 pp, i.e. inside two decimals with nothing to spare.
    static let appendixJRows: [Oracle] = appendixJCases.map { example in
        Oracle(
            id: example.id,
            source: regZAppJ,
            inputs: [
                "advance": example.advance,
                "paymentCount": Double(example.totalPayments),
                "unitPeriodsPerYear": example.unitPeriodsPerYear,
            ],
            precision: "±0.005 pp — Appendix J publishes the rate to two decimals; measured worst "
                + "deviation across all 17 examples is 0.00488 pp (par/scratch/regz_appJ.py)",
            values: ["aprPct": example.publishedAPR],
            tolerances: ["aprPct": 0.005]
        )
    }

    /// Regulation DD Appendix A's own worked yields.
    static let regDDRows: [Oracle] = [
        Oracle(
            id: "regdd-appA-now-account",
            source: regDDAppA,
            inputs: ["interest": 61.68, "principal": 1000, "daysInTerm": 365],
            precision: "±0.005 pp — published to two decimals",
            values: ["apyPct": 6.17],
            tolerances: ["apyPct": 0.005]
        ),
        Oracle(
            id: "regdd-appA-six-month-cd",
            source: regDDAppA,
            inputs: ["interest": 30.37, "principal": 1000, "daysInTerm": 182],
            precision: "±0.005 pp — published to two decimals; the 365/182 exponent is the whole point",
            values: ["apyPct": 6.18],
            tolerances: ["apyPct": 0.005]
        ),
        Oracle(
            id: "regdd-appA-apy-earned-statement-period",
            source: regDDAppA,
            inputs: ["interestEarned": 5.25, "averageDailyBalance": 1000, "daysInPeriod": 30],
            precision: "±0.005 pp — published to two decimals (Appendix A part II)",
            values: ["apyEarnedPct": 6.58],
            tolerances: ["apyEarnedPct": 0.005]
        ),
    ]

    /// The corpus. Expected numbers live ONLY here, each tied to an external source.
    static let all: [Oracle] = appendixJRows + regDDRows

    static func require(_ id: String) -> Oracle {
        guard let o = all.first(where: { $0.id == id }) else {
            fatalError("unknown oracle id '\(id)'")
        }
        return o
    }

    static func requireCase(_ id: String) -> AppendixJCase {
        guard let c = appendixJCases.first(where: { $0.id == id }) else {
            fatalError("unknown Appendix J case '\(id)'")
        }
        return c
    }
}

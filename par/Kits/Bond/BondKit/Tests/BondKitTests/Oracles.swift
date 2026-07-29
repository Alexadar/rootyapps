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

enum Oracles {
    static let appendixB = """
        31 CFR part 356, Appendix B ("Formulas and Examples"), US Treasury Uniform Offering Circular, \
        7-1-24 edition, pp. 409-412 and 419-421; \
        https://www.govinfo.gov/content/pkg/CFR-2024-title31-vol2/pdf/CFR-2024-title31-vol2-part356-appB.pdf \
        (US government work, public domain); retrieved 2026-07-27. Every example below is reproduced by \
        par/scratch/treasury_356.py, which also measures the residuals these tolerances come from.
        """

    /// The corpus. Expected numbers live ONLY here, each tied to an external source.
    ///
    /// Treasury prints its examples to six decimals for prices and nine for accrued interest in money,
    /// so the tolerances are the published rounding — 5e-7 and 5e-9 respectively — except where the
    /// regulation's own worked steps round an intermediate value, which is stated in `precision`.
    static let all: [Oracle] = [

        // ── §II. Yield to price, all five cases ──────────────────────────────────────
        // §II.A — 8¾% 30-year bond issued 1990-05-15, due 2020-05-15, at a 8.84% yield. Settlement is
        // on a coupon date (r = s), so accrued interest is zero and the stub factor is (1 + i/2).
        Oracle(
            id: "treasury-II-A-price",
            source: appendixB,
            inputs: ["couponPct": 8.75, "yield": 0.0884, "n": 59, "r": 184, "s": 184],
            precision: "±5e-7 — Appendix B defines P as 'rounded to six places'",
            values: ["price": 99.057893, "discountFactor": 0.0779403508, "annuityFactor": 20.8610780353],
            tolerances: ["price": 5e-7, "discountFactor": 5e-11, "annuityFactor": 5e-10]
        ),
        // §II.B — 8½% 2-year note issued 1990-04-02, due 1992-03-31, at 8.59%: a SHORT first period.
        Oracle(
            id: "treasury-II-B-price-short-first",
            source: appendixB,
            inputs: ["couponPct": 8.50, "yield": 0.0859, "n": 3, "r": 181, "s": 183],
            precision: "±5e-7 — six published decimals",
            values: ["price": 99.838183],
            tolerances: ["price": 5e-7]
        ),
        // §II.C — 8½% 5-year 2-month note issued 1990-03-01, due 1995-05-15, at 8.53%: a LONG first
        // period, where the stub coupon is itself discounted one period.
        Oracle(
            id: "treasury-II-C-price-long-first",
            source: appendixB,
            inputs: ["couponPct": 8.50, "yield": 0.0853, "n": 10, "r": 75, "s": 181],
            precision: "±5e-7 — six published decimals; v = .9590946147 is printed alongside",
            values: ["price": 99.805118, "onePeriodDiscount": 0.9590946147],
            tolerances: ["price": 5e-7, "onePeriodDiscount": 5e-11]
        ),
        // §II.D — 9½% 10-year note accruing from 1985-11-15, issued 1985-11-29, at 9.54%: a reopening in
        // a regular period, so the buyer pays P + A.
        Oracle(
            id: "treasury-II-D-price-reopening",
            source: appendixB,
            inputs: ["couponPct": 9.50, "yield": 0.0954, "n": 19, "r": 167, "s": 181],
            precision: "±5e-7 on P and A — both printed to six decimals",
            values: ["price": 99.730918, "accruedInterest": 0.367403, "settlementAmount": 100.098321],
            tolerances: ["price": 5e-7, "accruedInterest": 5e-7, "settlementAmount": 5e-6]
        ),
        // §II.E — 10¾% 19-year 9-month bond issued 1985-07-02, reopened 1985-11-04, at 10.47%: a
        // reopening in the regular portion of a long first period, where A spans both portions.
        Oracle(
            id: "treasury-II-E-price-reopening-long",
            source: appendixB,
            inputs: [
                "couponPct": 10.75, "yield": 0.1047, "n": 39, "r": 103, "s": 184,
                "rPrime": 44, "sDoublePrime": 181,
            ],
            precision: "±5e-6 — the published resolution steps round P + A to six decimals before "
                + "subtracting A, so the last published digit of P carries that rounding",
            values: ["price": 102.214586, "accruedInterest": 3.672798, "settlementAmount": 105.887384],
            tolerances: ["price": 5e-6, "accruedInterest": 5e-6, "settlementAmount": 5e-6]
        ),

        // ── §I.D(2). Accrued interest across two half-years of different length ──────
        // 10¾% bond issued 1985-07-02 as a 20-year 1-month bond, reopened 1985-11-04: 44 days of a
        // 181-day half-year, then 81 days of a 184-day one, per $1,000.
        Oracle(
            id: "treasury-I-D-accrued-two-half-years",
            source: appendixB,
            inputs: [
                "couponPct": 10.75, "par": 1000,
                "firstHalfYearDays": 44, "firstHalfYearLength": 181,
                "secondHalfYearDays": 81, "secondHalfYearLength": 184,
            ],
            precision: "±5e-9 with Treasury's own nine-decimal daily rounding; the exact product "
                + "differs at 1.6e-8, which is why the rounding is modelled rather than ignored",
            values: [
                "accruedInterest": 36.727983109,
                "dailyFirstHalf": 0.296961326, "dailySecondHalf": 0.292119565,
                "elevenThousandPar": 404.00778,
            ],
            tolerances: [
                "accruedInterest": 5e-9,
                "dailyFirstHalf": 5e-10, "dailySecondHalf": 5e-10,
                "elevenThousandPar": 5e-5,
            ]
        ),

        // ── §VI. Treasury bills ─────────────────────────────────────────────────────
        // §VI.A — bill issued 1989-11-24, due 1990-02-22, at a 7.610% discount rate.
        Oracle(
            id: "treasury-VI-A-bill-price",
            source: appendixB,
            inputs: ["discountRate": 0.07610, "r": 90],
            precision: "±5e-7 — six published decimals",
            values: ["price": 98.097500],
            tolerances: ["price": 5e-7]
        ),
        // §VI.D.1 — cash-management bill 1990-06-01 → 1990-06-21, price 99.559444, ≤ half a year.
        Oracle(
            id: "treasury-VI-D-1-investment-rate",
            source: appendixB,
            inputs: ["price": 99.559444, "r": 20, "y": 365],
            precision: "±2e-6: the published resolution's step (2) rounds (100−P)/P to six decimals "
                + "before multiplying, so the published .080756 sits 1.25e-6 from the unrounded .08075725",
            values: ["investmentRate": 0.080756],
            tolerances: ["investmentRate": 2e-6]
        ),
        // §VI.D.2 — 52-week bill 1990-06-07 → 1991-06-06, price 92.265000: the quadratic branch.
        Oracle(
            id: "treasury-VI-D-2-investment-rate",
            source: appendixB,
            inputs: ["price": 92.265000, "r": 364, "y": 365],
            precision: "±5e-9 — nine published decimals; a, b and c are printed alongside",
            values: [
                "investmentRate": 0.082373244,
                "a": 0.248630137, "b": 0.997260274, "c": -0.083834607,
            ],
            tolerances: ["investmentRate": 5e-9, "a": 5e-10, "b": 5e-10, "c": 5e-10]
        ),

        // ── §III. Inflation-indexed securities ──────────────────────────────────────
        // 3⅝% 10-year TIPS issued 1998-01-15, reopened 1998-10-15.
        Oracle(
            id: "treasury-III-index-ratio",
            source: appendixB,
            inputs: ["referenceCPI": 163.29032, "referenceCPIAtIssue": 161.55484],
            precision: "exact — the ratio is truncated (not rounded) to five decimals, so the published "
                + "1.01074 is reproducible exactly",
            values: ["indexRatio": 1.01074],
            tolerances: ["indexRatio": 1e-12]
        ),
    ]

    static func require(_ id: String) -> Oracle {
        guard let o = all.first(where: { $0.id == id }) else {
            fatalError("unknown oracle id '\(id)'")
        }
        return o
    }
}

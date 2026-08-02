import Foundation

/// A ground-truth entry transcribed from an EXTERNAL published authority.
/// The implementer must NOT invent these numbers — every entry cites its `source`.
/// Policy: ../../../../../calculators/VALIDATION.md · ledger: par/scratch/SOURCES.md
struct Oracle {
    let id: String
    let source: String            // external authority citation — MUST be non-empty (enforced)
    let inputs: [String: Double]
    let precision: String         // field precision / rationale for the tolerance
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
    static let treasuryAppB = """
        31 CFR part 356, Appendix B ("Formulas and Examples"), section II — US Treasury Uniform \
        Offering Circular, 7-1-24 edition, pp. 410-411; \
        https://www.govinfo.gov/content/pkg/CFR-2024-title31-vol2/pdf/CFR-2024-title31-vol2-part356-appB.pdf \
        (US government work, public domain); retrieved 2026-07-27. Treasury prints both the discount \
        factor vⁿ and the annuity factor aₙ of every worked example to ten decimals.
        """

    static let regZAppJ = """
        12 CFR part 1026 (Regulation Z), Appendix J, "Annual Percentage Rate Computations for \
        Closed-End Credit Transactions", examples (c)(1)-(c)(6) — CFPB, 1-1-24 edition, pp. 435-440; \
        https://www.govinfo.gov/content/pkg/CFR-2024-title12-vol9/pdf/CFR-2024-title12-vol9-part1026-appJ.pdf \
        (US government work, public domain); retrieved 2026-07-27. Appendix J states its rates were \
        obtained with a ten-digit calculator and are correct when rounded to two decimals.
        """

    static let regDDAppA = """
        12 CFR part 1030 (Regulation DD), Appendix A, "Annual Percentage Yield Calculation" — CFPB; \
        https://www.law.cornell.edu/cfr/text/12/appendix-A_to_part_1030 (US government work, public \
        domain); retrieved 2026-07-27.
        """

    /// The corpus. Expected numbers live ONLY here, each tied to an external source.
    static let all: [Oracle] = [

        // ── Published annuity and discount factors (31 CFR 356 App B §II) ─────────────
        // Each Treasury example prints vⁿ and aₙ for a semiannual rate i/2 over n periods, which is
        // exactly TVM's discountFactor and annuityFactor at that periodic rate.
        Oracle(
            id: "treasury-II-A-factors",
            source: treasuryAppB,
            inputs: ["periodicRate": 0.0442, "periods": 59],
            precision: "±5e-11: Treasury prints both factors to ten decimals",
            values: ["discountFactor": 0.0779403508, "annuityFactor": 20.8610780353],
            tolerances: ["discountFactor": 5e-11, "annuityFactor": 5e-10]
        ),
        Oracle(
            id: "treasury-II-C-factors",
            source: treasuryAppB,
            inputs: ["periodicRate": 0.04265, "periods": 10],
            precision: "±5e-11 on vⁿ and v; aₙ printed to ten decimals",
            values: [
                "discountFactor": 0.6585890783,
                "annuityFactor": 8.0049454082,
                "onePeriodDiscount": 0.9590946147,
            ],
            tolerances: ["discountFactor": 5e-11, "annuityFactor": 5e-10, "onePeriodDiscount": 5e-11]
        ),
        Oracle(
            id: "treasury-II-D-factors",
            source: treasuryAppB,
            inputs: ["periodicRate": 0.0477, "periods": 19],
            precision: "±5e-11: ten published decimals",
            values: ["discountFactor": 0.4125703996, "annuityFactor": 12.3150859630],
            tolerances: ["discountFactor": 5e-11, "annuityFactor": 5e-10]
        ),
        Oracle(
            id: "treasury-II-E-factors",
            source: treasuryAppB,
            inputs: ["periodicRate": 0.05235, "periods": 39],
            precision: "±5e-11: ten published decimals",
            values: ["discountFactor": 0.1366947986, "annuityFactor": 16.4910258142],
            tolerances: ["discountFactor": 5e-11, "annuityFactor": 5e-10]
        ),

        // ── Published rate solves (Reg Z Appendix J) ──────────────────────────────────
        // (c)(1)(i) is a plain ordinary annuity — t = 1, f = 0 — so its published APR is a published
        // answer to "solve for i", the one register with no closed form.
        Oracle(
            id: "regz-appJ-c1-i-rate",
            source: regZAppJ,
            inputs: ["presentValue": 5000, "payment": -230, "periods": 24, "paymentsPerYear": 12],
            precision: "±0.005 pp — the published APR is stated to two decimals",
            values: ["annualRatePct": 9.69],
            tolerances: ["annualRatePct": 0.005]
        ),
        // (c)(5)(ii): a single advance repaid by a single payment six months later, w = 2.
        Oracle(
            id: "regz-appJ-c5-ii-rate",
            source: regZAppJ,
            inputs: ["presentValue": 1000, "futureValue": -1044, "periods": 1, "paymentsPerYear": 2],
            precision: "±0.005 pp — published to two decimals (Form 1 or 4)",
            values: ["annualRatePct": 8.80],
            tolerances: ["annualRatePct": 0.005]
        ),
        // (c)(5)(iv): single advance, single payment, term exactly two years, w = 1.
        Oracle(
            id: "regz-appJ-c5-iv-rate",
            source: regZAppJ,
            inputs: ["presentValue": 1000, "futureValue": -1240, "periods": 2, "paymentsPerYear": 1],
            precision: "±0.005 pp — published to two decimals (Form 3 or 4)",
            values: ["annualRatePct": 11.36],
            tolerances: ["annualRatePct": 0.005]
        ),

        // ── Published compounding (Reg DD Appendix A) ─────────────────────────────────
        // $1,000 earning $61.68 over a 365-day term is a 6.17% annual percentage yield; as a TVM
        // problem that is PV = −1000, FV = 1061.68, n = 1, one period per year.
        Oracle(
            id: "regdd-appA-now-account",
            source: regDDAppA,
            inputs: ["presentValue": -1000, "futureValue": 1061.68, "periods": 1, "paymentsPerYear": 1],
            precision: "±0.005 pp — the published APY is stated to two decimals",
            values: ["annualRatePct": 6.17],
            tolerances: ["annualRatePct": 0.005]
        ),
    ]

    static func require(_ id: String) -> Oracle {
        guard let o = all.first(where: { $0.id == id }) else {
            fatalError("unknown oracle id '\(id)'")
        }
        return o
    }
}

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
    static let regZAppJ = """
        12 CFR part 1026 (Regulation Z), Appendix J, examples (c)(1)(i) and (c)(1)(iv) — CFPB, \
        1-1-24 edition, p. 435; \
        https://www.govinfo.gov/content/pkg/CFR-2024-title12-vol9/pdf/CFR-2024-title12-vol9-part1026-appJ.pdf \
        (US government work, public domain); retrieved 2026-07-27.
        """

    /// The corpus. Expected numbers live ONLY here, each tied to an external source.
    ///
    /// Appendix J publishes (amount advanced, payment, number of payments) → APR. Read the other way
    /// round it is a published amortization fact: at that APR, this principal and this term produce
    /// that level payment. The tolerance is derived, not chosen — the APR is published to two
    /// decimals, and ±0.005 pp of APR moves the payment by ±0.0115 on the (c)(1)(i) loan and
    /// ±0.0106 on (c)(1)(iv) (measured in par/scratch/regz_appJ.py's model).
    static let all: [Oracle] = [
        Oracle(
            id: "regz-appJ-c1-i-payment",
            source: regZAppJ,
            inputs: ["principal": 5000, "annualRatePct": 9.69, "periods": 24, "periodsPerYear": 12],
            precision: "±0.012 — measured payment sensitivity to the published APR's own ±0.005 pp rounding",
            values: ["payment": 230],
            tolerances: ["payment": 0.012]
        ),
    ]

    // Deliberately NOT in the corpus: Appendix J (c)(1)(ii)-(v). Each has an odd first period
    // (f = 19/30, 6/15, 39/90, 4/7) that a level annuity cannot express — (c)(1)(iv) computes to
    // 381.28 against a published 385, a 3.7 gap that is the model's, not the arithmetic's. Widening a
    // tolerance until it passed would manufacture a green test that proves nothing. Those examples are
    // oracles for RateKit, which models the fractional unit-period the way Appendix J (b)(8) defines
    // it, and they pass there to the published two decimals.

    static func require(_ id: String) -> Oracle {
        guard let o = all.first(where: { $0.id == id }) else {
            fatalError("unknown oracle id '\(id)'")
        }
        return o
    }
}

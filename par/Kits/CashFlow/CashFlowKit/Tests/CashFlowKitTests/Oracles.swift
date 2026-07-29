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
        12 CFR part 1026 (Regulation Z), Appendix J, examples (c)(1)(i), (c)(2)(i), (c)(3)(i), \
        (c)(4)(i) and (c)(5)(iv) — CFPB, 1-1-24 edition, pp. 435-439; \
        https://www.govinfo.gov/content/pkg/CFR-2024-title12-vol9/pdf/CFR-2024-title12-vol9-part1026-appJ.pdf \
        (US government work, public domain); retrieved 2026-07-27. Appendix J (b)(1): the annual \
        percentage rate is the unit-period rate multiplied by the number of unit-periods in a year — \
        so for an example with no odd first period (f = 0) the published APR is a published IRR.
        """

    static let nistHB135 = """
        NIST Handbook 135e2025, "Life Cycle Costing Manual for the Federal Energy Management \
        Program", section 7.1.1 Example 7-1 ("Decision to Accept or Reject Storm Windows"), pp. 94-95; \
        https://nvlpubs.nist.gov/nistpubs/hb/2025/NIST.HB.135e2025.pdf (US government work, public \
        domain); retrieved 2026-07-27.
        """

    /// The corpus. Expected numbers live ONLY here, each tied to an external source.
    ///
    /// Only Appendix J examples with **f = 0** are used: those are the ones whose flows all land on
    /// integer period boundaries, which is the model this Kit implements. The examples with an odd
    /// first period are oracles for RateKit instead, which implements Appendix J (b)(8) in full.
    /// Flows are encoded as `flow_<k>` plus a `count_<k>` for runs of equal payments.
    static let all: [Oracle] = [
        // (c)(1)(i): $5,000 advanced, 24 monthly payments of $230, first payment one full month later.
        Oracle(
            id: "regz-appJ-c1-i-irr",
            source: regZAppJ,
            inputs: ["advance": 5000, "payment": 230, "count": 24, "unitPeriodsPerYear": 12],
            precision: "±0.005 pp on the annualised rate — Appendix J publishes it to two decimals",
            values: ["annualPct": 9.69],
            tolerances: ["annualPct": 0.005]
        ),
        // (c)(2)(i): irregular FIRST payment of $250, then 23 of $230.
        Oracle(
            id: "regz-appJ-c2-i-irr",
            source: regZAppJ,
            inputs: ["advance": 5000, "firstPayment": 250, "payment": 230, "count": 23,
                     "unitPeriodsPerYear": 12],
            precision: "±0.005 pp — published to two decimals",
            values: ["annualPct": 10.08],
            tolerances: ["annualPct": 0.005]
        ),
        // (c)(3)(i): 23 payments of $230 then an irregular FINAL payment of $280.
        Oracle(
            id: "regz-appJ-c3-i-irr",
            source: regZAppJ,
            inputs: ["advance": 5000, "payment": 230, "count": 23, "finalPayment": 280,
                     "unitPeriodsPerYear": 12],
            precision: "±0.005 pp — published to two decimals",
            values: ["annualPct": 10.50],
            tolerances: ["annualPct": 0.005]
        ),
        // (c)(4)(i): irregular first AND final payment — $250, 22 × $230, $280.
        Oracle(
            id: "regz-appJ-c4-i-irr",
            source: regZAppJ,
            inputs: ["advance": 5000, "firstPayment": 250, "payment": 230, "count": 22,
                     "finalPayment": 280, "unitPeriodsPerYear": 12],
            precision: "±0.005 pp — published to two decimals",
            values: ["annualPct": 10.90],
            tolerances: ["annualPct": 0.005]
        ),
        // (c)(5)(iv): $1,000 repaid by a single $1,240 payment exactly two years later, w = 1.
        Oracle(
            id: "regz-appJ-c5-iv-irr",
            source: regZAppJ,
            inputs: ["advance": 1000, "finalPayment": 1240, "count": 1, "unitPeriodsPerYear": 1],
            precision: "±0.005 pp — published to two decimals (Form 3 or 4)",
            values: ["annualPct": 11.36],
            tolerances: ["annualPct": 0.005]
        ),

        // NIST HB 135 Example 7-1. The FEMP UPV* factors are published data (they embed energy price
        // escalation, so they are not plain uniform-present-value factors); what this oracle pins is
        // the life-cycle-cost composition LCC = I₀ + E, to the whole dollars NIST prints.
        Oracle(
            id: "nist-hb135-ex7-1-lcc",
            source: nistHB135,
            inputs: [
                "initialCost": 2000,
                "gasPricePerTherm": 1.05, "gasUPV": 16.15,
                "electricityPricePerKWh": 0.135, "electricityUPV": 15.48,
                "baseThermsPerYear": 1500, "baseKWhPerYear": 1200,
                "altThermsPerYear": 1300, "altKWhPerYear": 1100,
            ],
            precision: "±1 dollar — NIST prints both totals rounded to whole dollars",
            values: ["baseCaseLCC": 27944, "alternativeLCC": 26344, "netSavings": 1600],
            tolerances: ["baseCaseLCC": 1, "alternativeLCC": 1, "netSavings": 1]
        ),
    ]

    static func require(_ id: String) -> Oracle {
        guard let o = all.first(where: { $0.id == id }) else {
            fatalError("unknown oracle id '\(id)'")
        }
        return o
    }
}

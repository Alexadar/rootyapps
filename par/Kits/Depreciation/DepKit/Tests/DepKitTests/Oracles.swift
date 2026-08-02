import Foundation
import DepKit

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
    static let pub946 = """
        IRS Publication 946 (2025), "How To Depreciate Property", chapter 4 ("Figuring Depreciation \
        Under MACRS"), the worked office-furniture example; \
        https://www.irs.gov/pub/irs-pdf/p946.pdf (US government work, public domain); \
        retrieved 2026-07-27.
        """

    /// **Two published-table anomalies, recorded rather than absorbed.**
    ///
    /// The MACRS rounding-carry method reproduces 28 of the 30 published columns digit for digit. Two
    /// columns disagree by one unit in the last published place, and in both cases the difference is
    /// *shifted* to a later year so the column still totals exactly 100.00%:
    ///
    ///  • Table A-2 (mid-quarter, Q1), 20-year property — year 2 publishes 7.000 where the method gives
    ///    7.008; year 21 publishes 0.565 where the method gives 0.557.
    ///  • Table A-3 (mid-quarter, Q2), 7-year property — year 1 publishes 17.85 where the method gives
    ///    17.86; year 8 publishes 3.34 where the method gives 3.33. The exact first-year figure is
    ///    2/7 × 0.625 = 17.857142…, which rounds to 17.86 by any ordinary rule, and the same table's
    ///    3-year column (41.666… → 41.67) shows the IRS is rounding rather than truncating. That column
    ///    is therefore inconsistent with its own siblings.
    ///
    /// Both were verified against 200-dpi renders of Publication 946 pages 71 and 72, not just the text
    /// extraction. This map holds **what Par computes**; the corpus holds what the IRS publishes. The
    /// test asserts both, so neither can drift unnoticed — and the divergence goes on the release
    /// checklist for a human to confirm against a fresh copy of the publication.
    static let knownPublishedAnomalies: [String: [Int: Double]] = [
        "irs946-2025-tableA2-20yr": [2: 7.008, 21: 0.557],
        "irs946-2025-tableA3-7yr": [1: 17.86, 8: 3.33],
    ]

    /// The worked example Publication 946 prints in full, in dollars.
    static let furnitureRow = Oracle(
        id: "irs946-2025-furniture-example",
        source: pub946,
        inputs: ["cost": 10_000, "recoveryYears": 7],
        precision: "exact dollars — the publication prints whole-dollar deductions",
        values: [
            "year1": 1_429, "year2": 2_449, "year3": 1_749, "year4": 1_249,
            "year5": 893, "year6": 892, "year7": 893, "year8": 446,
        ],
        tolerances: [
            "year1": 0.5, "year2": 0.5, "year3": 0.5, "year4": 0.5,
            "year5": 0.5, "year6": 0.5, "year7": 0.5, "year8": 0.5,
        ]
    )

    /// The corpus. Expected numbers live ONLY here, each tied to an external source.
    static let all: [Oracle] = macrsRows + [furnitureRow]

    static func require(_ id: String) -> Oracle {
        guard let o = all.first(where: { $0.id == id }) else {
            fatalError("unknown oracle id '\(id)'")
        }
        return o
    }

    /// The corpus id for a table, so the tests can iterate conventions rather than hard-coding ids.
    static func macrsID(convention: Depreciation.Convention, recoveryYears: Int) -> String {
        let table: String
        switch convention {
        case .halfYear: table = "A1"
        case .midQuarterFirst: table = "A2"
        case .midQuarterSecond: table = "A3"
        case .midQuarterThird: table = "A4"
        case .midQuarterFourth: table = "A5"
        }
        return "irs946-2025-table\(table)-\(recoveryYears)yr"
    }
}

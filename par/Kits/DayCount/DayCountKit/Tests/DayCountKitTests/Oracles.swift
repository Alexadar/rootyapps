import Foundation

/// A ground-truth entry transcribed from an EXTERNAL published authority.
/// The implementer must NOT invent these numbers — every entry cites its `source`.
/// See ../../../../../calculators/VALIDATION.md for the policy this enforces, and
/// par/scratch/SOURCES.md for the transcription ledger with URLs and retrieval dates.
struct Oracle {
    let id: String
    let source: String            // external authority citation — MUST be non-empty (enforced)
    let inputs: [String: Double]  // dates are encoded yyyyMMdd so the suites carry no literals
    let precision: String         // field precision / rationale for the tolerance
    let values: [String: Double]
    let tolerances: [String: Double]

    /// True iff `actual` is within the cited tolerance of the oracle value for `key`.
    /// A tolerance of exactly 0 means the published value is an exact integer or an exact
    /// definition, and is asserted as equality.
    func matches(_ key: String, _ actual: Double) -> Bool {
        guard let v = values[key], let t = tolerances[key] else { return false }
        return abs(actual - v) <= t
    }

    /// Reads an input, trapping rather than silently substituting a default — a missing input is a
    /// corpus bug, not a test condition.
    func input(_ key: String) -> Double {
        guard let v = inputs[key] else { fatalError("oracle '\(id)' has no input '\(key)'") }
        return v
    }
}

enum Oracles {
    static let treasurySource = """
        31 CFR part 356, Appendix B ("Formulas and Examples"), section I.D(2) — US Treasury \
        Uniform Offering Circular, 7-1-24 edition, p. 410; \
        https://www.govinfo.gov/content/pkg/CFR-2024-title31-vol2/pdf/CFR-2024-title31-vol2-part356-appB.pdf \
        (US government work, public domain); retrieved 2026-07-27
        """

    static let isdaBondBasisSheetSource = """
        ISDA, "Calculation examples of 30/360 and 30E/360 in the 2006 ISDA Definitions" \
        (30-360-2006ISDADefs.xls, "30-360 Bond Basis" sheet, Example 2 and its footnote), \
        https://www.isda.org/a/mIJEE/30-360-2006ISDADefs.xls; retrieved 2026-07-27
        """

    /// Published day-count facts that are not ISDA Comparison-sheet rows.
    static let extraRows: [Oracle] = [
        // Treasury's own two-half-year reopening: a 10¾% bond issued 1985-07-02 and reopened
        // 1985-11-04 accrues 44 days of a 181-day half-year, then 81 days of a 184-day one.
        Oracle(
            id: "treasury-halfyear-44-of-181",
            source: treasurySource,
            inputs: ["periodStart": 19850215, "accrualStart": 19850702, "periodEnd": 19850815],
            precision: "exact integers — Treasury states 44 days of a 181-day half-year",
            values: ["accrualDays": 44, "periodDays": 181],
            tolerances: ["accrualDays": 0, "periodDays": 0]
        ),
        Oracle(
            id: "treasury-halfyear-81-of-184",
            source: treasurySource,
            inputs: ["periodStart": 19850815, "settlement": 19851104, "periodEnd": 19860215],
            precision: "exact integers — Treasury states 81 days of a 184-day half-year",
            values: ["accrualDays": 81, "periodDays": 184],
            tolerances: ["accrualDays": 0, "periodDays": 0]
        ),
        // The Bond-Basis curiosity ISDA flags in its own footnote: under §4.16(f) the two halves of
        // 2006-08-31 → 2007-08-31 sum to 361 days, not 360. Under the other two conventions: 360.
        Oracle(
            id: "isda-bond-basis-361-day-year",
            source: isdaBondBasisSheetSource,
            inputs: ["start": 20060831, "mid": 20070228, "end": 20070831],
            precision: "exact integers — 178 + 183 = 361 under Bond Basis; the footnote's whole point",
            values: [
                "firstHalf_thirty360": 178, "secondHalf_thirty360": 183, "year_thirty360": 361,
                "year_thirtyE360": 360, "year_thirtyE360ISDA": 360,
            ],
            tolerances: [
                "firstHalf_thirty360": 0, "secondHalf_thirty360": 0, "year_thirty360": 0,
                "year_thirtyE360": 0, "year_thirtyE360ISDA": 0,
            ]
        ),
    ]

    /// The corpus. Expected numbers live ONLY here, each tied to an external source.
    static let all: [Oracle] = isdaRows + extraRows

    static func require(_ id: String) -> Oracle {
        guard let o = all.first(where: { $0.id == id }) else {
            fatalError("unknown oracle id '\(id)'")
        }
        return o
    }
}

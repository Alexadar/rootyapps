import Foundation
import DimensionKit

/// Ground truth transcribed from NIST PS 20-20. Expected numbers live only here.
/// Policy: `docs/storypole_oracle_gate_2026-07-29.md` §2, §10.
struct Oracle {
    let id: String
    let source: String
    let inputs: [String: Double]
    let precision: String
    let values: [String: Double]
    let tolerances: [String: Double]

    func value(_ key: String) -> Double {
        guard let v = values[key] else { fatalError("oracle '\(id)' has no value '\(key)'") }
        return v
    }
    func tolerance(_ key: String) -> Double {
        guard let t = tolerances[key] else { fatalError("oracle '\(id)' has no tolerance for '\(key)'") }
        return t
    }
    func matches(_ key: String, _ actual: Double) -> Bool { abs(actual - value(key)) <= tolerance(key) }
}

enum Oracles {
    static let ps20 = """
        NIST SP / Voluntary Product Standard PS 20-20, "American Softwood Lumber Standard", \
        January 2020, U.S. Department of Commerce / NIST; \
        https://www.nist.gov/document/doc-ps-20-20-american-softwood-lumber-standard \
        (US Government work, public domain); retrieved 2026-07-29, HTTP 200. \
        NOTE: the handoff cited "PS 20-25", which does not exist.
        """

    static let all: [Oracle] = boardMeasure + dressedSections

    /// PS 20-20 §2.2 "Board measure": "The number of board feet in a piece of lumber is obtained by
    /// multiplying the nominal thickness in inches or fraction of an inch by the nominal width in
    /// feet by the length in feet."
    static let boardMeasure: [Oracle] = [
        Oracle(id: "bf-2x4x8",
               source: ps20 + " §2.2 Board measure. 2 x (4/12) x 8 = 16/3 board feet.",
               inputs: ["thicknessIn": 2, "widthIn": 4, "lengthFt": 8],
               precision: "exact: an exact rational, 5 1/3 BF",
               values: ["boardFeet": 16.0 / 3.0],
               tolerances: ["boardFeet": 1e-12]),
        Oracle(id: "bf-2x10x16",
               source: ps20 + " §2.2 Board measure.",
               inputs: ["thicknessIn": 2, "widthIn": 10, "lengthFt": 16],
               precision: "exact: 26 2/3 BF",
               values: ["boardFeet": 80.0 / 3.0],
               tolerances: ["boardFeet": 1e-12]),
        Oracle(id: "bf-1x12x10",
               source: ps20 + " §2.2 Board measure. A 1x12 at 10 ft is exactly 10 BF.",
               inputs: ["thicknessIn": 1, "widthIn": 12, "lengthFt": 10],
               precision: "exact",
               values: ["boardFeet": 10],
               tolerances: ["boardFeet": 0]),
        Oracle(id: "bf-one-board-foot",
               source: ps20 + " §2.2 Board measure. The definition itself: 144 cubic inches of "
                            + "nominal section is one board foot (1 x 12 x 12 inches).",
               inputs: ["thicknessIn": 1, "widthIn": 12, "lengthIn": 12],
               precision: "exact",
               values: ["boardFeet": 1],
               tolerances: ["boardFeet": 0]),
    ]

    /// PS 20-20 Table 3 — the rows everyone in the trade knows.
    static let dressedSections: [Oracle] = [
        Oracle(id: "dressed-2x4-dry",
               source: ps20 + " Table 3, \"Nominal and minimum-dressed sizes of boards, dimension, "
                            + "and timbers\": nominal 2 in -> 1-1/2 in dry; nominal 4 in -> 3-1/2 in dry.",
               inputs: ["nominalThicknessIn": 2, "nominalWidthIn": 4],
               precision: "exact: the standard tabulates exact fractions",
               values: ["dressedThicknessIn": 1.5, "dressedWidthIn": 3.5],
               tolerances: ["dressedThicknessIn": 0, "dressedWidthIn": 0]),
        Oracle(id: "dressed-2x4-green",
               source: ps20 + " Table 3, green column: nominal 2 in -> 1-9/16 in; nominal 4 in -> 3-9/16 in.",
               inputs: ["nominalThicknessIn": 2, "nominalWidthIn": 4],
               precision: "exact",
               values: ["dressedThicknessIn": 1.5625, "dressedWidthIn": 3.5625],
               tolerances: ["dressedThicknessIn": 0, "dressedWidthIn": 0]),
        Oracle(id: "dressed-2x10-dry",
               source: ps20 + " Table 3: nominal 2 in -> 1-1/2 in; nominal 10 in -> 9-1/4 in dry.",
               inputs: ["nominalThicknessIn": 2, "nominalWidthIn": 10],
               precision: "exact",
               values: ["dressedThicknessIn": 1.5, "dressedWidthIn": 9.25],
               tolerances: ["dressedThicknessIn": 0, "dressedWidthIn": 0]),
        Oracle(id: "dressed-1x6-dry",
               source: ps20 + " Table 3: nominal 1 in -> 3/4 in; nominal 6 in -> 5-1/2 in dry.",
               inputs: ["nominalThicknessIn": 1, "nominalWidthIn": 6],
               precision: "exact",
               values: ["dressedThicknessIn": 0.75, "dressedWidthIn": 5.5],
               tolerances: ["dressedThicknessIn": 0, "dressedWidthIn": 0]),
    ]

    static func require(_ id: String) -> Oracle {
        guard let o = all.first(where: { $0.id == id }) else { fatalError("unknown oracle id '\(id)'") }
        return o
    }
}

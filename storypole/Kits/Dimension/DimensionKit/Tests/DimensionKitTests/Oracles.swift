import Foundation

/// A ground-truth entry transcribed from an EXTERNAL published authority.
///
/// Expected numbers exist ONLY here, and every entry cites the document, the section, and a URI
/// that was actually fetched. The implementer must never author an expected value.
/// Gate + fetch log: `docs/storypole_oracle_gate_2026-07-29.md` §2, §10.
struct Oracle {
    let id: String
    let source: String                  // citation + section + URI + retrieval date — MUST be non-empty
    let inputs: [String: Double]
    let precision: String               // why the tolerance is what it is
    let values: [String: Double]
    let tolerances: [String: Double]

    func input(_ key: String) -> Double {
        guard let v = inputs[key] else { fatalError("oracle '\(id)' has no input '\(key)'") }
        return v
    }

    func value(_ key: String) -> Double {
        guard let v = values[key] else { fatalError("oracle '\(id)' has no value '\(key)'") }
        return v
    }

    func tolerance(_ key: String) -> Double {
        guard let t = tolerances[key] else { fatalError("oracle '\(id)' has no tolerance for '\(key)'") }
        return t
    }

    func matches(_ key: String, _ actual: Double) -> Bool {
        abs(actual - value(key)) <= tolerance(key)
    }
}

enum Oracles {

    // MARK: - Sources

    static let sp811 = """
        NIST SP 811 — NIST Special Publication 811 (2008 ed.), "Guide for the Use of the International System of \
        Units (SI)", Barry N. Taylor & Ambler Thompson; \
        https://nvlpubs.nist.gov/nistpubs/Legacy/SP/nistspecialpublication811e2008.pdf \
        (US Government work, public domain); retrieved 2026-07-29, HTTP 200.
        """

    static let ps20 = """
        NIST Voluntary Product Standard PS 20-20, "American Softwood Lumber Standard", January 2020, \
        U.S. Department of Commerce / NIST; \
        https://www.nist.gov/document/doc-ps-20-20-american-softwood-lumber-standard \
        (US Government work, public domain); retrieved 2026-07-29, HTTP 200. \
        NOTE: the handoff cited "PS 20-25", which does not exist — that URL 404s. PS 20-20 is current.
        """

    static let fr1959 = """
        Federal Register doc. 59-5442, 24 FR 5348 (National Bureau of Standards, 30 June 1959), \
        "Refinement of values for the yard and the pound", as quoted by NIST "SI Units - Length": \
        "The value for the inch, derived from the value of the Yard effective July 1, 1959, is \
        exactly equivalent to 25.4 mm"; https://www.nist.gov/pml/owm/si-units-length \
        (US Government work, public domain); retrieved 2026-07-29, HTTP 200.
        """

    static let fr85 = """
        85 FR 62698 (2020-10-05), "Deprecation of the United States (U.S.) Survey Foot", NIST/NGS-NOAA: \
        "Beginning on January 1, 2023, the U.S. survey foot should not be used."; \
        https://www.federalregister.gov/documents/2020/10/05/2020-21902/deprecation-of-the-united-states-us-survey-foot \
        (US Government work, public domain); retrieved 2026-07-29, HTTP 200.
        """

    // MARK: - The corpus

    static let all: [Oracle] = sp811Rounding + sp811Conversion + ps20DressedSizes + ps20Ties + exactUnits

    // ── NIST SP 811 §B.7.1 "Rounding numbers" ────────────────────────────────────────────────
    //
    // Rule 3, verbatim: "If the digits to be discarded begin with a 5 and all of the following
    // digits are 0, the digit preceding the 5 is unchanged if it is even and increased by 1 if it
    // is odd. (Note that this means that the final digit is always even.)"
    //
    // Values are expressed as (input, significant digits) -> rounded result.
    static let sp811Rounding: [Oracle] = [
        Oracle(id: "sp811-B71-3digits",
               source: sp811 + " §B.7.1 rule 1, worked example.",
               inputs: ["x": 6.9749515, "digits": 3],
               precision: "exact: the Guide prints the rounded value",
               values: ["rounded": 6.97],
               tolerances: ["rounded": 0]),
        Oracle(id: "sp811-B71-2digits",
               source: sp811 + " §B.7.1 rule 2, worked example.",
               inputs: ["x": 6.9749515, "digits": 2],
               precision: "exact",
               values: ["rounded": 7.0],
               tolerances: ["rounded": 0]),
        Oracle(id: "sp811-B71-5digits",
               source: sp811 + " §B.7.1 rule 2, worked example.",
               inputs: ["x": 6.9749515, "digits": 5],
               precision: "exact",
               values: ["rounded": 6.9750],
               tolerances: ["rounded": 0]),
        // The two that make the rule half-to-EVEN rather than half-up.
        Oracle(id: "sp811-B71-tie-odd",
               source: sp811 + " §B.7.1 rule 3, worked example — preceding digit 1 is ODD, so it increases.",
               inputs: ["x": 6.9749515, "digits": 7],
               precision: "exact",
               values: ["rounded": 6.974952],
               tolerances: ["rounded": 0]),
        Oracle(id: "sp811-B71-tie-even",
               source: sp811 + " §B.7.1 rule 3, worked example — preceding digit 0 is EVEN, so it is unchanged. "
                             + "Half-away-from-zero would give 6.974951 here; the Guide publishes 6.974950.",
               inputs: ["x": 6.9749505, "digits": 7],
               precision: "exact",
               values: ["rounded": 6.974950],
               tolerances: ["rounded": 0]),
    ]

    // ── NIST SP 811 §B.7.2 + §B.8 ────────────────────────────────────────────────────────────
    static let sp811Conversion: [Oracle] = [
        Oracle(id: "sp811-B72-36ft",
               source: sp811 + " §B.7.2, worked example: \"l = 36 ft x 0.3048 m/ft = 10.9728 m = 11.0 m\".",
               inputs: ["feet": 36],
               precision: "exact: both the product and the rounded result are printed",
               values: ["metersExact": 10.9728, "metersRounded3sf": 11.0],
               tolerances: ["metersExact": 0, "metersRounded3sf": 0]),
        Oracle(id: "sp811-B8-cubic-yard",
               source: sp811 + " §B.8, conversion factor table: cubic yard (yd3) -> cubic meter (m3) = 7.645549E-01.",
               inputs: ["cubicYards": 1],
               precision: "+/-5e-8: SP 811 prints the factor to seven significant digits",
               values: ["cubicMeters": 0.7645549],
               tolerances: ["cubicMeters": 5e-8]),
    ]

    // ── NIST PS 20-20 Table 3 ────────────────────────────────────────────────────────────────
    //
    // App. B §B1: "Metric dimensions are calculated at 25.4 millimeters (mm) times the dressed
    // dimension in inches. The nearest mm is significant for dimensions greater than 1/8 inch...
    // if 5 followed by only zeroes, retain the digit in the unit position (the digit before the
    // decimal point) if it is even or increase it one mm if it is odd."
    //
    // Every dressed size in Table 3 ("boards, dimension, and timbers"), 29 rows. The dressed inch
    // values are dyadic rationals and therefore exact in binary floating point, so tolerance is 0.
    static let ps20DressedSizes: [Oracle] = ps20Table3Rows.map { dressed, mm in
        Oracle(id: "ps20-table3-\(String(format: "%g", dressed).replacingOccurrences(of: ".", with: "_"))in",
               source: ps20 + " Table 3, \"Nominal and minimum-dressed sizes of boards, dimension, and "
                            + "timbers\"; rounding rule App. B §B1.",
               inputs: ["dressedInch": dressed],
               precision: "exact: the standard tabulates a whole number of millimetres",
               values: ["mm": mm],
               tolerances: ["mm": 0])
    }

    /// (dressed inches, published millimetres) — transcribed from PS 20-20 Table 3.
    static let ps20Table3Rows: [(Double, Double)] = [
        (0.3125, 8), (0.4375, 11), (0.5625, 14), (0.625, 16), (0.75, 19),
        (1, 25), (1.25, 32), (1.5, 38), (2, 51), (2.5, 64), (3, 76), (3.5, 89),
        (4, 102), (4.5, 114), (5.5, 140), (6.5, 165), (7.25, 184), (7.5, 190),
        (8.25, 210), (8.5, 216), (9.25, 235), (9.5, 241), (10.25, 260),
        (11.25, 286), (11.5, 292), (13.25, 337), (13.5, 343), (15.25, 387), (15.5, 394),
    ]

    // ── The discriminating ties ──────────────────────────────────────────────────────────────
    //
    // These two rows are the reason the default rule is halfToEven and not the carpentry
    // convention. Both land exactly on .5 mm; only one of them separates the two rules.
    static let ps20Ties: [Oracle] = [
        Oracle(id: "ps20-tie-7_5in-DISCRIMINATING",
               source: ps20 + " Table 3: dressed 7-1/2 in is published as 190 mm. "
                            + "7.5 x 25.4 = 190.5 EXACTLY. Round-half-to-even gives 190; "
                            + "round-half-away-from-zero gives 191. The standard publishes 190. "
                            + "This single row is the published evidence for the default rounding rule.",
               inputs: ["dressedInch": 7.5],
               precision: "exact",
               values: ["mmHalfToEven": 190, "mmHalfAwayFromZero": 191],
               tolerances: ["mmHalfToEven": 0, "mmHalfAwayFromZero": 0]),
        Oracle(id: "ps20-tie-2_5in-agreeing",
               source: ps20 + " Table 3: dressed 2-1/2 in is published as 64 mm. "
                            + "2.5 x 25.4 = 63.5 EXACTLY; the unit digit 3 is odd, so half-to-even "
                            + "rounds UP to 64 and both rules agree here. Included so the suite shows "
                            + "the rules coincide except where the neighbour is even.",
               inputs: ["dressedInch": 2.5],
               precision: "exact",
               values: ["mmHalfToEven": 64, "mmHalfAwayFromZero": 64],
               tolerances: ["mmHalfToEven": 0, "mmHalfAwayFromZero": 0]),
    ]

    // ── Exact defined units ──────────────────────────────────────────────────────────────────
    static let exactUnits: [Oracle] = [
        Oracle(id: "exact-inch-mm",
               source: fr1959,
               inputs: ["inches": 1],
               precision: "exact by definition, not a measurement",
               values: ["millimeters": 25.4],
               tolerances: ["millimeters": 0]),
        Oracle(id: "exact-foot-meter",
               source: fr1959 + " 1 ft = 12 x 25.4 mm = 0.3048 m exactly. Cross-checked against "
                              + "NIST SP 811 §B.8, which lists foot -> meter = 3.048E-01.",
               inputs: ["feet": 1],
               precision: "exact by definition",
               values: ["meters": 0.3048],
               tolerances: ["meters": 0]),
        Oracle(id: "exact-yard-meter",
               source: fr1959 + " The 1959 refixing defines the yard as 0.9144 m exactly. "
                              + "Cross-checked against NIST SP 811 §B.8: yard -> meter = 9.144E-01.",
               inputs: ["yards": 1],
               precision: "exact by definition",
               values: ["meters": 0.9144],
               tolerances: ["meters": 0]),
        Oracle(id: "survey-foot-meter",
               source: fr85 + " The US survey foot is 1200/3937 m exactly.",
               inputs: ["surveyFeet": 1],
               precision: "+/-1e-15: an exact rational evaluated in double precision",
               values: ["meters": 1200.0 / 3937.0],
               tolerances: ["meters": 1e-15]),
    ]

    static func require(_ id: String) -> Oracle {
        guard let o = all.first(where: { $0.id == id }) else {
            fatalError("unknown oracle id '\(id)'")
        }
        return o
    }
}

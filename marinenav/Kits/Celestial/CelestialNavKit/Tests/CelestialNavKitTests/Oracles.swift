import Foundation

/// External-authority ground truth (see ../../../VALIDATION.md). Transcribed, never invented.
struct Oracle {
    let id, source, inputs, precision: String
    let values: [String: Double]
    let tolerances: [String: Double]
    func matches(_ k: String, _ a: Double) -> Bool {
        guard let v = values[k], let t = tolerances[k] else { return false }
        return abs(a - v) <= t
    }
}

enum Oracles {
    static let all: [Oracle] = [
        Oracle(id: "meeus-25b-sun",
               source: "Meeus, Astronomical Algorithms (2nd ed.), Example 25.b — Sun 1992-10-13 0h TD (RA 198.38083°, Dec −7.78507°)",
               inputs: "1992-10-13 00:00 UT", precision: "±0.1° (compact series)",
               values: ["rightAscension": 198.38083, "declination": -7.78507],
               tolerances: ["rightAscension": 0.1, "declination": 0.1]),
        Oracle(id: "meeus-47a-moon",
               source: "Meeus, Astronomical Algorithms (2nd ed.), Example 47.a — Moon 1992-04-12 0h TD (λ 133.1627°, β −3.2292°)",
               inputs: "1992-04-12 00:00 UT", precision: "±0.25°/±0.15°",
               values: ["eclipticLongitude": 133.1627, "eclipticLatitude": -3.2292],
               tolerances: ["eclipticLongitude": 0.25, "eclipticLatitude": 0.15]),

        // The complete worked sight that was TODO(oracle) through two prior passes.
        // Every intermediate quantity is published, so each stage of the pipeline
        // -- dip, refraction, Ho, LHA, Hc, Z/Zn, intercept -- is pinned separately
        // rather than only the final answer.
        Oracle(id: "bowditch-805-kochab",
               source: "Bowditch, American Practical Navigator, NGA Pub. No. 9 (2024), Vol. 2, "
                     + "Chapter 8 'Sight Reduction', Section 805 worked example (Kochab, "
                     + "2024-06-01 UT 08h24m41s). U.S. Government work, public domain. "
                     + "https://thenauticalalmanac.com/2024_Bowditch-_American_Practical_Navigator"
                     + "/Volume_2/09_Volume_2_Calculations_For_Navigation/Chapter_8_Sight_Reduction.pdf",
               inputs: "hs 34deg54.6', IC 2.0' off the arc, height of eye 40 ft; "
                     + "GHA 153deg47.9', Dec 74deg03.4'N; assumed position 36N 066deg47.9'W",
               precision: "almanac work is carried to 0.1 arcminute, and each correction is "
                        + "ROUNDED to 0.1' before it is applied. Carrying full precision therefore "
                        + "differs from the printed Ho by the accumulated rounding of dip (6.145' "
                        + "-> 6.1') and refraction (1.427' -> 1.4'): 0.072' = 0.0012 deg. The "
                        + "ho_deg tolerance below is that accumulated rounding (2 x 0.05'), and "
                        + "the `almanacRoundedChainIsExact` test reproduces the printed value to "
                        + "0.0000' by rounding the same way",
               values: [
                   "dip_arcmin": 6.1,             // D for 40 ft
                   "ha_deg": 34.841667,           // 34deg50.5'
                   "refraction_arcmin": 1.4,      // St-P at ha
                   "ho_deg": 34.818333,           // 34deg49.1'
                   "lha_deg": 87.0,               // 087deg00.0'
                   "hc_deg": 35.226590,           // 35deg13.6'
                   "zn_deg": 340.4,               // N 19.6 W
                   "intercept_nm": -24.5,         // 24.5' AWAY (negative = away)
               ],
               tolerances: [
                   "dip_arcmin": 0.05,
                   "ha_deg": 0.001,
                   "refraction_arcmin": 0.05,
                   "ho_deg": 0.002,        // 2 x 0.05' of published rounding; see `precision`
                   "lha_deg": 0.001,
                   "hc_deg": 0.001,
                   "zn_deg": 0.05,
                   "intercept_nm": 0.1,
               ]),
    ]
    static func require(_ id: String) -> Oracle {
        guard let o = all.first(where: { $0.id == id }) else { fatalError("unknown oracle '\(id)'") }
        return o
    }
}

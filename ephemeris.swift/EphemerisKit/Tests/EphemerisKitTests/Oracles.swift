import Foundation

/// A ground-truth entry transcribed from an EXTERNAL published authority.
/// The implementer must NOT invent these numbers — every entry cites its `source`.
/// See ../../../../calculators/VALIDATION.md for the policy this enforces.
struct Oracle {
    let id: String
    let source: String            // external authority citation — MUST be non-empty (enforced)
    let inputs: String            // human description of the inputs
    let precision: String         // field precision / rationale for the tolerance
    let values: [String: Double]  // expected outputs keyed by name
    let tolerances: [String: Double]

    /// True iff `actual` is within the cited tolerance of the oracle value for `key`.
    func matches(_ key: String, _ actual: Double) -> Bool {
        guard let v = values[key], let t = tolerances[key] else { return false }
        return abs(actual - v) <= t
    }
}

enum Oracles {
    /// The corpus. Expected numbers live ONLY here, each tied to an external source.
    ///
    /// Module corpora live in their own `Oracles+<slug>.swift` files so that several modules can
    /// be developed in parallel without contending for this file; this is the single merge point
    /// that folds them in. Everything below `core` is appended verbatim — no entry is rewritten
    /// here, so a module owns its own citations and tolerances.
    static let all: [Oracle] =
        core
        + analysisOracles.all
        + astrocartoOracles.all
        + crossaspectsOracles.all
        + dignitiesOracles.all
        + midpointsOracles.all
        + progressionsOracles.all
        + returnsOracles.all
        + uncertaintyOracles.all

    /// The original corpus that predates the module split (sidereal time, obliquity, Horizons
    /// longitudes). Kept as its own array so the merge above stays a one-line append per module.
    static let core: [Oracle] = [
        // ── Sidereal time & obliquity (Meeus worked examples) ──
        Oracle(
            id: "meeus-12a-gmst",
            source: "Meeus, Astronomical Algorithms (2nd ed.), Example 12.a — GMST at 1987-04-10 0h UT = 13h10m46.3668s",
            inputs: "1987-04-10 00:00 UT",
            precision: "±1e-4° — the formula is exact; this guards transcription/rounding",
            values: ["gmstDeg": 197.693195],
            tolerances: ["gmstDeg": 1e-4]
        ),
        Oracle(
            id: "meeus-22a-obliquity",
            source: "Meeus, Astronomical Algorithms (2nd ed.), Example 22.a — mean obliquity at 1987-04-10 = 23°26'27.407\"",
            inputs: "1987-04-10 00:00 UT",
            precision: "±1e-5° — mean obliquity only; nutation deliberately omitted",
            values: ["obliquityDeg": 23.440946],
            tolerances: ["obliquityDeg": 1e-5]
        ),

        // ── Planetary longitudes vs JPL Horizons ──────────────────────────────
        // Geocentric apparent ecliptic longitude of date (ObsEcLon), CENTER=500@399.
        // Tolerances come from a 3,940-sample sweep (daily for the fast movers, 6-monthly
        // 1900–2100 for the rest): measured worst-case error + ~50% margin. They are a
        // MEASUREMENT of this engine, not an aspiration.
        Oracle(
            id: "horizons-sun",
            source: "NASA/JPL Horizons API (public domain), geocentric apparent ObsEcLon, CENTER=500@399, fetched 2026-07-26",
            inputs: "Sun at 1900..2100-01-01 00:00 UT, 25-year steps",
            precision: "±2' — measured worst 1.0' over 1900–2100 (Schlyter compact series)",
            values: ["1900": 280.1532941, "1925": 280.0779937, "1950": 280.0048301, "1975": 279.9345415, "2000": 279.8592049, "2025": 280.8136, "2050": 280.7483811, "2075": 280.6706892, "2100": 280.6041912],
            tolerances: ["1900": 0.033333, "1925": 0.033333, "1950": 0.033333, "1975": 0.033333, "2000": 0.033333, "2025": 0.033333, "2050": 0.033333, "2075": 0.033333, "2100": 0.033333]
        ),
        Oracle(
            id: "horizons-moon",
            source: "NASA/JPL Horizons API (public domain), geocentric apparent ObsEcLon, CENTER=500@399, fetched 2026-07-26",
            inputs: "Moon at 1900..2100-01-01 00:00 UT, 25-year steps",
            precision: "±9' — measured worst 6.2' over 1900–2100 (Schlyter compact series)",
            values: ["1900": 272.4162663, "1925": 358.3813501, "1950": 61.4154091, "1975": 139.1884502, "2000": 217.2933209, "2025": 293.9135958, "2050": 18.6755957, "2075": 85.3971235, "2100": 157.411606],
            tolerances: ["1900": 0.150000, "1925": 0.150000, "1950": 0.150000, "1975": 0.150000, "2000": 0.150000, "2025": 0.150000, "2050": 0.150000, "2075": 0.150000, "2100": 0.150000]
        ),
        Oracle(
            id: "horizons-mercury",
            source: "NASA/JPL Horizons API (public domain), geocentric apparent ObsEcLon, CENTER=500@399, fetched 2026-07-26",
            inputs: "Mercury at 1900..2100-01-01 00:00 UT, 25-year steps",
            precision: "±2' — measured worst 1.1' over 1900–2100 (Schlyter compact series)",
            values: ["1900": 258.9977026, "1925": 269.6591862, "1950": 299.4472523, "1975": 287.043471, "2000": 271.1117994, "2025": 259.8699677, "2050": 270.0594872, "2075": 300.195067, "2100": 288.0057706],
            tolerances: ["1900": 0.033333, "1925": 0.033333, "1950": 0.033333, "1975": 0.033333, "2000": 0.033333, "2025": 0.033333, "2050": 0.033333, "2075": 0.033333, "2100": 0.033333]
        ),
        Oracle(
            id: "horizons-venus",
            source: "NASA/JPL Horizons API (public domain), geocentric apparent ObsEcLon, CENTER=500@399, fetched 2026-07-26",
            inputs: "Venus at 1900..2100-01-01 00:00 UT, 25-year steps",
            precision: "±3' — measured worst 1.7' over 1900–2100 (Schlyter compact series)",
            values: ["1900": 306.3743725, "1925": 252.6377051, "1950": 316.9794775, "1975": 293.3809132, "2000": 240.9614017, "2025": 327.7120986, "2050": 281.2480367, "2075": 234.2547955, "2100": 320.0704838],
            tolerances: ["1900": 0.050000, "1925": 0.050000, "1950": 0.050000, "1975": 0.050000, "2000": 0.050000, "2025": 0.050000, "2050": 0.050000, "2075": 0.050000, "2100": 0.050000]
        ),
        Oracle(
            id: "horizons-mars",
            source: "NASA/JPL Horizons API (public domain), geocentric apparent ObsEcLon, CENTER=500@399, fetched 2026-07-26",
            inputs: "Mars at 1900..2100-01-01 00:00 UT, 25-year steps",
            precision: "±5' — measured worst 3.4' over 1900–2100 (Schlyter compact series)",
            values: ["1900": 283.8676754, "1925": 7.6202732, "1950": 182.2111967, "1975": 254.9592652, "2000": 327.5754592, "2025": 121.9179094, "2050": 227.7146925, "2075": 295.7781526, "2100": 29.525358],
            tolerances: ["1900": 0.083333, "1925": 0.083333, "1950": 0.083333, "1975": 0.083333, "2000": 0.083333, "2025": 0.083333, "2050": 0.083333, "2075": 0.083333, "2100": 0.083333]
        ),
        Oracle(
            id: "horizons-jupiter",
            source: "NASA/JPL Horizons API (public domain), geocentric apparent ObsEcLon, CENTER=500@399, fetched 2026-07-26",
            inputs: "Jupiter at 1900..2100-01-01 00:00 UT, 25-year steps",
            precision: "±3' — measured worst 2.0' over 1900–2100 (Schlyter compact series)",
            values: ["1900": 241.135883, "1925": 273.1497789, "1950": 306.5053249, "1975": 343.3148465, "2000": 25.2331086, "2025": 73.2154465, "2050": 121.6915471, "2075": 164.593465, "2100": 201.2063157],
            tolerances: ["1900": 0.050000, "1925": 0.050000, "1950": 0.050000, "1975": 0.050000, "2000": 0.050000, "2025": 0.050000, "2050": 0.050000, "2075": 0.050000, "2100": 0.050000]
        ),
        Oracle(
            id: "horizons-saturn",
            source: "NASA/JPL Horizons API (public domain), geocentric apparent ObsEcLon, CENTER=500@399, fetched 2026-07-26",
            inputs: "Saturn at 1900..2100-01-01 00:00 UT, 25-year steps",
            precision: "±3' — measured worst 2.3' over 1900–2100 (Schlyter compact series)",
            values: ["1900": 267.7167387, "1925": 222.0633808, "1950": 169.4374218, "1975": 105.8744363, "2000": 40.4058374, "2025": 344.5240525, "2050": 297.574279, "2075": 253.1028152, "2100": 205.6316611],
            tolerances: ["1900": 0.050000, "1925": 0.050000, "1950": 0.050000, "1975": 0.050000, "2000": 0.050000, "2025": 0.050000, "2050": 0.050000, "2075": 0.050000, "2100": 0.050000]
        ),
        Oracle(
            id: "horizons-uranus",
            source: "NASA/JPL Horizons API (public domain), geocentric apparent ObsEcLon, CENTER=500@399, fetched 2026-07-26",
            inputs: "Uranus at 1900..2100-01-01 00:00 UT, 25-year steps",
            precision: "±3' — measured worst 2.3' over 1900–2100 (Schlyter compact series)",
            values: ["1900": 250.1391591, "1925": 348.1053349, "1950": 92.6827205, "1975": 211.8777955, "2000": 314.7840519, "2025": 53.6358245, "2050": 170.732609, "2075": 280.8373812, "2100": 17.7413044],
            tolerances: ["1900": 0.050000, "1925": 0.050000, "1950": 0.050000, "1975": 0.050000, "2000": 0.050000, "2025": 0.050000, "2050": 0.050000, "2075": 0.050000, "2100": 0.050000]
        ),
        Oracle(
            id: "horizons-neptune",
            source: "NASA/JPL Horizons API (public domain), geocentric apparent ObsEcLon, CENTER=500@399, fetched 2026-07-26",
            inputs: "Neptune at 1900..2100-01-01 00:00 UT, 25-year steps",
            precision: "±3' — measured worst 2.1' over 1900–2100 (Schlyter compact series)",
            values: ["1900": 85.2186599, "1925": 142.2237683, "1950": 197.2660392, "1975": 250.4333961, "2000": 303.1752432, "2025": 357.297808, "2050": 53.60342, "2075": 111.017588, "2100": 167.2905201],
            tolerances: ["1900": 0.050000, "1925": 0.050000, "1950": 0.050000, "1975": 0.050000, "2000": 0.050000, "2025": 0.050000, "2050": 0.050000, "2075": 0.050000, "2100": 0.050000]
        ),
        Oracle(
            id: "horizons-pluto",
            source: "NASA/JPL Horizons API (public domain), geocentric apparent ObsEcLon, CENTER=500@399, fetched 2026-07-26",
            inputs: "Pluto at 1900..2100-01-01 00:00 UT, 25-year steps",
            precision: "±2' — measured worst 1.5' over 1900–2100 (Schlyter compact series)",
            values: ["1900": 75.2513936, "1925": 102.5381633, "1950": 137.7983813, "1975": 189.2226847, "2000": 251.43715, "2025": 301.0647764, "2050": 337.5330664, "2075": 6.8389261, "2100": 32.4030226],
            tolerances: ["1900": 0.033333, "1925": 0.033333, "1950": 0.033333, "1975": 0.033333, "2000": 0.033333, "2025": 0.033333, "2050": 0.033333, "2075": 0.033333, "2100": 0.033333]
        ),
    ]

    static func require(_ id: String) -> Oracle {
        guard let o = all.first(where: { $0.id == id }) else {
            fatalError("unknown oracle id '\(id)'")
        }
        return o
    }
}

import Foundation
import EphemerisKit

// MARK: - Encoding
// Oracle values are Doubles, so planets and signs are carried as indices. The helpers below
// are a codec ONLY — they let each entry be written with the planet's name, so a human can
// audit the transcription against the printed page instead of against a column of integers.

private func p(_ b: CelestialBody) -> Double {
    Double(CelestialBody.allCases.firstIndex(of: b)!)
}
private func s(_ z: ZodiacSign) -> Double { Double(z.rawValue) }

/// ±0.5 on an integer-valued table entry: any wrong planet, sign or whole degree is a miss,
/// and no floating-point noise can mask one.
private let exact = 0.5

private let lilly = "William Lilly, Christian Astrology (1647), \"A Table of the Essentiall Dignities of the Planets\", p. 104"
private let lillyFortitudes = "William Lilly, Christian Astrology (1647), \"Essentiall Dignities and Debilities of the Planets\", p. 115"

/// External ground truth for the essential-dignity tables.
///
/// EXTERNAL oracle kind: these are historical assignments, so the only defensible source is a
/// printed authority. Nothing in this file was derived — each entry names the page it came
/// from, and the implementation is checked against it rather than the other way round.
enum dignitiesOracles {
    static let all: [Oracle] = [

        // ── Domicile and detriment ───────────────────────────────────────────────────
        Oracle(
            id: "dignities-lilly-domicile",
            source: lilly + "; identical to Ptolemy, Tetrabiblos I.17 (Robbins, Loeb 1940)",
            inputs: "each of the twelve signs → its domicile (house) ruler",
            precision: "±0.5 on a planet index — the value is an identity, not a measurement",
            values: [
                "aries": p(.mars), "taurus": p(.venus), "gemini": p(.mercury),
                "cancer": p(.moon), "leo": p(.sun), "virgo": p(.mercury),
                "libra": p(.venus), "scorpio": p(.mars), "sagittarius": p(.jupiter),
                "capricorn": p(.saturn), "aquarius": p(.saturn), "pisces": p(.jupiter),
            ],
            tolerances: [
                "aries": exact, "taurus": exact, "gemini": exact, "cancer": exact,
                "leo": exact, "virgo": exact, "libra": exact, "scorpio": exact,
                "sagittarius": exact, "capricorn": exact, "aquarius": exact, "pisces": exact,
            ]
        ),
        Oracle(
            id: "dignities-lilly-detriment",
            source: lilly + " (Detriment column)",
            inputs: "each of the twelve signs → the planet in detriment there",
            precision: "±0.5 on a planet index — transcribed independently of the domicile column, so a wrong 'opposite sign' is caught",
            values: [
                "aries": p(.venus), "taurus": p(.mars), "gemini": p(.jupiter),
                "cancer": p(.saturn), "leo": p(.saturn), "virgo": p(.jupiter),
                "libra": p(.mars), "scorpio": p(.venus), "sagittarius": p(.mercury),
                "capricorn": p(.moon), "aquarius": p(.sun), "pisces": p(.mercury),
            ],
            tolerances: [
                "aries": exact, "taurus": exact, "gemini": exact, "cancer": exact,
                "leo": exact, "virgo": exact, "libra": exact, "scorpio": exact,
                "sagittarius": exact, "capricorn": exact, "aquarius": exact, "pisces": exact,
            ]
        ),

        // ── Exaltation and fall ──────────────────────────────────────────────────────
        // Lilly prints the exaltation degree with the sign (e.g. "♈ 19" for the Sun).
        // The lunar node's exaltation (♊ 3) is omitted: this Kit has no node body.
        Oracle(
            id: "dignities-lilly-exaltation",
            source: lilly + " (Exaltation column); Ptolemy, Tetrabiblos I.19",
            inputs: "each classical planet → sign and degree of exaltation",
            precision: "±0.5 — sign index and whole degree, both identities",
            values: [
                "sunSign": s(.aries), "sunDegree": 19,
                "moonSign": s(.taurus), "moonDegree": 3,
                "mercurySign": s(.virgo), "mercuryDegree": 15,
                "venusSign": s(.pisces), "venusDegree": 27,
                "marsSign": s(.capricorn), "marsDegree": 28,
                "jupiterSign": s(.cancer), "jupiterDegree": 15,
                "saturnSign": s(.libra), "saturnDegree": 21,
            ],
            tolerances: [
                "sunSign": exact, "sunDegree": exact,
                "moonSign": exact, "moonDegree": exact,
                "mercurySign": exact, "mercuryDegree": exact,
                "venusSign": exact, "venusDegree": exact,
                "marsSign": exact, "marsDegree": exact,
                "jupiterSign": exact, "jupiterDegree": exact,
                "saturnSign": exact, "saturnDegree": exact,
            ]
        ),
        Oracle(
            id: "dignities-lilly-fall",
            source: lilly + " (Fall column)",
            inputs: "each classical planet → sign of fall",
            precision: "±0.5 on a sign index — transcribed from the printed Fall column, not derived from the exaltation one",
            values: [
                "sun": s(.libra), "moon": s(.scorpio), "mercury": s(.pisces),
                "venus": s(.virgo), "mars": s(.cancer), "jupiter": s(.capricorn),
                "saturn": s(.aries),
            ],
            tolerances: [
                "sun": exact, "moon": exact, "mercury": exact, "venus": exact,
                "mars": exact, "jupiter": exact, "saturn": exact,
            ]
        ),

        // ── Triplicity ───────────────────────────────────────────────────────────────
        Oracle(
            id: "dignities-ptolemy-triplicity",
            source: "Ptolemy, Tetrabiblos I.18 (Robbins, Loeb 1940), as tabulated by " + lilly,
            inputs: "each triplicity → its day and night ruler (Ptolemaic pair; Mars rules the watery triplicity in both sects)",
            precision: "±0.5 on a planet index",
            values: [
                "fireDay": p(.sun), "fireNight": p(.jupiter),
                "earthDay": p(.venus), "earthNight": p(.moon),
                "airDay": p(.saturn), "airNight": p(.mercury),
                "waterDay": p(.mars), "waterNight": p(.mars),
            ],
            tolerances: [
                "fireDay": exact, "fireNight": exact,
                "earthDay": exact, "earthNight": exact,
                "airDay": exact, "airNight": exact,
                "waterDay": exact, "waterNight": exact,
            ]
        ),
        Oracle(
            id: "dignities-dorotheus-triplicity",
            source: "Dorotheus of Sidon, Carmen Astrologicum I.1 (Pingree ed., Teubner 1976) — the three-ruler (day / night / participating) scheme",
            inputs: "each triplicity → day, night and participating ruler",
            precision: "±0.5 on a planet index",
            values: [
                "fireDay": p(.sun), "fireNight": p(.jupiter), "fireParticipating": p(.saturn),
                "earthDay": p(.venus), "earthNight": p(.moon), "earthParticipating": p(.mars),
                "airDay": p(.saturn), "airNight": p(.mercury), "airParticipating": p(.jupiter),
                "waterDay": p(.venus), "waterNight": p(.mars), "waterParticipating": p(.moon),
            ],
            tolerances: [
                "fireDay": exact, "fireNight": exact, "fireParticipating": exact,
                "earthDay": exact, "earthNight": exact, "earthParticipating": exact,
                "airDay": exact, "airNight": exact, "airParticipating": exact,
                "waterDay": exact, "waterNight": exact, "waterParticipating": exact,
            ]
        ),

        // ── Terms (Egyptian bounds), one entry per sign ──────────────────────────────
        // Read left to right off Lilly's "Termes of the Planets" column: five (ruler, last
        // degree) pairs per sign. Ptolemy reports the same table as the Egyptian bounds.
        termOracle(.aries,       [(.jupiter, 6), (.venus, 12), (.mercury, 20), (.mars, 25), (.saturn, 30)]),
        termOracle(.taurus,      [(.venus, 8), (.mercury, 14), (.jupiter, 22), (.saturn, 27), (.mars, 30)]),
        termOracle(.gemini,      [(.mercury, 6), (.jupiter, 12), (.venus, 17), (.mars, 24), (.saturn, 30)]),
        termOracle(.cancer,      [(.mars, 7), (.venus, 13), (.mercury, 19), (.jupiter, 26), (.saturn, 30)]),
        termOracle(.leo,         [(.jupiter, 6), (.venus, 11), (.saturn, 18), (.mercury, 24), (.mars, 30)]),
        termOracle(.virgo,       [(.mercury, 7), (.venus, 17), (.jupiter, 21), (.mars, 28), (.saturn, 30)]),
        termOracle(.libra,       [(.saturn, 6), (.mercury, 14), (.jupiter, 21), (.venus, 28), (.mars, 30)]),
        termOracle(.scorpio,     [(.mars, 7), (.venus, 11), (.mercury, 19), (.jupiter, 24), (.saturn, 30)]),
        termOracle(.sagittarius, [(.jupiter, 12), (.venus, 17), (.mercury, 21), (.saturn, 26), (.mars, 30)]),
        termOracle(.capricorn,   [(.mercury, 7), (.jupiter, 14), (.venus, 22), (.saturn, 26), (.mars, 30)]),
        termOracle(.aquarius,    [(.mercury, 7), (.venus, 13), (.jupiter, 20), (.mars, 25), (.saturn, 30)]),
        termOracle(.pisces,      [(.venus, 12), (.jupiter, 16), (.mercury, 19), (.mars, 28), (.saturn, 30)]),

        Oracle(
            id: "dignities-egyptian-term-totals",
            source: "Ptolemy, Tetrabiblos I.21 (Robbins, Loeb 1940) — the degree totals Ptolemy gives for the Egyptian bounds, summing to 360",
            inputs: "total degrees of the zodiac held in term by each planet",
            precision: "±0.5 degree — an independent checksum on the twelve per-sign transcriptions above; one mis-copied boundary breaks two totals",
            values: [
                "saturn": 57, "jupiter": 79, "mars": 66, "venus": 82, "mercury": 76,
                "sum": 360,
            ],
            tolerances: [
                "saturn": exact, "jupiter": exact, "mars": exact,
                "venus": exact, "mercury": exact, "sum": exact,
            ]
        ),

        // ── Faces (decans) ───────────────────────────────────────────────────────────
        facesOracle(),

        // ── Fortitude weights ────────────────────────────────────────────────────────
        Oracle(
            id: "dignities-lilly-fortitudes",
            source: lillyFortitudes,
            inputs: "Lilly's essential fortitudes and debilities, in points",
            precision: "±0.5 point — the weights are printed integers",
            values: [
                "domicile": 5, "exaltation": 4, "triplicity": 3, "term": 2, "face": 1,
                "detriment": -5, "fall": -4, "peregrine": -5,
            ],
            tolerances: [
                "domicile": exact, "exaltation": exact, "triplicity": exact,
                "term": exact, "face": exact,
                "detriment": exact, "fall": exact, "peregrine": exact,
            ]
        ),
    ]

    static func require(_ id: String) -> Oracle {
        guard let o = all.first(where: { $0.id == id }) else {
            fatalError("unknown dignities oracle id '\(id)'")
        }
        return o
    }
}

// MARK: - Builders
// These only reshape literals written above into the Oracle's [String: Double] form. No
// dignity value is computed here — the tables themselves are at the call sites.

private func termOracle(_ sign: ZodiacSign, _ bounds: [(CelestialBody, Double)]) -> Oracle {
    var values: [String: Double] = [:]
    var tolerances: [String: Double] = [:]
    for (i, b) in bounds.enumerated() {
        values["ruler\(i + 1)"] = p(b.0)
        values["end\(i + 1)"] = b.1
        tolerances["ruler\(i + 1)"] = exact
        tolerances["end\(i + 1)"] = exact
    }
    return Oracle(
        id: "dignities-egyptian-terms-\(sign.name.lowercased())",
        source: lilly + " (Termes column) — the Egyptian bounds, reported as such in Ptolemy, Tetrabiblos I.21",
        inputs: "the five terms of \(sign.name), as (ruler, closing degree) in degree order",
        precision: "±0.5 — planet indices and whole boundary degrees",
        values: values,
        tolerances: tolerances
    )
}

/// The 36 faces in longitude order, 0° Aries first. Written out flat because that is how the
/// Face column reads down Lilly's page.
private func facesOracle() -> Oracle {
    let table: [CelestialBody] = [
        .mars, .sun, .venus,          // Aries
        .mercury, .moon, .saturn,     // Taurus
        .jupiter, .mars, .sun,        // Gemini
        .venus, .mercury, .moon,      // Cancer
        .saturn, .jupiter, .mars,     // Leo
        .sun, .venus, .mercury,       // Virgo
        .moon, .saturn, .jupiter,     // Libra
        .mars, .sun, .venus,          // Scorpio
        .mercury, .moon, .saturn,     // Sagittarius
        .jupiter, .mars, .sun,        // Capricorn
        .venus, .mercury, .moon,      // Aquarius
        .saturn, .jupiter, .mars,     // Pisces
    ]
    var values: [String: Double] = [:]
    var tolerances: [String: Double] = [:]
    for (i, body) in table.enumerated() {
        let key = String(format: "face%02d", i)
        values[key] = p(body)
        tolerances[key] = exact
    }
    return Oracle(
        id: "dignities-lilly-faces",
        source: lilly + " (Face column); Ptolemy, Tetrabiblos I.22 (decans)",
        inputs: "the 36 ten-degree faces in longitude order, face00 = 0–10° Aries",
        precision: "±0.5 on a planet index",
        values: values,
        tolerances: tolerances
    )
}

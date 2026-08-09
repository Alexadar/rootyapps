import Foundation

/// Oracles for chart analysis.
///
/// Two kinds live here, and the distinction matters when reading them:
///
/// * **Assignment tables** — which sign belongs to which triplicity and quadruplicity — are
///   external published fact, transcribed from Ptolemy. Nothing here re-derives them.
/// * **Pattern classifications** — the chart is *constructed* to satisfy a published definition
///   (ten bodies inside one trine is a bundle; ten evenly spread is a splash; nine plus a lone
///   opposite one is a bucket), and the oracle records what that definition demands. The gaps
///   are whole degrees by construction, so the geometry values are exact and the tolerances
///   guard floating-point only.
///
/// `patternIndex` is the position of the expected case in `ChartPattern.allCases`; the enum's
/// declaration order is the order Jones presents the patterns, and a test pins it.
enum analysisOracles {
    static let all: [Oracle] = [

        // ── Triplicities and quadruplicities ──────────────────────────────────
        Oracle(
            id: "analysis-triplicity-quadruplicity",
            source: "Ptolemy, Tetrabiblos I.11 (solstitial/equinoctial, solid, bicorporeal signs = the quadruplicities) and I.18 (Of Trigons = the triplicities), Loeb ed. — the standard sign→element/modality assignment",
            inputs: "Ten bodies at 15° of Aries…Capricorn (longitudes 15 + 30k, k = 0…9)",
            precision: "exact integers — counts of bodies; ±1e-9 guards nothing but arithmetic",
            values: ["fire": 3, "earth": 3, "air": 2, "water": 2,
                     "cardinal": 4, "fixed": 3, "mutable": 3,
                     "elementTotal": 10, "modalityTotal": 10],
            tolerances: ["fire": 1e-9, "earth": 1e-9, "air": 1e-9, "water": 1e-9,
                         "cardinal": 1e-9, "fixed": 1e-9, "mutable": 1e-9,
                         "elementTotal": 1e-9, "modalityTotal": 1e-9]
        ),

        // ── The seven planetary patterns ──────────────────────────────────────
        Oracle(
            id: "analysis-pattern-bundle",
            source: "Marc Edmund Jones, The Guide to Horoscope Interpretation (1941), 'The Seven Planetary Patterns' — bundle = every body within a trine; thresholds as made numeric by Robert Jansky and by Bil Tierney, Dynamics of Aspect Analysis (1983)",
            inputs: "Ten bodies at 12k degrees, k = 0…9 (span 108°)",
            precision: "exact by construction; ±1e-6 for the angles, ±0.25 to pin the integer pattern index",
            values: ["patternIndex": 0, "occupiedSpan": 108, "largestGap": 252, "secondLargestGap": 12],
            tolerances: ["patternIndex": 0.25, "occupiedSpan": 1e-6, "largestGap": 1e-6, "secondLargestGap": 1e-6]
        ),
        Oracle(
            id: "analysis-pattern-bundle-wrapped",
            source: "Marc Edmund Jones, The Guide to Horoscope Interpretation (1941) — the pattern is a property of the shape, not of where 0° Aries happens to fall; same bundle rotated across the 0°/360° seam",
            inputs: "Ten bodies at (350 + 12k) mod 360, k = 0…9 (same 108° span, straddling 0°)",
            precision: "must match the unrotated bundle exactly — this is the wrap guard",
            values: ["patternIndex": 0, "occupiedSpan": 108, "largestGap": 252, "secondLargestGap": 12],
            tolerances: ["patternIndex": 0.25, "occupiedSpan": 1e-6, "largestGap": 1e-6, "secondLargestGap": 1e-6]
        ),
        Oracle(
            id: "analysis-pattern-bowl",
            source: "Marc Edmund Jones, The Guide to Horoscope Interpretation (1941) — bowl = all bodies in one hemisphere, i.e. an empty arc of at least 180°",
            inputs: "Ten bodies at 18k degrees, k = 0…9 (span 162°)",
            precision: "exact by construction; ±1e-6 for the angles, ±0.25 for the pattern index",
            values: ["patternIndex": 1, "occupiedSpan": 162, "largestGap": 198, "secondLargestGap": 18],
            tolerances: ["patternIndex": 0.25, "occupiedSpan": 1e-6, "largestGap": 1e-6, "secondLargestGap": 1e-6]
        ),
        Oracle(
            id: "analysis-pattern-bucket",
            source: "Marc Edmund Jones, The Guide to Horoscope Interpretation (1941) — bucket = a bowl plus a single 'handle' body standing clear of both rims (Jansky: at least an empty sextile on each side)",
            inputs: "Nine bodies at 20k degrees, k = 0…8 (span 160°), plus one at 250°",
            precision: "exact by construction; handleCount is the number of bodies in the handle",
            values: ["patternIndex": 2, "occupiedSpan": 250, "largestGap": 110, "secondLargestGap": 90, "handleCount": 1],
            tolerances: ["patternIndex": 0.25, "occupiedSpan": 1e-6, "largestGap": 1e-6, "secondLargestGap": 1e-6, "handleCount": 1e-9]
        ),
        Oracle(
            id: "analysis-pattern-locomotive",
            source: "Marc Edmund Jones, The Guide to Horoscope Interpretation (1941) — locomotive = bodies over two thirds of the wheel with one empty trine",
            inputs: "Ten bodies at (240/9)k degrees, k = 0…9 (span 240°, one 120° gap)",
            precision: "the 240/9 step is not representable in binary, so ±1e-6 absorbs the rounding",
            values: ["patternIndex": 3, "occupiedSpan": 240, "largestGap": 120, "secondLargestGap": 26.666667],
            tolerances: ["patternIndex": 0.25, "occupiedSpan": 1e-6, "largestGap": 1e-6, "secondLargestGap": 1e-5]
        ),
        Oracle(
            id: "analysis-pattern-seesaw",
            source: "Marc Edmund Jones, The Guide to Horoscope Interpretation (1941) — seesaw = two groups opposed across the wheel, each separated from the other by an empty sextile or more",
            inputs: "Five bodies at 0,10,20,30,40° and five at 180,190,200,210,220°",
            precision: "exact by construction; both gaps are 140°, so largest and second largest coincide",
            values: ["patternIndex": 4, "occupiedSpan": 220, "largestGap": 140, "secondLargestGap": 140],
            tolerances: ["patternIndex": 0.25, "occupiedSpan": 1e-6, "largestGap": 1e-6, "secondLargestGap": 1e-6]
        ),
        Oracle(
            id: "analysis-pattern-splash",
            source: "Marc Edmund Jones, The Guide to Horoscope Interpretation (1941) — splash = bodies scattered around the wheel with no grouping gap",
            inputs: "Ten bodies evenly spread at 36k degrees, k = 0…9",
            precision: "exact by construction; every gap is 36°, below the 60° grouping threshold",
            values: ["patternIndex": 5, "occupiedSpan": 324, "largestGap": 36, "secondLargestGap": 36],
            tolerances: ["patternIndex": 0.25, "occupiedSpan": 1e-6, "largestGap": 1e-6, "secondLargestGap": 1e-6]
        ),
        Oracle(
            id: "analysis-pattern-splay",
            source: "Marc Edmund Jones, The Guide to Horoscope Interpretation (1941) — splay = irregular, several distinct groups (the 'tripod'), fitting none of the other six",
            inputs: "Three tight groups: 0,10,20° / 130,140,150° / 250,260,270°",
            precision: "exact by construction; three gaps of 110/100/90° all exceed the 60° threshold",
            values: ["patternIndex": 6, "occupiedSpan": 250, "largestGap": 110, "secondLargestGap": 100, "clusterCount": 3],
            tolerances: ["patternIndex": 0.25, "occupiedSpan": 1e-6, "largestGap": 1e-6, "secondLargestGap": 1e-6, "clusterCount": 1e-9]
        ),
    ]
}

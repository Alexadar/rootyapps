import Foundation

/// Oracles for cross-set (transit↔natal, synastry) aspect detection.
///
/// ORACLE KIND: property. Cross-aspect detection produces no new astronomy — it reuses
/// longitudes that already have Horizons oracles. What it can get wrong is *structure*:
/// the aspect angles it matches against, how many pairs it considers, and the circular
/// metric it measures with. Each of those is pinned to an external authority below.
/// The one number that is genuinely astronomical — how long a return takes — is anchored
/// to the published sidereal period of Saturn.
enum crossaspectsOracles {
    static let all: [Oracle] = [
        Oracle(
            id: "crossaspects-ptolemaic-angles",
            source: "Ptolemy, Tetrabiblos I.13 (Robbins tr., Loeb 1940) — the five classical configurations: conjunction 0°, sextile 60°, quartile 90°, trine 120°, opposition 180°",
            inputs: "aspect angle, in degrees, keyed by lowercased aspect name",
            precision: "±1e-9° — these are exact fractions of the circle (0, 1/6, 1/4, 1/3, 1/2); the tolerance guards transcription only, not accuracy",
            values: ["conjunction": 0, "sextile": 60, "square": 90, "trine": 120, "opposition": 180],
            tolerances: ["conjunction": 1e-9, "sextile": 1e-9, "square": 1e-9, "trine": 1e-9, "opposition": 1e-9]
        ),
        Oracle(
            id: "crossaspects-cartesian-cardinality",
            source: "Halmos, Naive Set Theory (1960), §6 — |A×B| = |A|·|B|; and the binomial coefficient C(n,2) = n(n−1)/2 for unordered pairs within one set (Graham/Knuth/Patashnik, Concrete Mathematics §5.1)",
            inputs: "10 bodies against 10 bodies (CelestialBody.allCases), and 3 against 10",
            precision: "exact integers; ±0.5 so a fractional count could never pass",
            values: ["orderedPairs": 100, "withinSetPairs": 45, "selfPairs": 10, "threeByTen": 30],
            tolerances: ["orderedPairs": 0.5, "withinSetPairs": 0.5, "selfPairs": 0.5, "threeByTen": 0.5]
        ),
        Oracle(
            id: "crossaspects-circular-metric",
            source: "Standard metric on the circle group ℝ/360ℤ: d(a,b) = min(|a−b| mod 360, 360 − (|a−b| mod 360)) ∈ [0,180]. Angle reduction to [0,360) per Meeus, Astronomical Algorithms (2nd ed.), ch. 1 'Hints and Tips'",
            inputs: "longitude pairs straddling the 0°/360° seam and beyond 180°",
            precision: "±1e-9° — the metric is exact arithmetic; the tolerance only absorbs binary floating point",
            values: ["sep359to1": 2, "sep1to359": 2, "sep300to0": 60, "sep190to0": 170],
            tolerances: ["sep359to1": 1e-9, "sep1to359": 1e-9, "sep300to0": 1e-9, "sep190to0": 1e-9]
        ),
        Oracle(
            id: "crossaspects-saturn-return",
            source: "NASA NSSDC Saturn Fact Sheet (public domain) — sidereal orbit period 10,759.22 days = 29.4571 Julian years",
            inputs: "tightest transiting-Saturn ☌ natal-Saturn self-pair from a daily scan over natal+27y..natal+32y, for the 11 natal epochs 1900-01-01…2000-01-01 (10-year steps); and the mean of those 11 returns",
            precision: "single return ±1.4 yr, mean ±0.35 yr. The fact-sheet figure is the HELIOCENTRIC sidereal period; an individual geocentric return lands wherever Saturn's retrograde loop crosses the natal degree, which the ±6° annual parallax wobble and Saturn's eccentricity move by most of a year. Measured worst single-epoch offset 0.954 yr and mean offset 0.214 yr over the 11 epochs, each plus ~50% margin. The loose single-return bound still fails hard if self-pairs are dropped (no return at all) or the wrong cycle is matched",
            values: ["returnYears": 29.4571, "meanReturnYears": 29.4571],
            tolerances: ["returnYears": 1.4, "meanReturnYears": 0.35]
        ),
    ]

    /// Local lookup. These entries are not in `Oracles.all` until an integration pass
    /// appends this array, so resolving through `Oracles.require` would trap until then.
    static func require(_ id: String) -> Oracle {
        guard let o = all.first(where: { $0.id == id }) else {
            fatalError("unknown cross-aspect oracle id '\(id)'")
        }
        return o
    }
}

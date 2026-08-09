import Foundation

/// Oracle corpus for circular midpoints and the midpoint-method composite.
///
/// These are **property** oracles: the half-sum is defined geometrically, so every value below is
/// forced by the published definition rather than measured off an ephemeris. That is why the
/// tolerances are 1e-9° — they guard arithmetic and wrap handling, not accuracy.
///
/// Kept in its own file (and its own array) so the shared `Oracles.all` stays a single merge
/// point; an integration pass appends `midpointsOracles.all` to it.
enum midpointsOracles {
    static let all: [Oracle] = [

        // ── The half-sum itself ────────────────────────────────────────────────
        Oracle(
            id: "midpoints-half-sum-shorter-arc",
            source: "Reinhold Ebertin, The Combination of Stellar Influences — the half-sum (midpoint) of two planets is the point bisecting the SHORTER arc between them, not the arithmetic mean of the two longitudes",
            inputs: "longitude pairs, degrees: (350,10), (10,350), (100,200), (0,90), (359,1)",
            precision: "±1e-9° — exact by definition; the tolerance guards wrap handling and double arithmetic only",
            values: ["350_10": 0, "10_350": 0, "100_200": 150, "0_90": 45, "359_1": 0],
            tolerances: ["350_10": 1e-9, "10_350": 1e-9, "100_200": 1e-9, "0_90": 1e-9, "359_1": 1e-9]
        ),
        Oracle(
            id: "midpoints-half-sum-axis",
            source: "Reinhold Ebertin, The Combination of Stellar Influences — a half-sum and its opposition form one axis; a planet on either end activates the same midpoint",
            inputs: "the far midpoint (half-sum + 180°) of the pairs (350,10) and (100,200)",
            precision: "±1e-9° — exact by definition",
            values: ["350_10": 180, "100_200": 330],
            tolerances: ["350_10": 1e-9, "100_200": 1e-9]
        ),

        // ── The two branches either side of opposition ─────────────────────────
        Oracle(
            id: "midpoints-near-opposition-branches",
            source: "Reinhold Ebertin, The Combination of Stellar Influences — shorter-arc definition applied on each side of exact opposition; which arc is shorter swaps as the separation crosses 180°",
            inputs: "pairs (0, 179.9) — shorter arc runs 0→179.9 — and (0, 180.1) — shorter arc runs 180.1→360",
            precision: "±1e-9° — exact by definition; the pair straddles the branch and a sign slip moves the answer by 180°, far outside the tolerance",
            values: ["0_179.9": 89.95, "0_180.1": 270.05],
            tolerances: ["0_179.9": 1e-9, "0_180.1": 1e-9]
        ),

        // ── The genuinely ambiguous case ───────────────────────────────────────
        Oracle(
            id: "midpoints-opposition-tiebreak",
            source: "Reinhold Ebertin, The Combination of Stellar Influences — at exact opposition BOTH half-sums are equidistant and the literature reads the axis rather than one end, so no external authority names a single value. The numbers below are this Kit's documented tie-break (midpoint of the arc running counterclockwise from the numerically smaller normalized longitude), recorded here so that changing the convention breaks a test instead of silently moving a chart",
            inputs: "exactly opposed pairs, degrees: (0,180), (180,0), (10,190), (270,90)",
            precision: "±1e-9° — a convention, so exactness is the whole point; the alternative answer differs by 180°",
            values: ["0_180": 90, "180_0": 90, "10_190": 100, "270_90": 180],
            tolerances: ["0_180": 1e-9, "180_0": 1e-9, "10_190": 1e-9, "270_90": 1e-9]
        ),

        // ── Composite (midpoint method) ────────────────────────────────────────
        Oracle(
            id: "midpoints-composite-midpoint-method",
            source: "Robert Hand, Planets in Composite: Analyzing Human Relationships — the composite chart places each planet at the (nearer) midpoint of its two natal positions",
            inputs: "chart A Sun 10°, Moon 200°, Mars 350°; chart B Sun 350°, Moon 100°, Mars 20°",
            precision: "±1e-9° — exact by definition; the Sun and Mars pairs both cross 0° Aries, which is where an arithmetic mean would land 180° away",
            values: ["sun": 0, "moon": 150, "mars": 5],
            tolerances: ["sun": 1e-9, "moon": 1e-9, "mars": 1e-9]
        ),
    ]

    static func require(_ id: String) -> Oracle {
        guard let o = all.first(where: { $0.id == id }) else {
            fatalError("unknown midpoints oracle id '\(id)'")
        }
        return o
    }
}

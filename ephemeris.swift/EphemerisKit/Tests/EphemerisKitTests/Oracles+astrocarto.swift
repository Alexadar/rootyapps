import Foundation

/// Oracles for the astrocartography lines.
///
/// **Kind: construction.** There is no published table of A\*C\*G line longitudes to transcribe —
/// the commercial engines (Solar Fire, Astrodienst) print maps, not numbers, and their bodies
/// carry true ecliptic latitude, which this Kit's position engine does not publish. So the oracle
/// is the *definition* instead: each entry pins the exact value some standard identity must take
/// at a point the implementation claims is on a line, cited to the authority that states the
/// identity. A wrong implementation cannot satisfy them — an astrocartography line is completely
/// determined by "hour angle 0" and "altitude 0", so reproducing those two numbers at every
/// sampled point *is* reproducing the line.
///
/// One entry (`astrocarto-solstice-rising-limit`) is a genuine external number: the Arctic Circle.
///
/// Kept in its own file — `Oracles.swift` is a single shared array and several modules land in it.
enum astrocartoOracles {
    static let all: [Oracle] = [

        // ── The two defining identities ───────────────────────────────────────
        Oracle(
            id: "astrocarto-mc-hour-angle",
            source: "Meeus, Astronomical Algorithms (2nd ed.), ch. 13 & 15 — a body culminates when its hour angle H = LST − α is zero; the MC line is therefore the meridian λ_earth = α − θ₀.",
            inputs: "Every body, every sampled point of its MC line, 1990-02-14 07:42 UT",
            precision: "±1e-6° — closed form, no iteration; the tolerance only guards a wrap or a transcription slip, not accuracy",
            values: ["hourAngleDeg": 0],
            tolerances: ["hourAngleDeg": 1e-6]
        ),
        Oracle(
            id: "astrocarto-horizon-altitude",
            source: "Jim Lewis, Astro*Carto*Graphy (1976) — the rising/setting lines are the loci where the body's centre is on the horizon; altitude from Meeus 13.6, sin h = sin φ sin δ + cos φ cos δ cos H, taken at exactly h = 0 (geometric, no refraction).",
            inputs: "Every body, every sampled point of its AC and DC lines, 1990-02-14 07:42 UT, latitudes -66…+66",
            precision: "±1e-6° — the branch is solved in closed form from cos H₀ = −tan φ tan δ; a 1° error in longitude moves altitude by ≳0.5°, so this tolerance is ~5 orders of magnitude below a real defect",
            values: ["altitudeDeg": 0],
            tolerances: ["altitudeDeg": 1e-6]
        ),
        Oracle(
            id: "astrocarto-rise-hour-angle-relation",
            source: "Meeus, Astronomical Algorithms (2nd ed.), eq. 15.1 — cos H₀ = (sin h₀ − sin φ sin δ)/(cos φ cos δ), which at h₀ = 0 reduces to cos H₀ = −tan φ tan δ.",
            inputs: "The semi-diurnal arc returned for a grid of declinations (-23…+23) and latitudes (-66…+66)",
            precision: "±1e-12 — a pure algebraic identity on the returned H₀; anything above rounding noise is a wrong formula",
            values: ["residual": 0],
            tolerances: ["residual": 1e-12]
        ),

        // ── Structural identities the pair of lines must satisfy ──────────────
        Oracle(
            id: "astrocarto-ic-opposition",
            source: "Definitional — the Imum Coeli is the lower meridian, the antimeridian of the Medium Coeli, so the IC line is the MC line's antipodal meridian.",
            inputs: "Every body's MC and IC line longitudes, 1990-02-14 07:42 UT",
            precision: "±1e-9° — exact by construction (one added 180); this catches a normalisation that folds the wrap the wrong way",
            values: ["separationDeg": 180],
            tolerances: ["separationDeg": 1e-9]
        ),
        Oracle(
            id: "astrocarto-equinox-quadrature",
            source: "Spherical geometry — a body on the celestial equator (δ = 0) rises 6h before and sets 6h after culminating at every latitude (Meeus 15.1 gives cos H₀ = 0 ⇒ H₀ = 90°), so its AC and DC lines are meridians exactly 90° of longitude either side of its MC line.",
            inputs: "Pure frame: ecliptic degree 0 with obliquity 0 (δ = 0 exactly), latitudes -80…+80, GMST 0",
            precision: "±1e-9° — the pure frame makes δ identically zero, so the expected value is exact and no ephemeris error enters",
            values: ["acOffsetDeg": -90, "dcOffsetDeg": 90],
            tolerances: ["acOffsetDeg": 1e-9, "dcOffsetDeg": 1e-9]
        ),
        Oracle(
            id: "astrocarto-subsolar-zenith",
            source: "Definitional — the subsolar point (latitude = the Sun's declination, longitude = the Sun's MC meridian) is where the Sun is at the zenith, altitude 90°.",
            inputs: "Sun, 1990-02-14 07:42 UT; the point (δ☉, MC-line longitude)",
            precision: "±1e-6° — closed form; the Sun's own ~1′ longitude error cancels because declination and MC longitude are both taken from the same computed position",
            values: ["altitudeDeg": 90],
            tolerances: ["altitudeDeg": 1e-6]
        ),

        // ── External geographic constant ──────────────────────────────────────
        Oracle(
            id: "astrocarto-solstice-rising-limit",
            source: "IERS/USNO — the Arctic Circle, 66°33′49″ N (66.5636°) for the current epoch, is by definition 90° − ε and is the midnight-sun boundary: at the June solstice the Sun does not set north of it, so the Sun's rising line must terminate exactly there.",
            inputs: "Sun at 2026-06-21 12:00 UT (≈3.6 h after the solstice instant)",
            precision: "±0.05° — the published circle uses a rounded epoch obliquity and the sample is a few hours off the exact solstice; both effects are well under 0.05°, while a wrong circumpolar test would miss by degrees",
            values: ["limitLatitudeDeg": 66.5636],
            tolerances: ["limitLatitudeDeg": 0.05]
        ),
    ]
}

import Foundation

/// Oracles for secondary progressions and solar arc directions.
///
/// **Kind: construction.** Progressions add no astronomy — they are a *definition* laid on top
/// of the existing ephemeris ("one day of sky stands for one year of life"). There is therefore
/// no external table of progressed positions worth transcribing: any such table is just some
/// other engine's Sun and Moon, and checking against it would only re-test `Ephemeris`, which
/// already has its own Horizons corpus.
///
/// What can be pinned externally is (a) the length of the year the map is built on, and (b) the
/// defining identities themselves, whose expected value is exactly zero residual. The
/// zero-residual entries carry a tolerance at the level of double-precision round-off, so they
/// fail on a real sign/wrap/convention error and on nothing else.
enum progressionsOracles {
    static let all: [Oracle] = [

        // ── The unit of the map ───────────────────────────────────────────────
        Oracle(
            id: "progressions-tropical-year",
            source: "Meeus, Astronomical Algorithms (2nd ed.), ch. 27 — mean tropical year at J2000 = 365.242190 days",
            inputs: "none — a defining constant of the day-for-a-year map",
            precision: "±1e-6 d — the constant is exact as transcribed; this guards a typo",
            values: ["days": 365.242190],
            tolerances: ["days": 1e-6]
        ),
        Oracle(
            id: "progressions-mean-solar-motion",
            source: "Derived from the same constant: 360° / 365.242190 d (mean daily motion of the Sun in longitude)",
            inputs: "none — a defining constant, used only to unwrap the solar arc",
            precision: "±1e-9 °/d — pure arithmetic on the year length",
            values: ["degPerDay": 0.9856473590852142],
            tolerances: ["degPerDay": 1e-9]
        ),

        // ── The date map ──────────────────────────────────────────────────────
        Oracle(
            id: "progressions-day-for-a-year-at-40",
            source: "Definition of secondary progression (a day for a year), as stated in Meeus, Astronomical Algorithms (2nd ed.), ch. 27 for the year length and in standard practice for the map: age N years → birth + N days",
            inputs: "birth + 40 tropical years",
            precision: "±1e-9 d on the ephemeris offset; ±1e-6 d on the calendar offset (40 × 365.242190)",
            values: ["progressedOffsetDays": 40.0, "calendarOffsetDays": 14609.6876],
            tolerances: ["progressedOffsetDays": 1e-9, "calendarOffsetDays": 1e-6]
        ),

        // ── The defining identities (expected residual: exactly zero) ─────────
        Oracle(
            id: "progressions-chart-is-natal-at-progressed-date",
            source: "Definition: the progressed chart for age N IS the natal computation evaluated at birth + N days — no separate model exists",
            inputs: "birth 1990-03-15 12:00 UT, ages 0…80 in 5-year steps, all ten bodies",
            precision: "±1e-12° — the two paths must be the same arithmetic, not merely close",
            values: ["maxLongitudeDiffDeg": 0.0, "maxSpeedDiffDegPerDay": 0.0],
            tolerances: ["maxLongitudeDiffDeg": 1e-12, "maxSpeedDiffDegPerDay": 1e-12]
        ),
        Oracle(
            id: "progressions-arc-is-progressed-minus-natal-sun",
            source: "Definition of solar arc: the arc the progressed Sun has moved from the natal Sun",
            inputs: "birth 1990-03-15 12:00 UT, ages 0…80 in 5-year steps",
            precision: "±1e-9° — residual of arc − norm180(progressedSun − natalSun) over ages where the arc is under 180°",
            values: ["maxResidualDeg": 0.0],
            tolerances: ["maxResidualDeg": 1e-9]
        ),
        Oracle(
            id: "progressions-arc-reproduces-progressed-sun",
            source: "Definition of solar arc direction: adding the arc to the natal Sun must return the progressed Sun (the Sun is the one body where direction and progression coincide)",
            inputs: "birth 1990-03-15 12:00 UT, ages 0…400 (arc exceeds a full turn at the top end)",
            precision: "±1e-9° — residual of norm360(natalSun + arc) − progressedSun",
            values: ["maxResidualDeg": 0.0],
            tolerances: ["maxResidualDeg": 1e-9]
        ),

        // ── The 0°/360° wrap ──────────────────────────────────────────────────
        Oracle(
            id: "progressions-arc-wraps-through-aries",
            source: "Definition: a late-Pisces natal Sun directed by ~30° lands in Aries — the directed longitude must wrap through 0°, and the arc itself must stay positive (≈ age × mean solar motion, 30 × 0.9856473590852142)",
            inputs: "birth 1990-03-15 12:00 UT (Sun in late Pisces), age 30 years",
            precision: "±1e-9° on the wrap residual; ±4° on the arc, which is the MEAN value — true minus mean longitude is the equation of the centre, ±1.92° (2e rad, e = 0.0167), and it enters twice, once at each end of the arc",
            values: ["wrapResidualDeg": 0.0, "arcDeg": 29.569420772556423],
            tolerances: ["wrapResidualDeg": 1e-9, "arcDeg": 4.0]
        ),
        Oracle(
            id: "progressions-arc-unwraps-past-full-turn",
            source: "Definition: the arc is the distance travelled, not an angle on a circle — at 400 years of life the progressed Sun has passed the natal Sun once, so the arc is ≈ 400 × 0.9856473590852142 and must NOT fold back below 360°",
            inputs: "birth 1990-03-15 12:00 UT, age 400 years",
            precision: "±4° — the mean value; the equation of the centre is periodic, not cumulative, so a longer arc has the same ±2 × 1.92° spread",
            values: ["arcDeg": 394.25894363408565],
            tolerances: ["arcDeg": 4.0]
        ),
        Oracle(
            id: "progressions-converse-arc-is-negative",
            source: "Definition: a converse direction (target before birth) runs the map backwards, so the arc is negative — ≈ −30 × 0.9856473590852142",
            inputs: "birth 1990-03-15 12:00 UT, age −30 years",
            precision: "±4° — mean value, same equation-of-centre spread as the forward 30-year case",
            values: ["arcDeg": -29.569420772556423],
            tolerances: ["arcDeg": 4.0]
        ),
    ]

    static func require(_ id: String) -> Oracle {
        guard let o = all.first(where: { $0.id == id }) else {
            fatalError("unknown oracle id '\(id)'")
        }
        return o
    }
}

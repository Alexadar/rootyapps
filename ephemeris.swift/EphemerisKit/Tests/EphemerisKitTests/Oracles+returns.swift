import Foundation

/// Oracle corpus for return charts (solar, lunar, planetary).
///
/// Mostly **construction** oracles. A return has no published instant to check against here, but
/// it has an exact definition — λ(t) = λ_natal — so the strongest available check is the identity
/// itself, plus the fact that successive returns must reproduce a *published mean period*.
///
/// Every period below is the **tropical** (equinox-of-date) one, because `Ephemeris.longitude` is
/// tropical. Quoting the sidereal period instead would be wrong by exactly one precession step —
/// 12.3 days for Saturn — which is larger than several of these tolerances.
///
/// The tolerances are not aspirations: each is the measured residual of this engine over the
/// stated number of returns, rounded up with margin. They are loose for the outer planets for a
/// physical reason, stated per entry: a *geocentric* passage over a fixed degree is displaced by
/// the retrograde loop (Earth's own orbit seen from outside), and that displacement only cancels
/// once the sample spans several synodic beats.
///
/// Kept in its own file (and its own array) so the shared `Oracles.all` stays a single merge
/// point; an integration pass appends `returnsOracles.all` to it.
enum returnsOracles {
    static let all: [Oracle] = [

        // ── The defining identity ──────────────────────────────────────────────
        Oracle(
            id: "returns-identity-residual",
            source: "Construction: a return is BY DEFINITION the instant at which the body's ecliptic longitude equals the natal longitude, λ(t) = λ_natal (Alan Leo, The Progressed Horoscope; standard in every return-chart treatment since)",
            inputs: "|λ_body(t_return) − λ_natal| over solar, lunar, Mars, Jupiter and Saturn returns, including natal degrees straddling 0° Aries",
            precision: "±1e-6° — 48 halvings of a one-day bracket in RootFinding.refine leave ~3e-10 s of timing error, which even for the Moon's 15°/day is <1e-12°; the observed floor of 7e-9° is the ephemeris function's own double-precision noise, so 1e-6° is ~150× margin and still fails loudly if the root-find ever lands on the 360° wrap instead of the crossing",
            values: ["residualDeg": 0.0],
            tolerances: ["residualDeg": 1e-6]
        ),

        // ── Mean periods: the returns must reproduce published values ──────────
        Oracle(
            id: "returns-tropical-year",
            source: "Meeus, Astronomical Algorithms (2nd ed.), ch. 27 — mean tropical year at epoch 2000.0 = 365.2421897 d (same value in the Astronomical Almanac / USNO)",
            inputs: "mean interval between 40 consecutive solar returns of a 1990-03-15 12:00 UT natal Sun",
            precision: "±0.001 d (86 s) — the Sun here runs on fixed mean elements, so its year is a constant 365.24243 d; the measured departure from the published mean is 0.00024 d (21 s), far inside the ±1′ longitude accuracy of the underlying series",
            values: ["days": 365.2421897],
            tolerances: ["days": 0.001]
        ),
        Oracle(
            id: "returns-tropical-month",
            source: "Meeus, Astronomical Algorithms (2nd ed.), ch. 47 — mean tropical month = 27.321582 d (Astronomical Almanac, same figure)",
            inputs: "mean interval between 80 consecutive lunar returns of a 1990-03-15 12:00 UT natal Moon",
            precision: "±0.02 d over the 80-return mean — individual months here run 27.22–27.47 d because the anomalistic (27.55 d) and evection (31.8 d) beats do not close over 80 months; measured residual 0.0053 d (8 min)",
            values: ["meanDays": 27.321582],
            tolerances: ["meanDays": 0.02]
        ),
        Oracle(
            id: "returns-mars-tropical-period",
            source: "NASA/NSSDC Mars Fact Sheet (public domain) — tropical orbit period 686.973 d",
            inputs: "mean interval between 60 consecutive Mars returns of a 1990-03-15 12:00 UT natal Mars",
            precision: "±0.5 d over the 60-return mean — a single geocentric passage is displaced by up to ~4 months by the retrograde loop and only averages out across the ~8-return synodic beat; measured residual 0.08 d",
            values: ["meanDays": 686.973],
            tolerances: ["meanDays": 0.5]
        ),
        Oracle(
            id: "returns-jupiter-tropical-period",
            source: "NASA/NSSDC Jupiter Fact Sheet (public domain) — tropical orbit period 4330.595 d",
            inputs: "mean interval between 25 consecutive Jupiter returns of a 1990-03-15 12:00 UT natal Jupiter",
            precision: "±12 d over the 25-return mean — the loop displaces a single passage by up to ~250 d and the synodic beat closes only every ~7 returns, so 25 returns leave a few days of residual; measured 4.6 d",
            values: ["meanDays": 4330.595],
            tolerances: ["meanDays": 12]
        ),
        Oracle(
            id: "returns-saturn-tropical-period",
            source: "NASA/NSSDC Saturn Fact Sheet (public domain) — tropical orbit period 29.4248 yr = 10746.94 d (its sidereal orbit period, 29.4571 yr = 10759.22 d, is 12.3 d longer: exactly one precession step, and the wrong quantity for tropical longitudes)",
            inputs: "mean interval between 20 consecutive Saturn returns of a 1990-03-15 12:00 UT natal Saturn",
            precision: "±8 d over the 20-return mean — the loop displaces a single passage by up to ~130 d, but Saturn's synodic beat closes every ~2.4 returns so 20 returns average it out well; measured residual 1.2 d",
            values: ["meanDays": 10746.94],
            tolerances: ["meanDays": 8]
        ),
        Oracle(
            id: "returns-saturn-first-return-age",
            source: "NASA/NSSDC Saturn Fact Sheet (public domain) — tropical orbit period 29.4248 yr; this is the published basis for the astrological 'Saturn return at about age 29½'",
            inputs: "age at the first Saturn return of a 1990-03-15 12:00 UT natal Saturn (first exact hit of the passage)",
            precision: "±1.0 yr — a SINGLE passage, so nothing averages: the geocentric retrograde loop alone moves the first exact hit by up to ~±0.4 yr, and where the passage falls inside the loop depends on the natal chart; measured 29.84 yr, i.e. 0.42 yr from the mean",
            values: ["years": 29.4248],
            tolerances: ["years": 1.0]
        ),
    ]
}

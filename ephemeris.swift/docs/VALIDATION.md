# Validation — Ephemeris Sky

Implements the monorepo policy in [`calculators/VALIDATION.md`](../../calculators/VALIDATION.md):
ground truth comes from an **independent external authority**, never from self-consistency, and
expected numbers live only in the oracle corpus.

## Oracle machinery
- **`EphemerisKit/Tests/EphemerisKitTests/Oracles.swift`** — the corpus. Every entry carries
  `{id, source, inputs, precision, values, tolerances}` and cites its external source.
- **`OracleGuardTests.swift`** — fails the build if any oracle lacks a citation, has a value with
  no tolerance, duplicates an ID, or if **any rendered body has no oracle at all**.
- **`AccuracyTests.swift`** — oracle-backed position accuracy across 1900–2100.

## Measured accuracy (the headline number)

Geocentric apparent ecliptic longitude vs **NASA/JPL Horizons** (public domain), **3,940 samples**:
daily for a year for the fast movers, 6-monthly across 1900–2100 for the rest.

| Body | Worst | Mean | | Body | Worst | Mean |
|---|---|---|---|---|---|---|
| Moon | **6.2′** | 1.3′ | | Jupiter | 2.0′ | 0.5′ |
| Mars | 3.4′ | 0.6′ | | Venus | 1.7′ | 0.5′ |
| Uranus | 2.3′ | 0.7′ | | Pluto | 1.5′ | 0.5′ |
| Saturn | 2.3′ | 0.8′ | | Mercury | 1.1′ | 0.5′ |
| Neptune | 2.1′ | 0.6′ | | Sun | 1.0′ | 0.4′ |

**In one line: better than 7 arcminutes for every body, 1900–2100; typically under 1.5′.**

Honest framing for a practitioner audience: professional desktop software (Swiss Ephemeris, JPL)
agrees with Horizons to sub-arcsecond. This engine is a *compact* series — it will differ from
Solar Fire in the arcminute digit, never in sign, and effectively never in house placement. That
is a deliberate trade for a fully offline, dependency-free, licence-clean engine.

### What this replaced
Before this suite, external validation was **six bodies at a single instant** (2026-06-21) with
tolerances of 0.25°–1.0° (15–60′) — 10–60× looser than the engine's real error, so a serious
regression could have passed. Moon, Uranus, Neptune and Pluto had **no external check at all**.
Tolerances are now measurement-derived (worst case + ~50% margin) and cover all ten bodies.

### Notes and limits
- **Geocentric, tropical, of date** — the astrological convention. **Topocentric parallax is
  deliberately NOT applied.** A pre-measurement review flagged the Moon's ~1° parallax as a bug
  now that houses are computed for a place. It isn't: astrological charts are geocentric by
  definition, and every incumbent (Solar Fire, astro.com, Swiss Ephemeris) defaults to geocentric.
  Adding parallax would make this app *disagree* with the reference tools, not agree with them.
- Mean obliquity, **no nutation** (≤ ~0.005° on the angles) and no ΔT/UT1 correction (≤ 0.9 s).
- **Sun aberration (~0.006° ≈ 0.34″) is not applied** — a considered no-op: the Sun's *measured*
  mean error is 0.4′ and worst 1.0′, so the correction is smaller than the noise it would sit in.
  Not worth perturbing working engine math for.
- Pluto uses Schlyter's dedicated series, documented as valid ~1800–2099. Measured at 1.5′ through
  2100 and asserted by `plutoHoldsToTheEndOfItsDocumentedWindow`; behaviour outside that window is
  **not** validated.
- Houses/angles are exact spherical trig; their inputs (GMST, obliquity) are pinned to Meeus
  Examples 12.a and 22.a. See `HousesTests.swift`.

## House cusps — independent re-derivation (external oracle still outstanding)

Cusps have **no published-chart oracle yet**. Sourcing one was attempted and failed: the worked
example found in search was on a dead domain, a second hit was a commercial API's marketing
sample (not an authority), and Astrodienst's Placidus tables PDF is scanned images with no
extractable text. **No value was invented to fill the gap.**

In its place, `HousesTests.swift` rebuilds the geometry from vectors and asserts the shipped
closed forms land on it — sharing **no code path** with the implementation (no cusp `atan2`, no
`AstroMath`, no house-circle offset derivation):

| Test | What it independently proves |
|---|---|
| `regiomontanusCuspsLieOnTheirHouseCircle` | each cusp lies on the great circle through the horizon's N/S points and the equator point 30k° east — as a plane equation, to 1e-9 |
| `campanusCuspsLieOnTheirPrimeVerticalCircle` | same, for the prime-vertical division |
| `placidusCuspsSatisfyTheirSemiArcDefinition` | hour angle equals the correct fraction of the cusp's own semi-arc, from the definition |
| `kochClosesOnTheMidheaven` | Asc(RAMC − SA_MC) is exactly the MC — the identity that defines Koch |

The Regiomontanus plane test carries a **control assertion**: the same check on a cusp nudged 1°
must fail, so the test cannot silently rubber-stamp a wrong implementation.

These have already earned their keep — the closure identity caught a shipped Koch that was
trisecting the wrong arc (1.53° error at Kyiv), which every structural invariant had passed.

**Still required to satisfy policy:** one published chart (stated date/time/place → published
Placidus cusps) asserted to the arc-minute. Do not invent it.

## Outstanding
- External published cusp oracle (above).
- Incumbent cross-check (one full chart against independent software) remains a human step.

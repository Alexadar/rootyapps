# Astronomy core — positions

**Status:** implemented
**Source:** `EphemerisKit/Sources/EphemerisKit/Astronomy/` — `Ephemeris.swift`, `SunPosition.swift`,
`MoonPosition.swift`, `PlanetPosition.swift`, `JulianDay.swift`, `AstroMath.swift`, `Models/CelestialBody.swift`
**Tests:** `AccuracyTests.swift`, `EphemerisTests.swift` · **Oracle:** `Oracles.swift`

## What it does

Computes geocentric apparent ecliptic longitude for the Sun, Moon and eight planets at any instant,
offline, with no data files and no third-party dependency. Everything else in this app is a
presentation of these numbers — **if this is wrong, everything is wrong, silently.**

Compact analytical series rather than a JPL kernel: a deliberate trade of the last arcsecond for
being fully offline, dependency-free and licence-clean.

## Why anyone pays

Nobody buys "positions." They buy the charts built on them. But this is the function that decides
whether the app can be trusted at all, and it is the only place in the product where being wrong
has a consequence a practitioner can actually detect — a body on the wrong side of a sign boundary
changes every interpretation downstream.

## The oracle

**Kind: external.** The strongest in the repo.

- **Ground truth:** NASA/JPL Horizons (public domain), geocentric apparent `ObsEcLon`
- **Coverage:** 3,940 samples — daily for a year for fast movers, 6-monthly across **1900–2100**
  for the rest
- **Measured worst-case error:** Moon 6.2′ · Mars 3.4′ · Uranus 2.3′ · Saturn 2.3′ · Neptune 2.1′ ·
  Jupiter 2.0′ · Venus 1.7′ · Pluto 1.5′ · Mercury 1.1′ · Sun 1.0′
- **Headline:** better than 7 arcminutes for every body, 1900–2100; typically under 1.5′
- Tolerances are worst-observed + ~50% margin, not round numbers picked for comfort

**`OracleGuardTests` refuses to build if any rendered body has no oracle at all.** That guard is
what stops a new body being added to the UI ahead of its ground truth.

**Honest framing for practitioners:** Swiss Ephemeris and JPL agree with Horizons to sub-arcsecond.
This engine differs from Solar Fire in the arcminute digit — never in sign, effectively never in
house placement. Say that plainly rather than implying parity.

## Suggested design

This function has no UI of its own and should not acquire one. Its two design obligations:

- **The accuracy claim is a selling point and must be stated exactly**, with its span and its
  units. "Arcminute accuracy, 1900–2100, validated against NASA/JPL Horizons" is true and
  checkable. "Professional grade" is not.
- **Range honesty.** Outside 1900–2100 the series degrades and is not oracled. Either refuse dates
  outside it or mark results as unvalidated — never render an unvalidated position identically to
  a validated one.

## Failure modes

- Adding a body to the UI before adding its oracle (guarded — keep the guard)
- Widening a tolerance to make a failing test pass, which converts the suite into decoration
- Extending the date range without extending the validation
- Confusing apparent with geometric position, or true with mean equinox — the corpus pins
  *apparent*, and a mismatch here is a systematic sub-arcminute bias that looks like noise

## Related

[[houses]] · [[natal-chart]] · [[astrocartography]] · [[events]] · [[sidereal-zodiac]]

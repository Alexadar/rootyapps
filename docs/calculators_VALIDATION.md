# Validation Directive & Oracle Machinery (all calculator apps)

Correctness in these niches is the moat. It is judged against **independent external authority, never self-consistency**. This file is the canonical policy; every app references it and ships the machinery below.

## Policy (the directive)
1. **Separate roles.** The source that writes the implementation must not also supply the expected test values. Code from one place; ground-truth numbers from a **published external authority**.
2. **Oracle before code.** Before implementing a formula, pull the canonical worked example and record its inputs + expected outputs:
   - Sight reduction → Nautical Almanac worked examples
   - Thiele-Small / enclosure → standard loudspeaker-design textbook solved cases
   - NEC2 antenna → NEC2/4nec2 validation cases with known patterns
   - Psychrometrics → published psychrometric-chart readings (state pressure/altitude)
   - Rocketry stability → Barrowman's original worked example
   - COGO/geodesy → surveying-textbook traverse examples with published closures
   - Astronomy → Meeus *Astronomical Algorithms* worked examples; USNO/almanac for rise/set
   - Tides → NOAA published station predictions
   - Options → a standard derivatives textbook's solved Black-Scholes case
   - Ballistics(ext.) → published Litz/JBM trajectory tables
3. **Pin tests to those numbers** at the precision the field uses — not to whatever the code emits.
4. **Test what the domain breaks on**, not the happy path: sign conventions (E/W, N/S), antimeridian, altitude/pressure ≠ sea level, transonic/subsonic limits, saturation, canted-fin corrections, end corrections, retrograde/negative rates, year/leap boundaries.
5. **Cross-check against an incumbent** (reference desktop tool or well-reviewed app); flag divergence beyond expected rounding.
6. **No green suite ships without a documented oracle.** If a test's expected value can't be traced to an external source, it proves nothing — mark and fix.

Rule of thumb: a passing test only means the code matches its assumptions. Only an independent oracle tells you the assumptions are right.

## Machinery that makes the policy self-enforcing
The directive is policy; these give it teeth (an automated run can't quietly skip them):

- **Oracle corpus as data** — each `<App>Kit` test target has `Oracles.swift`: a list of `Oracle` entries `{ id, source, inputs, precision, values, tolerances }`. Expected numbers exist **only** here, each tied to a cited external `source`.
- **Enforcement guard** — an `Oracle corpus integrity` suite fails if any oracle has an empty `source`, missing `values`, or a value without a matching `tolerance`; and asserts unique IDs. Reference tests fetch expected values via `Oracles.require(id).matches(key, actual)` — they cannot hardcode a number without a cited oracle.
- **Test taxonomy** (labelled in each suite):
  - *Oracle-backed* — empirical/model outputs vs published numbers (astronomy positions, tide heights, deco stops, CP location…).
  - *Identity/definition* — pure math definitions (FOV = 2·atan(d/2f), √N stacking); their "oracle" is the definition; still cross-checked numerically.
  - *Invariant/physics* — bounds, monotonicity, round-trips, conservation.
- **Human checkpoint** — non-scriptable incumbent cross-checks live in each app's `RELEASE_CHECKLIST.md` as required manual sign-offs before the user green-lights a release. **Nothing uploads**; the user is the final human checkpoint.

## Honest limits
Full lights-out automation is deliberately *not* the goal for consequential tools. A passing suite proves "matches cited oracles," not "safe to bet a part / a fix / a position on." The oracle corpus must be transcribed from real sources (error-prone, itself checked), and incumbent cross-checks stay human-in-the-loop. Green is necessary, not sufficient.

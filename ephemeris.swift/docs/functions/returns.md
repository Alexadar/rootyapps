# Returns

**Status:** implemented
**Source:** `EphemerisKit/Sources/EphemerisKit/Returns/Returns.swift`
**Tests:** `ReturnsTests.swift` · **Oracle:** `Oracles+returns.swift`

## What it does

Finds the instant a body comes back to its exact natal longitude, and builds the chart for that
moment. The solar return — the Sun's return, near each birthday — is the common case; lunar
returns recur monthly, and outer-body returns mark once-a-lifetime events (the Saturn return near
29½).

Implementation is **root-finding**, not table lookup: solve `λ(t) − λ_natal = 0` on a bracketed
interval. `meanPeriodDays` supplies the bracket — Sun 365.242190, Moon 27.321582, Saturn 10746.94,
and so on.

⚠️ **A solar return is not your birthday.** It typically falls hours either side, and can land on
the previous or next calendar day. An implementation that returns midnight on the birth date has
not computed anything.

## Why anyone pays

Solar return charts are a standard annual consultation — a practitioner runs one per client per
year. That is recurring professional use.

Note the search reality: `solar return` returns **zero** autocomplete hits. This has no discovery
value whatsoever and exists purely as depth in the paid tool.

## The oracle

**Kind: construction**, with external anchors on the periods.

| Identity | Must hold |
|---|---|
| Root exactness | at the returned instant, `λ(t) == λ_natal` to ±1e-6° |
| Bracketing | the root lies inside the bracket derived from `meanPeriodDays` |
| Period sanity | consecutive solar returns are ~365.2422 days apart; lunar ~27.3216 — cited to Meeus ch. 27 and NASA/NSSDC fact sheets, both already in the corpus |
| Uniqueness | exactly one root per period — a retrograde-induced triple crossing must be handled explicitly, not averaged |
| Age-zero degeneracy | the 0th solar return is the birth moment itself |
| Location independence | the return *instant* does not depend on location; the return *chart* does |

**What a wrong implementation cannot fake:** the retrograde multiple crossing. For Mercury and
Venus the longitude function is not monotonic, so a naive bisection can converge on the wrong
crossing or miss one. The oracle must include a case where the body stations near its natal degree.

## Suggested design

- **Two dates, both shown:** the exact return instant, and the calendar date it falls on. They
  often disagree, and that disagreement is the point.
- **Return charts render as ordinary wheels** — reuse [[natal-chart]]'s drawing.
- **Relocated returns are standard practice**: the chart is cast for wherever the person will be,
  not where they were born. Offer a location picker, defaulting to the natal place, and make the
  choice visible in metadata.
- A list of upcoming returns across bodies is a good "what's coming" surface — feeds naturally into
  [[events]].

## Failure modes

- Using the birthday instead of the computed instant
- Missing a root when the body stations near its natal degree
- Casting the return chart at the birth location by default without saying so
- Confusing the tropical year with the sidereal or anomalistic year

## Related

[[astronomy-core]] · [[natal-chart]] · [[cross-aspects]] · [[events]] · [[progressions]]

# Natal chart

**Status:** implemented
**Source:** `EphemerisKit/Sources/EphemerisKit/Natal/` — `ChartStore.swift`, `ICloudChartStore.swift`,
`SavedChart.swift`, `Uncertainty.swift`, `JSONValue.swift`
**Tests:** `NatalChartTests.swift`, `ChartStoreTests.swift`, `UncertaintyTests.swift`
**Oracle:** `Oracles.swift`, `Oracles+uncertainty.swift`

## What it does

The birth chart: bodies from [[astronomy-core]], sectors from [[houses]], relationships from
[[aspects]] — assembled for one person, one moment, one place, and **stored**.

Storage is not incidental. A practitioner accumulates client charts over years; the archive is the
reason they stay. Charts sync through the user's own iCloud container — user-owned storage, never
an account, never a server.

`Uncertainty` is the unusual part and the most defensible: birth times are frequently approximate,
and this models what that approximation actually costs. A ±30-minute uncertainty barely moves the
Sun and can move the Ascendant across two signs.

## Why anyone pays

This is the product. `birth chart` returns 10 autocomplete hits with roughly **seven generic** —
the strongest demand measured anywhere in astrology. The paid tier lives here: iPhemeris $29.99
(1,101 ratings) and Time Nomad $8.99 (2,731), both actively maintained, both aimed at working
astrologers rather than horoscope readers.

## The oracle

**Kind: mixed.**

*External:* the assembled chart inherits [[astronomy-core]]'s Horizons-validated positions and
[[houses]]'s sidereal-time checks. No separate transcription is needed for the assembly itself.

*Construction — for uncertainty:*

| Identity | Must hold |
|---|---|
| Monotonicity | widening the time window can never narrow a body's possible range |
| Containment | the nominal chart's values lie inside the uncertainty band, always |
| Rate sanity | ASC moves ≈ 1° per 4 minutes at mid-latitudes; a model claiming otherwise is wrong |
| Differential sensitivity | for a ±30 min window, ASC range ≫ Sun range — by orders of magnitude |
| Zero-width degeneracy | a ±0 window collapses to exactly the nominal chart |

*Construction — for storage:*

| Identity | Must hold |
|---|---|
| Round-trip | save → load → recompute yields byte-identical chart values |
| Schema stability | a chart written by an older version still opens |
| iCloud-unavailable | local fallback path produces the same chart, and says so |

**What a wrong implementation cannot fake:** differential sensitivity. An uncertainty model that
widens everything by the same proportion passes containment and fails this immediately.

## Suggested design

- **The wheel is the identity of the app.** It must be readable at watch size and beautiful at Mac
  size — the same drawing, not two designs.
- **Uncertainty must be visible, not a disclaimer.** When birth time is approximate, the affected
  angles should show their range in the chart itself. A practitioner who cannot see that the
  Ascendant is unreliable will state it confidently to a client.
- **The archive is a first-class surface**, not a save dialog: browse, search, group. This is what
  a professional returns to daily.
- ⚠️ **User-owned storage language only.** iCloud is the user's own disk. Nothing may read as an
  account or a service.
- Rectification (working backwards from events to an exact birth time) is the natural extension
  and is *not* implemented — see [[cross-aspects]] for the machinery it would need.

## Failure modes

- Rendering an uncertain Ascendant identically to a certain one
- Losing chart data on schema change — the archive is the retention asset; corrupting it is fatal
- Treating time zone and DST historically wrong; 1940s wartime time and pre-1970 local rules are
  where this breaks
- Storing derived values instead of inputs, so a corrected engine cannot fix old charts

## Related

[[astronomy-core]] · [[houses]] · [[aspects]] · [[cross-aspects]] · [[chart-analysis]] · [[export]]

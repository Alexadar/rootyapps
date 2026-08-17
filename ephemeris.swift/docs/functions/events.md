# Events — ingresses, lunations, mundane aspects, cycles

**Status:** implemented
**Source:** `EphemerisKit/Sources/EphemerisKit/Events/` — `AstroEvent.swift`, `EventCatalog.swift`,
`EventTimeline.swift`, `Ingresses.swift`, `Lunations.swift`, `MundaneAspects.swift`,
`SynodicCycle.swift`, `RootFinding.swift`, `Models/SynodicEvent.swift`
**Tests:** `EventCatalogTests.swift`, `EventTimelineTests.swift`, `SynodicCycleTests.swift`
**Oracle:** `Oracles.swift`

## What it does

Finds *when* things happen, rather than what is true now. Four families:

- **Ingresses** — a body crossing into a new sign
- **Lunations** — new and full moons, and the quarters
- **Mundane aspects** — aspects between transiting bodies, independent of any birth chart
- **Synodic cycles** — the full conjunction-to-conjunction cycle of a planet pair

`RootFinding.swift` is the shared machinery: every one of these is *solve `f(t) = 0` on a bracket*,
where `f` is a longitude difference. The families differ only in what `f` is.

⚠️ **Non-monotonicity is the hazard throughout.** Retrograde motion means a body can cross the same
degree three times. A root-finder that assumes one crossing per bracket silently loses two of them.

## Why anyone pays

This is the "what's happening" layer — the one thing here with genuine consumer pull.
`retrograde` returns 7 autocomplete hits including a Mercury retrograde tracker; `moon calendar`
returns 10 with about five generic. Neither supports a separate paid record, but both draw people
into a tool that has more inside it.

## The oracle

**Kind: external** where published, **construction** elsewhere.

| Identity | Must hold |
|---|---|
| Ingress exactness | at the returned instant the body is at exactly 0°00′00″ of the sign, ±1e-6° |
| Lunation exactness | Sun–Moon elongation is exactly 0° (new) or 180° (full) |
| Published lunations | new/full moon times are published by NASA and by national almanacs — transcribe them; this is genuine external ground truth |
| Synodic period | consecutive conjunctions of a pair are separated by the published synodic period — NASA/NSSDC fact sheets are already cited in this corpus for Saturn |
| Multiplicity | a retrograde triple ingress returns **three** events, not one |
| Ordering | a timeline is strictly ordered, with no duplicates and no dropped events at bracket seams |
| Bracket completeness | every root inside the requested window is found — the check is subdividing the bracket and getting the same set |

**What a wrong implementation cannot fake:** the triple crossing. It is the single most common
defect in event engines and the reason `RootFinding` deserves its own oracle rather than being
tested only through its callers.

## Suggested design

- **A timeline is the natural form** — vertical, scrollable, dated, with today anchored.
- **Filter by family and by body.** All events at once is noise; a Mercury-only or lunation-only
  view is what people actually want.
- **Widgets and notifications belong here** more than anywhere else in the app — this is the only
  function whose value is time-sensitive.
- ⚠️ **Show retrograde multiplicity honestly.** Three ingresses across five months is a real and
  interpretively significant pattern; collapsing it to one is a data loss the user cannot detect.
- Feeds [[export]] via `TimelineExporter` — practitioners want these dates in their calendars.

## Failure modes

- Assuming one root per bracket
- Losing or duplicating events at the seam between adjacent brackets
- Reporting event times in local time without marking the zone
- Confusing mean with true lunation times

## Related

[[astronomy-core]] · [[cross-aspects]] · [[returns]] · [[export]] · [[planetary-hours]]

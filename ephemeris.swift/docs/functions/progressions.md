# Progressions

**Status:** implemented
**Source:** `EphemerisKit/Sources/EphemerisKit/Progressions/Progressions.swift`
**Tests:** `ProgressionsTests.swift` · **Oracle:** `Oracles+progressions.swift`

## What it does

Symbolic time. Two systems, both implemented:

- **Secondary progressions** — the day-for-a-year key. The chart for the 30th day after birth is
  read as the chart for the 30th year. Progressed positions are ordinary positions computed at a
  mapped date, so accuracy inherits directly from [[astronomy-core]].
- **Solar arc** — every body advances by the same amount the Sun has progressed. Simpler, and it
  moves the slow bodies that secondary progressions barely touch.

Progressed charts are then read against the natal chart via [[cross-aspects]].

## Why anyone pays

A serious practitioner technique with no consumer analogue. `progressions` as a search term is
**hijacked** — it returns guitar chord progressions and a credit union. Zero discovery value,
real professional value. Depth inside the tool.

## The oracle

**Kind: construction**, with an external anchor on the year length.

| Identity | Must hold |
|---|---|
| Day-for-year key | progressed date == birth date + (elapsed years × 1 day), to the second |
| Year length | uses the **mean tropical year**, cited to Meeus ch. 27 — already in the corpus — not 365 or 365.25 |
| Solar arc definition | arc == progressed Sun longitude − natal Sun longitude, on the shorter arc |
| Uniformity | in solar arc, **every** body advances by exactly the same amount, no exceptions |
| Zero-elapsed degeneracy | at age 0, the progressed chart equals the natal chart exactly |
| Position inheritance | a progressed position equals a position computed directly at the mapped date — this is what ties progressions to the Horizons-validated engine |

**What a wrong implementation cannot fake:** the year length. Using 365.25 instead of 365.2422
drifts by about a day per century of progressed time — invisible at age 20, obviously wrong at 80.

## Suggested design

- **Reuse the transit surface entirely.** Progressed-to-radix is a cross-aspect set with a
  different source chart; it needs no new screen. See [[cross-aspects]].
- **Show the mapped date.** "Progressed to 2026-08-17 (= 1990-03-16 actual)" — practitioners check
  this, and it makes the technique legible rather than magical.
- Offer both systems side by side; they answer differently and practitioners use both.
- A timeline of progressed aspect exactness is the natural extension — see [[events]] for the
  root-finding.

## Failure modes

- 365 or 365.25 instead of the mean tropical year
- Progressing the angles by the wrong method (several conventions exist; pick, document, oracle)
- Solar arc applied to some bodies but not the angles
- Presenting a progressed chart without marking it as progressed

## Related

[[astronomy-core]] · [[cross-aspects]] · [[natal-chart]] · [[returns]] · [[events]]

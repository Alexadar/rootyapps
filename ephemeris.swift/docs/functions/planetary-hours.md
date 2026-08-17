# Planetary hours

**Status:** engine implemented and oracled — **no UI**; the hour ring below is not built
**Lives in:** `EphemerisKit/Sources/EphemerisKit/Hours/PlanetaryHours.swift`, over the shared
`Astronomy/RiseSet.swift` primitive built for it
**Tests:** `PlanetaryHoursTests.swift` (12) · **Oracle:** `Oracles+hours.swift` (5 entries)
**Depends on:** [[astronomy-core]] (sunrise/sunset), [[houses]] (observer location)

## What it does

Divides the interval from sunrise to sunset into **twelve unequal "hours"**, and the interval from
sunset to the next sunrise into twelve more. Each hour is ruled by a planet, assigned in the
**Chaldean order** — Saturn, Jupiter, Mars, Sun, Venus, Mercury, Moon — cycling continuously.

The first hour of the day is ruled by the planet that rules that weekday: Sun on Sunday, Moon on
Monday, Mars on Tuesday, and so on. From there the sequence simply advances. The whole system is a
lookup once you have sunrise and sunset for a place and date.

Two properties fall out of the definition and are the reason it is interesting to compute rather
than tabulate:

- **Hours are not 60 minutes.** A summer daytime hour at high latitude can exceed 90 minutes while
  the corresponding night hour shrinks below 30.
- **The 25th hour does not exist.** Day and night each get exactly twelve, so the sequence resets
  at sunrise, not at midnight.

## Why anyone pays

Measured: `planetary hours` returns 10 autocomplete hits with roughly five generic — real demand,
nine apps in the field. But the only paid pure-play sits at $4.99 with **one** rating, and the
paid app that actually sells (Time Nomad, $8.99, 2,731 ratings) is a full chart tool that includes
hours among many things.

**Read this as a feature, not a product.** It earns its place inside a chart tool and does not
support a separate record.

## The oracle

**Kind: construction**, with one external anchor.

There is no authoritative published table of planetary hours for arbitrary places and dates —
every source computes them the same way from sunrise and sunset. So the oracle pins the identities:

| Identity | Must hold |
|---|---|
| Twelve day hours span exactly sunrise → sunset | `Σ dayHourDurations == sunset − sunrise` to ±1e-6 s |
| Twelve night hours span sunset → next sunrise | same, on the night interval |
| Day hour 1 ruler == the weekday ruler | Sunday→Sun, Monday→Moon, Tuesday→Mars, Wednesday→Mercury, Thursday→Jupiter, Friday→Venus, Saturday→Saturn |
| Rulers advance in Chaldean order without a break across the day/night boundary | hour 13 follows hour 12 in sequence |
| Hour 1 of the *next* day is the next weekday's ruler | the 24-hour cycle closes — this is the check that catches an off-by-one |

**External anchor:** at the equinox on the equator, every hour is exactly 60 minutes. That is a
real number from spherical geometry, not from us, and it fails loudly if the unequal-hour division
is wrong.

**Cite:** the Chaldean order and the weekday-ruler rule are classical — Ptolemy, *Tetrabiblos*
I.21 is already cited in this repo's corpus for dignities and covers the planetary week; Vettius
Valens is the usual source for the hours themselves.

**What a wrong implementation cannot fake:** the 24-hour closure. An implementation that assigns
rulers by clock hour rather than by unequal hour drifts out of the weekday sequence within a
single day and can never satisfy the closure check.

## Suggested design

A **clock**, not a list. The strength of this function is that it is *now*-shaped.

- A ring showing the current hour, its ruler, and how much of it remains — the ring is unequal by
  construction, so segment widths must visibly differ. A design that draws twelve equal segments
  is lying about the mathematics.
- Tap forward and back through the sequence without leaving the ring.
- Day and night halves visually distinct; the sunrise/sunset boundary is the only fixed point.
- **A widget is the natural home** — this is a glanceable value that changes several times a day.
- Latitude honesty: above the Arctic and Antarctic circles, sunrise or sunset can fail to occur.
  Design the "no sunrise today" state deliberately; do not fabricate an hour.

## Failure modes

- Assigning by clock hour instead of unequal hour — the classic wrong implementation
- Resetting at midnight rather than sunrise
- Silently producing hours on polar days when there is no sunrise to divide
- Using civil twilight instead of true sunrise; pick one, document it, oracle it

## Related

[[astronomy-core]] · [[houses]] · [[dignities]] (shares the Chaldean order) · [[events]]

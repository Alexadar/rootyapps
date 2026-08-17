# Function docs — Ephemeris Sky

One file per calculable function. Each is **self-describing**: it states what the function is,
how it is proven correct, and how it should look — without requiring you to have read the others.

Links between files are **weak**: a wiki-style link may point at a document that does not exist yet.
That is a marker for work, not a broken reference.

⚠️ **These files do not carry visual authority.** Tokens, type, the watch brief and the shipped
look live in `design_handoff_nebula/`; existing screens live in `ephemeris/*View.swift`. See
[`../ASTROLOGY_LINKS.md`](../ASTROLOGY_LINKS.md) §0 before designing anything.

## Why these files exist

The app grew past the point where one person holds it all. Knowledge that lived in a single
build prompt now lives here, per function, so a session can be handed exactly the slice it needs.

## The rule that makes a function shippable

> **A function ships only when it has an oracle, and the oracle cites an authority outside this
> repository.**

Ground truth never comes from our own output. Self-consistency proves nothing — a wrong engine
agrees with itself perfectly.

## Oracle kinds

Every oracle declares which kind it is. Both are legitimate; they fail differently.

| Kind | Ground truth is | Use when | Example |
|---|---|---|---|
| **External** | numbers transcribed from a published authority | someone else has already computed and published the answer | planetary longitudes vs NASA/JPL Horizons |
| **Construction** | a defining identity that must hold exactly | no one publishes the numbers, but the definition pins them | an astrocartography MC line is *exactly* where hour angle = 0 |

A construction oracle is not a weaker oracle. *"Reproduce hour angle 0 at every sampled point of
the line"* cannot be satisfied by a wrong implementation, because the line is completely
determined by that identity.

## Corpus mechanics

- **`EphemerisKit/Tests/EphemerisKitTests/Oracles.swift`** and its `Oracles+*.swift` companions
  hold the corpus. Every entry carries `{id, source, inputs, precision, values, tolerances}`.
- **`OracleGuardTests.swift`** fails the build if any oracle lacks a citation, carries a value with
  no tolerance, duplicates an ID, or if a rendered body has no oracle at all.
- Tolerances are **measurement-derived** — worst observed error plus roughly 50% margin. A
  tolerance loose enough to hide a regression is worse than no test.
- Authorities cited so far: NASA/JPL Horizons · Meeus, *Astronomical Algorithms* (2nd ed.) ·
  Ptolemy, *Tetrabiblos* · Ebertin, *The Combination of Stellar Influences* · Robert Hand,
  *Planets in Composite* · Marc Edmund Jones · NASA/NSSDC fact sheets.

See [`../VALIDATION.md`](../VALIDATION.md) for the measured accuracy headline, and
[`../ASTROLOGY_LINKS.md`](../ASTROLOGY_LINKS.md) for the dependency map, input gates and surface map.

## Index

### Engine implemented and oracled — no UI yet
The maths, the corpus entries and the tests exist and are green; every "Suggested design" section
in these three is still unbuilt, so nothing of this reaches a user yet.

| Function | One line |
|---|---|
| [[planetary-hours]] | Chaldean-order hour rulers between sunrise and sunset |
| [[sidereal-zodiac]] | ayanamsa offset — the same chart read in the sidereal frame |
| [[moon-phases]] | lunar calendar surface over existing lunation maths — **gate 0, no birth data** |

### Implemented
| Function | One line |
|---|---|
| [[astronomy-core]] | positions of Sun, Moon and planets — everything else depends on this |
| [[houses]] | dividing the local sky into twelve, several ways |
| [[natal-chart]] | the birth chart, its storage, and its uncertainty |
| [[astrocartography]] | planetary angle lines drawn on a world map |
| [[aspects]] | angular relationships inside one chart |
| [[cross-aspects]] | one chart against another — transits, synastry, progressed-to-radix |
| [[midpoints-composite]] | half-sums, and the relationship chart built from them |
| [[progressions]] | symbolic time — secondary progressions and solar arc |
| [[returns]] | the moment a body comes back to its natal degree |
| [[dignities]] | a body's condition by sign — the classical scoring |
| [[events]] | ingresses, lunations, mundane aspects, synodic cycles |
| [[chart-analysis]] | shape, emphasis and distribution across a whole chart |
| [[export]] | getting the results out in a form other tools accept |

## Document template

Each file carries, in this order: **Status · Source · Tests · What it does · Why anyone pays ·
The oracle · Suggested design · Failure modes · Related.**

## Deliberately not documented here

**App and platform plumbing**, which carries no oracle and is not a paid function:
`LaunchOverride.swift` · `SharedStore.swift` · `WatchBridge.swift`, plus the widget, watch and
UI targets. If one of these grows a rule worth proving, it earns a file then — not before.

**Niches measured and rejected**, kept here so they are not re-proposed: Human Design (39 apps,
**zero** paid), numerology (leaders all free), I Ching, dream dictionary, biorhythm, horary,
Chinese astrology. Each has demand; none has a paying buyer.

> **Moon calendar was on that list and has been removed.** The re-measurement on 2026-08-17
> (recorded in [[moon-phases]]) found the opposite of the original read: Mooncast at $3.99 with
> 3,619 ratings and My Moon Phase Pro at $3.99 with 2,581 — roughly 6,200 *paid* ratings, the only
> consumer astro niche in this table with a working paid model, and gate-0 besides. The point of a
> rejected list is to stop re-litigating settled questions, which makes a stale entry in it more
> expensive than no list at all: it would have talked someone out of the one measured winner.

**Known engine gaps, unproposed:** harmonics, fixed stars, eclipses. No symbol exists for any of
them. They are legitimate extensions of [[astronomy-core]] but were not measured, so no file
asserts they are worth building.

# Midpoints and composite charts

**Status:** implemented
**Source:** `EphemerisKit/Sources/EphemerisKit/Midpoints/` — `Midpoints.swift`, `Composite.swift`
**Tests:** `MidpointsTests.swift` · **Oracle:** `Oracles+midpoints.swift`

## What it does

A **midpoint** is the half-sum of two longitudes — the point equidistant between two bodies. On a
circle, every pair has **two** midpoints, 180° apart, and choosing between them is the entire
difficulty: the convention is the *shorter arc*.

A **composite chart** applies this to two whole charts, producing a third chart of the
relationship itself. Not either person — the pairing.

## Why anyone pays

Midpoint work (Ebertin's system) is a serious practitioner technique, and composite charts are how
relationship astrology is actually done at the professional tier. Neither has independent search
demand — `compatibility astrology` returns a single hit, and it is an app name. This is depth
inside the paid tool, not a discovery surface.

## The oracle

**Kind: external** — unusually well-served, and already cited in the corpus.

| Source | What it pins |
|---|---|
| **Ebertin, *The Combination of Stellar Influences*** | the half-sum definition; shorter-arc convention; behaviour at exact opposition |
| **Robert Hand, *Planets in Composite*** | composite construction from two charts |

Identities the corpus pins:

| Identity | Must hold |
|---|---|
| Half-sum | midpoint of a and b is (a+b)/2 on the shorter arc |
| Shorter arc | for 350° and 10°, the midpoint is **0°**, not 180° — the naive average is exactly wrong here |
| Symmetry | midpoint(a,b) == midpoint(b,a) |
| Opposition degeneracy | at exactly 180° apart both midpoints are equally valid — the corpus pins the tie-break so it is deterministic rather than accidental |
| Composite closure | a composite chart's bodies are the midpoints of the corresponding pairs, every one |

**What a wrong implementation cannot fake:** the 350°/10° case. Naive `(a+b)/2` gives 180° — the
precise opposite of correct. This single check separates working code from plausible code.

## Suggested design

- **Midpoint trees** are the practitioner convention: a body, and everything whose midpoint falls
  on it within a tight orb. Dense and text-heavy by nature; do not try to make it a wheel.
- **Composite charts render as a normal wheel** — reuse [[natal-chart]]'s drawing entirely. It is a
  chart; treat it as one.
- ⚠️ **Label a composite as a composite, permanently.** It has no birth moment and no location in
  the ordinary sense; a user who mistakes it for a natal chart will read it wrongly. Metadata must
  survive export.
- Midpoint orbs are much tighter than aspect orbs (typically ≤ 1.5°). Do not inherit the aspect
  default.

## Failure modes

- Naive arithmetic mean across the 0° wrap
- Non-deterministic tie-break at exact opposition
- Reusing aspect orbs, which floods the tree with noise
- Losing the "this is a composite" marker on save or export

## Related

[[aspects]] · [[cross-aspects]] · [[natal-chart]] · [[chart-analysis]]

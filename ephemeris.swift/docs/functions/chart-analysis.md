# Chart analysis — shape and emphasis

**Status:** implemented
**Source:** `EphemerisKit/Sources/EphemerisKit/Analysis/ChartAnalysis.swift`
**Tests:** `ChartAnalysisTests.swift` · **Oracle:** `Oracles+analysis.swift`

## What it does

Describes a chart **as a whole** rather than body by body: how the ten bodies are distributed
around the circle, and what that distribution is called.

The classical scheme is Marc Edmund Jones's seven planetary patterns — **splash, bundle, bowl,
locomotive, seesaw, bucket, splay** — each defined by a geometric rule about the largest empty arc
and how the occupied portion is filled. Alongside them sit the simpler emphasis counts: by element,
by modality, by hemisphere, by quadrant.

This is pattern recognition over a set of angles. No new astronomy — but a real classification
problem with genuine edge cases, because a chart can sit exactly on the boundary between two shapes.

## Why anyone pays

It is the "what is this chart *like*" summary a practitioner gives in the first minute of a
consultation. Consumer apps rarely implement it because the definitions are fussy and easy to get
subtly wrong.

## The oracle

**Kind: external.**

| Source | What it pins |
|---|---|
| **Marc Edmund Jones, *The Guide to Horoscope Interpretation* (1941)** | the seven pattern definitions and their thresholds — already cited twice in this repo's corpus, including the splash definition |

| Identity | Must hold |
|---|---|
| Pattern definitions | each shape's threshold matches Jones's stated rule — e.g. bundle within 120°, bowl within 180° |
| Exhaustiveness | every possible chart classifies as exactly one pattern; none falls through |
| Determinism | a chart on a threshold boundary resolves the same way every time, and the tie-break is pinned |
| Count closure | element counts sum to the body count; modality counts likewise; hemisphere counts likewise |
| Rotational sensitivity | a bundle rotated 90° is still a bundle — shape is orientation-independent |
| Hemisphere dependence | hemisphere and quadrant emphasis *do* depend on the angles, so they change with birth time while shape does not |

**What a wrong implementation cannot fake:** exhaustiveness combined with determinism. An engine
with a gap between two thresholds returns nothing for some charts; one with an overlap returns
different answers depending on evaluation order.

## Suggested design

- **One line at the top of the chart**, not a screen. "Bucket, Mars handle · fire-heavy · 8 of 10
  below the horizon" is the whole deliverable.
- **Draw the shape on the wheel** — highlight the empty arc, mark the handle of a bucket. The
  pattern is geometric and should be seen, not just named.
- ⚠️ **Say when a chart is borderline.** A chart 1° from being a bowl instead of a bucket should be
  labelled as such; a confident single word there is misleading.
- Element and modality counts want a compact tally, not prose.

## Failure modes

- Threshold gaps or overlaps between pattern definitions
- Order-dependent tie-breaks on boundary charts
- Including or excluding the outer bodies inconsistently — Jones wrote for a ten-body chart, and
  adding points changes every threshold
- Treating hemisphere emphasis as birth-time-independent

## Related

[[natal-chart]] · [[aspects]] · [[dignities]] · [[midpoints-composite]]

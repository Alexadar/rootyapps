# Aspects

**Status:** implemented
**Source:** `EphemerisKit/Sources/EphemerisKit/Models/Aspect.swift`
**Tests:** `AspectsTests.swift`, `AspectPrecedenceTests.swift` · **Oracle:** `Oracles.swift`

## What it does

Finds angular relationships between two bodies **inside one chart**. Conjunction 0°, opposition
180°, trine 120°, square 90°, sextile 60°, plus minor aspects. A pair counts as aspected when their
separation falls within an **orb** of the exact angle.

Two subtleties carry the whole function:

- **Separation is circular.** The distance between 350° and 10° is 20°, not 340°. The corpus cites
  this explicitly — *"standard metric on the circle group ℝ/360ℤ: d(a,b) = min(|a−b| mod 360, …)"*.
- **Precedence.** When two aspects both fit within orb, one wins. That rule is why
  `AspectPrecedenceTests` exists as a separate file — it is a real source of quiet disagreement
  between engines.

Inside one chart the two bodies are **interchangeable**: Sun square Moon and Moon square Sun are
the same statement. That is exactly what distinguishes this type from [[cross-aspects]].

## Why anyone pays

Aspects are what a chart *says*. A wheel without them is a diagram; with them it is a reading.
Bundled into the $9–30 professional tier — never sold alone.

## The oracle

**Kind: construction**, with published orb conventions as external anchors.

| Identity | Must hold |
|---|---|
| Circular metric | d(350°, 10°) == 20° — and d(a,b) == d(b,a) for all pairs |
| Exactness | separation exactly equal to the aspect angle yields orb 0 |
| Orb boundary | separation at exactly the orb limit is included; one ULP beyond is excluded — pick the convention, pin it |
| Symmetry | swapping the two bodies changes nothing at all |
| Precedence determinism | the same pair at the same separation always resolves to the same aspect, never order-dependent |
| Applying vs separating | sign follows relative motion, and reverses correctly through retrograde |

**External anchor:** classical orb tables — Ptolemy, *Tetrabiblos* is already cited in this repo's
corpus and covers the classical aspect set; modern orb conventions differ and should be named
wherever a default is chosen.

**What a wrong implementation cannot fake:** the wrap. An engine using naive `abs(a − b)` passes
every test where both bodies sit mid-circle and fails silently across 0° Aries — which is where a
great many charts actually have bodies.

## Suggested design

- **Draw them in the wheel**, as lines across the centre. That is the convention and departing from
  it costs recognition for no gain.
- **Orb is a setting practitioners argue about.** Expose it; default it; show which set is active
  in chart metadata.
- Distinguish applying from separating — a tightening aspect means something different from a
  loosening one, and most consumer apps do not show it. That is a cheap professional signal.
- Tight aspects deserve more visual weight than wide ones. Never rely on colour alone.

## Failure modes

- Naive absolute difference instead of circular distance
- Orb boundary treated inconsistently between detection and display
- Precedence resolved by array order, so results depend on body enumeration
- Applying/separating sign not reversing during retrograde motion

## Related

[[cross-aspects]] · [[midpoints-composite]] · [[natal-chart]] · [[chart-analysis]] · [[events]]

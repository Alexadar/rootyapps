# Cross-aspects — transits, synastry, progressed-to-radix

**Status:** implemented
**Source:** `EphemerisKit/Sources/EphemerisKit/Models/CrossAspect.swift`
**Tests:** `CrossAspectTests.swift` · **Oracle:** `Oracles+crossaspects.swift`

## What it does

An aspect between a body in **one** position set and a body in **another**. One type serves three
functions that are the same mathematics with different second charts:

| Function | Set A | Set B |
|---|---|---|
| **Transits** | today's sky | the natal chart |
| **Synastry** | person A's chart | person B's chart |
| **Progressed-to-radix** | the progressed chart | the natal chart |

⚠️ **The sides are not interchangeable**, and this is the design decision the source file exists to
protect. Transiting Sun square natal Moon and transiting Moon square natal Sun are *different
statements about different charts*. A type that forgets which side a body came from cannot tell
them apart — which is precisely why this is a separate type from [[aspects]], where the two bodies
genuinely are symmetric.

## Why anyone pays

This is the function practitioners use *daily*. A natal chart is computed once; transits are
consulted every morning. Bundled into the $9–30 tier — iPhemeris and Time Nomad both ship all three.

`transits` returns 7 autocomplete hits with some generic; `synastry` returns only 4 and mostly app
names. Neither supports a separate record. Both are indispensable inside the tool.

## The oracle

**Kind: construction**, inheriting external validity from [[astronomy-core]].

| Identity | Must hold |
|---|---|
| Asymmetry | swapping the two sets produces a *different* result set, not a reordered one |
| Side preservation | every returned aspect knows which set each body came from, after any sort or filter |
| Self-consistency | cross-aspecting a chart with itself reproduces its own [[aspects]] exactly |
| Circular metric | inherited — d(350°, 10°) == 20° |
| Orb parity | the same orb rules apply as in-chart, unless deliberately configured otherwise |
| Exactness timing | the instant a transit is exact must agree with a root-find on the separation function — see [[events]] |

**What a wrong implementation cannot fake:** the self-consistency check. Cross-aspecting a chart
against itself must yield its own aspect set — an implementation that has confused the sides
produces duplicates or drops the diagonal.

## Suggested design

- **Three surfaces, one engine.** Transits, synastry and progressions should feel like different
  screens, not one screen with a mode switch — the questions are unrelated even though the maths
  is shared.
- **Transits want a timeline**, not a list: what is exact today, what is approaching, what is
  separating. See [[events]] for the root-finding that makes "exact at 14:22" possible.
- **Synastry wants a grid** — person A's bodies down, person B's across — plus the wheel-on-wheel
  biwheel. Both conventions exist; practitioners expect both.
- ⚠️ **Always label which side is which, everywhere.** "Sun square Moon" is ambiguous and therefore
  wrong. "Transiting Sun square natal Moon" is the minimum.
- Progressed-to-radix reuses the transit UI with a different source chart — no new design needed.

## Failure modes

- Losing side information in a sort, filter or `Set` operation
- Rendering a cross-aspect with in-chart phrasing, so the reader cannot tell direction
- Applying natal orbs to transits without saying so (practitioners commonly use tighter transit orbs)
- Treating the Moon's speed as constant when computing exactness

## Related

[[aspects]] · [[natal-chart]] · [[progressions]] · [[returns]] · [[events]] · [[midpoints-composite]]

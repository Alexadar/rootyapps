# Essential dignities

**Status:** implemented
**Source:** `EphemerisKit/Sources/EphemerisKit/Dignities/` — `EssentialDignities.swift`,
`DignityScore.swift`
**Tests:** `DignitiesTests.swift` · **Oracle:** `Oracles+dignities.swift`

## What it does

Scores how well-placed a body is by sign, using the classical scheme: **rulership, exaltation,
triplicity, term, face**, and the negatives — **detriment** and **fall**. A body in its own sign is
strong; in the opposite sign, weak. The scoring sums to a number practitioners read directly.

This is the most *purely textual* function in the app. The values are not computed from astronomy —
they are transcribed from a 2nd-century source and applied by table lookup. The only computation is
finding which sign, term and face a longitude falls in.

The Chaldean order appears here too, in the faces — the same sequence that would drive
[[planetary-hours]].

## Why anyone pays

Traditional and Hellenistic astrology have grown substantially, and dignity scoring is central to
both. It is also a genuine differentiator: many consumer apps omit it entirely because it requires
transcribing tables correctly rather than calling a library.

## The oracle

**Kind: external.** The strongest kind, and unusually clean for an esoteric function — the source
is a published text with explicit numbers.

| Source | What it pins |
|---|---|
| **Ptolemy, *Tetrabiblos* I.21 (Robbins, Loeb 1940)** | the term boundaries and the degree totals — already cited in this repo's corpus |

The corpus entry pins **the degree totals Ptolemy states**, which is the right check: the terms
divide each sign into five unequal spans, and every sign's spans must sum to exactly 30°. A
transcription error anywhere breaks that sum.

| Identity | Must hold |
|---|---|
| Term closure | each sign's five term spans sum to exactly 30° |
| Ptolemaic totals | each planet's total term degrees across the zodiac match the published figure |
| Rulership completeness | every sign has exactly one ruler; every planet rules its classical signs |
| Detriment/fall symmetry | detriment is opposite rulership; fall is opposite exaltation — always |
| Face closure | 36 faces of 10° each, in Chaldean order, covering the circle exactly once |
| Boundary behaviour | a longitude exactly on a term boundary resolves deterministically |

**What a wrong implementation cannot fake:** the degree totals. A single mis-transcribed term
boundary shifts a planet's total and fails immediately — which is why that is the check chosen.

## Suggested design

- **A compact table or a per-body badge in the wheel**, not a separate screen. It is an annotation
  on bodies you are already showing.
- Show the **components**, not just the sum. "+5 rulership, +3 triplicity, −5 detriment" is what a
  practitioner reasons with; a bare total is not.
- Traditional/modern rulership is a real schism (does Mars still rule Scorpio?). Make it a setting,
  show which is active.
- ⚠️ **Do not editorialise the score.** "Weak" is a technical term here, not a judgement, and copy
  that reads as a verdict on the person is both wrong and off-putting.

## Failure modes

- Transcription slips in the term tables — the reason the degree-total check exists
- Modern rulers silently mixed into a traditional scheme
- Off-by-one at sign and term boundaries (0° vs 30°)
- Applying dignities to points that do not have them (nodes, angles) without saying so

## Related

[[natal-chart]] · [[aspects]] · [[chart-analysis]] · [[planetary-hours]] · [[sidereal-zodiac]]

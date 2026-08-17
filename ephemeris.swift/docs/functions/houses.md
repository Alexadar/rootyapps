# Houses

**Status:** implemented
**Source:** `EphemerisKit/Sources/EphemerisKit/Houses/` — `Houses.swift`, `HouseSystem.swift`,
`SiderealTime.swift`, `GeoLocation.swift`
**Tests:** `HousesTests.swift` · **Oracle:** `Oracles.swift`

## What it does

Divides the local sky into twelve sectors as seen from a specific place at a specific moment, and
places each body in one. Requires latitude, longitude and exact time — this is the only part of a
chart that depends on *where you were*, which is why birth time uncertainty hurts here first.

Several systems exist and disagree. Placidus divides time, Whole Sign divides by sign, Koch and
Campanus divide space differently again. **They are not approximations of one another** — a body
can sit in the 9th house Placidus and the 10th Whole Sign, and both are correct within their own
definition.

Two angles matter more than the cusps: the **Ascendant** (ecliptic rising on the eastern horizon)
and the **Midheaven** (ecliptic crossing the meridian). Those two are system-independent and are
what [[astrocartography]] draws.

## Why anyone pays

House placement is where the paid chart tools differentiate. `natal chart – placidus` appears as a
distinct autocomplete hit, which means practitioners search by system. Supporting several systems
credibly is table stakes for the $9–30 tier.

## The oracle

**Kind: mixed.**

*External:* local sidereal time at a known instant and longitude is published — Meeus,
*Astronomical Algorithms* ch. 12 gives the formula and worked examples with numbers to transcribe.

*Construction:* the cusp definitions pin themselves.

| Identity | Must hold |
|---|---|
| MC ≡ ecliptic point on the meridian | its hour angle is 0 to ±1e-6° |
| ASC ≡ ecliptic point rising | its altitude is 0, and it is on the eastern side |
| Opposition closure | cusp(n+6) == cusp(n) + 180° for every n, exactly |
| Whole Sign degeneracy | in Whole Sign, every cusp is 0° of its sign — a system that cannot reproduce this trivial case has a sign-boundary bug |
| Equator degeneracy | at latitude 0, Placidus and Equal converge; divergence there means the quadrant division is wrong |
| Ordering | cusps increase monotonically around the circle with no crossing |

**What a wrong implementation cannot fake:** the polar limit. Above roughly 66°N, Placidus cusps
become undefined for parts of the year. An implementation that always returns twelve neat cusps at
70° latitude is fabricating.

## Suggested design

- **System is a chart property, shown in chart metadata**, not a hidden global preference. A
  practitioner comparing two charts must see which system each used.
- Default to one system, expose the rest without ceremony; do not make the user choose on first
  run.
- ⚠️ **Design the high-latitude failure.** When a system is undefined for the location, say so and
  offer Whole Sign, which is always defined. Do not silently substitute.
- The angles (ASC/MC) deserve visual weight above the intermediate cusps — they carry more
  interpretive load and they are the system-independent ones.

## Failure modes

- Treating house systems as interchangeable or "roughly the same"
- Applying the wrong sign to west longitude — a whole-chart error that looks plausible
- Ignoring the equation of time or using mean instead of apparent sidereal time
- Returning cusps at polar latitudes where the system is undefined

## Related

[[astronomy-core]] · [[natal-chart]] · [[astrocartography]] · [[aspects]] · [[sidereal-zodiac]]

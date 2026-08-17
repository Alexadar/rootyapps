# Astrocartography

**Status:** implemented
**Source:** `EphemerisKit/Sources/EphemerisKit/Astrocartography/AstroCartography.swift`
**Tests:** `AstroCartographyTests.swift` · **Oracle:** `Oracles+astrocarto.swift`

## What it does

Answers *where on Earth* rather than *what am I like*. For each body in a natal chart, draws the
lines on the globe where that body was exactly on an angle at the birth moment:

| Line | The body was |
|---|---|
| **MC** | culminating — directly overhead |
| **IC** | directly underfoot |
| **AC** | rising on the eastern horizon |
| **DC** | setting on the western horizon |

Ten bodies × four angles = forty lines across a world map. MC/IC lines are meridians — straight
verticals. AC/DC lines are curves, and they behave badly at high latitude: when a body's
declination exceeds the circumpolar limit for a latitude, it never rises there and **the line
genuinely does not exist.**

## Why anyone pays

It is decision support for moving house or country — a researched, expensive, high-stakes choice,
which is a completely different buying context from a daily horoscope.

Measured: ten apps in the entire field, the thinnest in astrology. Paid precedent is iPhemeris at
**$29.99** (1,101 ratings), which ships it inside a full chart tool. The only pure-play paid
competitor has **zero** ratings; the free ones sit at 180, 133, 17 and 5.

⚠️ **That is why this is a feature, not a second app.** A practitioner will not buy a separate
product and re-enter birth data to see their lines.

## The oracle

**Kind: construction**, with one external anchor — and the reasoning is worth preserving.

No published table of A\*C\*G line longitudes exists to transcribe. Solar Fire and Astrodienst
print maps, not numbers, and their bodies carry true ecliptic latitude which this Kit's position
engine does not publish. So the oracle pins **the definition** instead:

| Identity | Must hold |
|---|---|
| MC line | hour angle `H = LST − α` is **0** at every sampled point, ±1e-6° |
| IC line | hour angle is **180°** |
| AC/DC lines | body altitude is **0** at every sampled point |
| AC vs DC | eastern versus western side of the meridian — the two are not interchangeable |

**This is not a weaker oracle.** An astrocartography line is *completely determined* by "hour
angle 0" and "altitude 0". Reproducing those two numbers at every sampled point **is** reproducing
the line — a wrong implementation cannot satisfy them.

**External anchor:** `astrocarto-solstice-rising-limit` — the Arctic Circle. A real number from
spherical geometry, not from us, that fails loudly if the circumpolar limit is mishandled.

**What a wrong implementation cannot fake:** the missing line. Code that always draws a complete
AC curve from pole to pole is fabricating a rising that never happens.

## Suggested design

- **A map, and it should look like one.** This is the only thing in the whole astrology category
  that is not a wheel — that is its screenshot advantage. Use it.
- **Forty lines is too many at once.** Filter by body, by angle, or by "show me benefics". The
  default view must not be spaghetti.
- **Tap a city, get the lines near it and their distances.** This is the actual question users
  arrive with — "what's near where I'm thinking of moving" — not "trace this line".
- Distinguish MC/IC (straight) from AC/DC (curved) visually; they mean different things.
- ⚠️ **Render the non-existent line as absent, not as an edge case at the map border.** If a body
  never rises at a latitude, there is no line there and the map must say nothing rather than
  something ambiguous.
- Interpretation text is optional and secondary. The map is the product.

## Failure modes

- Drawing AC/DC lines through latitudes where the body is circumpolar
- Using geocentric ecliptic longitude where right ascension and declination are required
- Wrapping longitude wrongly at ±180° — produces a line that jumps the map
- Implying precision the underlying positions do not have; see [[astronomy-core]] on arcminutes

## Related

[[astronomy-core]] · [[houses]] · [[natal-chart]] · [[events]]

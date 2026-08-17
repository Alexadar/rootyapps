# Sidereal zodiac (ayanamsa)

**Status:** engine implemented and oracled — **no UI**; the frame switch below is not built.
Note `sidereal` elsewhere in this repo means *sidereal time*, which is unrelated
**Lives in:** `EphemerisKit/Sources/EphemerisKit/Zodiac/Ayanamsa.swift`
**Tests:** `AyanamsaTests.swift` (9) · **Oracle:** `Oracles+zodiac.swift` (4 entries)
**Depends on:** [[astronomy-core]]

## What it does

Every longitude this engine computes is **tropical** — measured from the vernal equinox. The
sidereal zodiac measures from a fixed point among the stars instead. The difference between the
two frames is the **ayanamsa**, currently around 24° and growing by roughly 50.3 arcseconds per
year because of the precession of the equinoxes.

The conversion is one subtraction:

```
λ_sidereal = λ_tropical − ayanamsa(date)
```

That is the entire computation. What makes it non-trivial is that **there is no single ayanamsa.**
Lahiri (the Indian government standard), Krishnamurti, Raman, Fagan–Bradley and Djwhal Khul differ
by up to a degree, which is enough to move a body across a sign boundary. The function must
therefore be *parameterised by ayanamsa*, never hardcoded.

Everything downstream — [[houses]], [[aspects]], [[dignities]] — is unchanged in mechanism and
simply reads shifted longitudes. Nakshatras (27 lunar mansions of 13°20′ each) and dashas
(planetary period systems) are separate functions that only make sense once this exists.

## Why anyone pays

Measured: `vedic astrology` returns 10 autocomplete hits but only about three are generic — the
other seven are competitor app names. That is a crowded field with real demand.

Paid precedent **does** exist and is better than the crowding suggests — measured 2026-08-17:

| App | Price | Ratings | State |
|---|---|---|---|
| Jyotish Vedic | **$12.99** | 178 | active (2026-08-11) |
| Jyotish Dashboard™ | $9.99 | **253** | **dead since 2023-12** |
| Jyotish Computer | $9.99 | 7 | 2025-05 |
| Time Nomad *(general chart tool)* | $8.99 | 2,731 | active |

Five paid apps in the niche. **Jyotish Dashboard is a rot target** — 253 ratings, abandoned for
over two years. Still: this is depth inside the existing tool, not a second record.

## The oracle

**Kind: external.** This is one of the rare esoteric functions with a genuine published authority.

| Source | What it pins |
|---|---|
| **Lahiri / Indian Astronomical Ephemeris** (Positional Astronomy Centre, Govt. of India) | the official ayanamsa value at given epochs — a real published table |
| **Meeus, *Astronomical Algorithms*, ch. 21** | general precession in longitude; the rate the ayanamsa must grow at |
| **Fagan–Bradley definition** | ayanamsa = 24°02′31.36″ at 1950.0 — a single fixed anchor, exact by definition |

Oracle entries should pin:

- the ayanamsa value at **several separated epochs** (e.g. 1950.0, 2000.0, 2025.0) per system, to
  arcsecond tolerance — a single-epoch check cannot catch a wrong precession *rate*
- **round-trip identity:** `tropical → sidereal → tropical` returns the input to ±1e-9°
- **sign-boundary sensitivity:** a body at 24°30′ tropical Aries must land in Pisces sidereally
  under Lahiri — this is the check that proves the shift is actually applied downstream and not
  merely displayed
- **system disagreement:** Lahiri and Fagan–Bradley must differ by their published amount, so a
  copy-paste of one into the other fails

**What a wrong implementation cannot fake:** the growth rate across a 75-year span. Hardcoding
today's ~24° passes a single-epoch test and fails 1950 by more than a degree.

## Suggested design

- **A frame switch, not a separate app section.** The same natal chart, the same houses, the same
  aspects — read in a different frame. Anything that duplicates the chart UI for sidereal has
  designed it wrong.
- **The ayanamsa system is a setting with a default of Lahiri**, changeable, and the current value
  must be *visible* — a practitioner needs to know which system produced what they are looking at.
- **Show the offset numerically** somewhere in the chart metadata (e.g. "Lahiri 24°11′07″").
- ⚠️ **Never mix frames in one view.** A tropical Sun beside a sidereal Moon is meaningless. The
  frame belongs to the chart, not to the body.

## Failure modes

- Hardcoding a single ayanamsa value — passes today, wrong for every historical chart
- Applying the shift at render time only, so aspects and dignities silently stay tropical
- Confusing sidereal *time* (already in this Kit, used for houses) with the sidereal *zodiac* —
  unrelated concepts sharing a word
- Offering nakshatras or dashas before the frame itself is oracled

## Related

[[astronomy-core]] · [[houses]] · [[natal-chart]] · [[dignities]] · [[aspects]]

# Design an Apple Watch app for Ephemeris Sky

> **Provenance — read first.** This is the ORIGINAL design brief: the prompt the Nebula
> watch work answers, kept for traceability. The **authoritative delivered spec is the
> Apple Watch section of `README.md`**; where this brief and that section differ, the
> spec wins. One known difference: the moon *complication* is **text-only** (a watch
> face has no guaranteed latitude, so a hemisphere-correct disc cannot be drawn there),
> not the "drawn disc" this brief's item 3 first assumed — the latitude rule was
> established after this brief was written. This file is included so merging the handoff
> never silently drops the brief; it is not a second, divergent spec.

## What the app is

A precision astronomy/astrology tool for iPhone, iPad and Mac. It computes real geocentric
planetary positions (tropical, referred to the equinox of date), aspects, house cusps in six
systems, and synodic cycles — all on-device, offline, validated against NASA/JPL Horizons to
better than 7 arcminutes. It is not a horoscope-content app and generates no predictive text.
Its buyers are practitioners who care that the numbers are right. Paid once, no subscription,
no ads, no account. It ships in 17 languages.

This watch app is intended as a **standalone product with its own App Store listing**, not a
companion — so it has to stand on its own.

## Design system — "Nebula"

Single always-dark theme. Deep violet gradient ground (`#0C0525` → `#10082E`) with a faint star
field. Magenta accent `#FF4D9D`; secondary cyan `#35E7FF`, violet `#C061FF`, aurora green
`#4DF0A0`. Near-white glyph colour `#F2ECFF`. Text hierarchy is violet-tinted: `#BEAAEB` at 90%
for uppercase headers, `#C8B9EB` at 85% for secondary, `#BEAAEB` at 55% for faint. Retrograde is
amber `#E67E22` with the ℞ symbol. Dividers `#B496FF` at 14%. Cards are `.ultraThinMaterial` at
~0.54 opacity, softly rounded.

## Hard constraints

- **41 mm is 176×215 pt. Design there first.** If it fails at 41 mm it fails.
- **The phone's chart wheel does not survive the shrink.** It carries four layers — zodiac ring,
  twelve house cusps, ten planet glyphs, colour-coded aspect lines — and the aspect lines become a
  grey smear. Any wheel here is stripped to zodiac ring + planet glyphs + the AC/MC axis. No aspect
  lines, no house numbers, no cusp table.
- **The Digital Crown is the point.** Turning it scrubs time and moves the planets around the ring.
  That is the one interaction the watch does *better* than the phone, and it should be the hero,
  not a secondary control.
- **Glyphs are the vocabulary.** Planet, sign and aspect symbols are how this audience reads a
  chart. Do not replace them with words.
- **17 languages.** German compounds run long, CJK is full-width. No layout may depend on English
  string lengths.
- Everything computes on-device in milliseconds. No network, no loading states, no spinners —
  anywhere.

## Screens

1. **Wheel** (hero) — stripped zodiac ring, ten planet glyphs, AC/MC axis, current date/time.
   Crown scrubs time. Show resting and mid-scrub states.
2. **Positions** — scrolling list: glyph, sign, degree°minute, daily motion, retrograde marked.
   This is a table on a 176 pt-wide screen; that is the design problem.
3. **Now** — the glanceable summary: what's retrograde, Moon sign and phase, next ingress with its
   real date.
4. **Events** — upcoming ingresses, lunations, stations, each with a real date.

**Do not design:** aspects list, house cusp tables, the six house-system picker, or a
place/coordinate editor. Those belong on larger screens and would be unusable here.

## Complications

All four families — `accessoryCircular`, `accessoryCorner`, `accessoryRectangular`,
`accessoryInline` — plus a Smart Stack widget. These are the discovery surface for a standalone
watch app; treat them as a first-class deliverable.

The test for each: **does the value actually change, and would someone glance at it more than once
a day?** Anything static is wasted on a watch face. Ranked by how well they pass:

1. **Rising sign — lead with this.** The Ascendant moves through all twelve signs every 24 hours,
   roughly one every two hours. It is the only value that changes *while you're looking at it*, and
   almost nothing else in this category offers it because almost nothing else computes real houses.
   Sign glyph plus degree; on `accessoryCorner` use the gauge for progress through the current sign.
2. **Retrograde status.** Which planets are retrograde now, as glyphs with ℞ in amber. The single
   most-checked fact in this domain. `accessoryInline` reads "☿ ℞ until 22 Aug".
3. **Moon phase + sign.** Never an emoji (it can't show the true fraction and breaks the
   glyph vocabulary). **Resolved in the delivered spec:** a hemisphere-correct disc
   needs a latitude and a complication can't guarantee one, so the *complication* shows
   **text phase** (name · % · waxing/waning); a drawn `MoonDisc` is used only on in-app
   screens where a place exists. See the README moon rule.
4. **Next event with its real date** — "Mars → Gemini, 28 Jun". `accessoryRectangular` fits two
   lines. This is what makes it read as an almanac rather than a horoscope.
5. **Chosen planet's synodic phase** — "Morning star · day 2 of 9". Niche, but no competitor has it.

**Do not** design a complication showing a whole wheel, a full aspect list, or daily-horoscope
text — the app generates none.

## Data & refresh — read before designing complications

Nothing polls and nothing loads. Complications come from a WidgetKit timeline: the app hands the
system entries stamped with the exact instant each becomes valid, and the system renders them with
the app not running.

- **Never design a loading, refreshing or "last updated" state.** They don't exist. A value is
  exact or absent.
- **Values are exact at boundaries.** The engine computes the precise second the Ascendant changes
  sign, a planet stations, a body ingresses. Entries land on those instants. No "about", no "~",
  no rounding language.
- **Two states you must design**, both because data lives outside the widget's process:
  - **No place set.** The Ascendant depends on latitude, longitude *and* time, unlike planetary
    positions. Without a saved place it can't be shown. Prefer degrading to a place-independent
    value (Moon phase, retrograde) over an error.
  - **Stale place.** Location comes from a shared App Group container and doesn't follow the user
    when they travel. Decide whether that warrants visual treatment or is silently accepted.
- **Locale resolves at render time from the App Group**, not the system. A widget extension is a
  separate process and would otherwise show English despite the in-app language picker. Every
  complication string must survive all 17 languages in the smallest family.

## Deliverables

Layouts at 41 mm and 49 mm, all four complication families plus the Smart Stack widget, a type
scale that survives German and Japanese, and a note on what you dropped and why.

## The question I actually need answered

**Is the stripped wheel legible at 41 mm?** If it isn't, say so plainly and design a purely
typographic "Now" screen with complications instead. A watch app that reads well beats a wheel
that doesn't.

# Handoff: Ephemeris Sky — "Nebula" theme (v2, all platforms + Apple Watch)

## Overview
"Nebula" is a vivid, immersive redesign of **Ephemeris Sky** (the SwiftUI ephemeris /
astrology app). It keeps every existing data flow and control — it changes the
**visual language** (deep-space gradient + star field, dark violet-edged glass cards,
magenta→cyan accents, neon aspect palette, glowing chart wheel) and gives each
platform a **native layout**:

- **iPhone** — single column, bottom tab bar.
- **iPad** — top segmented control + **two-column dashboards** (Chart: Moment +
  "Tightest aspects" left, wheel right; Positions: Moment beside the table;
  Cycle: picker/phase beside upcoming events).
- **macOS** — **sidebar navigation** (gradient wordmark, icon+label rows, date
  footer), content column max ~860pt.
- **watchOS** — **standalone product with its own App Store listing**; four screens
  and five complication families. Full spec in the Apple Watch section below.
- **watchOS** — compact app view + complications.
- **visionOS** — floating glass window.
- **tvOS** — full-screen "Tonight's sky" dashboard with focus cards.
- **WidgetKit / ActivityKit** — home + lock-screen widgets, notification style,
  Dynamic Island live activity.

The app is always dark (`.preferredColorScheme(.dark)`).

## About the design files
`reference/Ephemeris Sky (All Platforms).html` is a **design reference created in
HTML** — one canvas showing every platform (the iPhone/iPad/macOS mockups are fully
interactive). It is **not** production code. The task is to **recreate this look in
the existing SwiftUI app** (`ephemeris.swift`) using its established patterns.

`DesignSystem/` contains **ready-to-use SwiftUI source** mapping the Nebula tokens
onto the app's conventions (uses `Color(rgbHex:)` from `ColorHex.swift`).

## Fidelity
**High-fidelity.** Exact colors, radii, treatments specified below. Reuse the app's
existing view structure; restyle and re-layout only as described.

---

# Apple Watch

A **standalone product**, not a companion — it must read on its own. Reference:
`reference/Ephemeris Sky (Apple Watch).html`, every screen at true 1× point size, which
is the honest legibility test. Code: `NebulaWatch.swift`, `NebulaComplications.swift`,
`MoonPhaseDisc.swift`.

## The headline question: is the stripped wheel legible at 41 mm?

**Yes — but it is an *instrument*, not a readout, and it survives only with all three of
these. Drop any one and it fails:**

1. **Two planet tracks with collision de-clustering.** At r ≈ 54 pt a 13 pt glyph
   subtends ~14°, so any pair closer than 15° overlaps. Real charts cluster constantly
   — on 29 Jul 2026 Jupiter and the Sun are **0.4° apart** in Leo, Saturn and Neptune
   9.8° apart in Aries. Colliding bodies drop to an inner track. Without this the wheel
   is a blob roughly one week in three. (`NebulaWatch.declusterTracks`)
2. **Only the four cardinal signs are labelled at 41 mm.** Twelve sign glyphs in a
   10 pt band forces ~8.5 pt, below the floor. ♈ ♋ ♎ ♑ at 10 pt plus twelve ticks gives
   the same orientation for a third of the ink. All twelve return at 49 mm.
3. **Precision lives in the centre, never on the ring.** You cannot read arcminutes off
   a 108 pt circle. The ring carries *gestalt and motion*; the hole in the middle
   carries the authoritative date/time and becomes the scrub readout.

**One deviation from the brief:** *Now is the launch screen, not the wheel.* A
practitioner raising their wrist wants "what is retrograde, where is the Moon, what is
next" in under a second — typography's job. The wheel is one swipe left, where the crown
makes it worth arriving at. Hero interaction, second screen.

## Screens (41 mm = 176×215 pt, designed there first)

1. **Now** *(launch)* — retrograde block (amber ℞, each with its direct date), Moon
   phase disc + sign + degree + illuminated %, next ingress with its exact date. Zero
   geometry. **Its title is the place name** ("LOS ANGELES") — see stale place.
2. **Wheel** — stripped ring, ten glyphs, AC/MC axis, centre readout; crown scrubs time.
   Mid-scrub: header becomes "SCRUBBING" + signed delta, crown arc on the right, centre
   ring tints accent, planets leave motion trails, sign ring dims to 60%.
3. **Positions** — the 176 pt table problem, solved as **four columns totalling 136 pt**:
   planet glyph (16) · sign glyph (15) · `d°mm′` mono (≈62) · daily motion right-aligned,
   retrograde rows amber and ℞-prefixed. Row height 31 pt, six visible.
4. **Events** — glyph-led rows, date as subtitle; lunations use a drawn phase disc.

**49 mm (205×251 pt) is not a redesign** — +16% width buys all twelve sign glyphs and a
seventh Positions row, and every value steps one rung up the type scale.

## Corner-safe insets — a real trap

The display corner radius (54 pt at 41 mm, 60 pt at 49 mm) eats content near the
corners: at a header baseline of y ≈ 13 pt the required left inset is ~12.8 pt, more than
the 10 pt you would naturally reach for. Rather than fight it per screen, **screen
headers are centred groups**, not edge-to-edge `HStack { … Spacer() … }`. Centring
removes the problem structurally and costs no vertical space — which matters because Now
is already full at 215 pt. (`NebulaWatch.cornerSafeInset`)

## The Digital Crown is the product

The one interaction the watch does better than the phone, so it is the hero.
`.digitalCrownRotation` at 0.02 days per detent (~29 min), haptics on, non-continuous.
Everything recomputes per frame — on-device, milliseconds, **no throttling, no loading
state**.

## Complications — the discovery surface

For a paid-once standalone app these are how it gets found. The test for every
candidate: **does the value actually change, and would someone glance at it more than
once a day?** Ranked:

| # | Candidate | Why it earns the slot |
|---|---|---|
| ① | **Rising sign** | The Ascendant moves a sign ~every 2 h — the only value that changes *while you are looking at it*, and it exists only because the app computes real houses. **Lead with this.** On `accessoryCorner` the bezel curve is a **Gauge** for progress through the current sign. |
| ② | **Retrograde status** | Most-checked fact in the domain. Glyphs + ℞ amber; gauge = elapsed fraction, so "how much longer" needs no words. Inline: "♄︎ ℞ until 18 Nov". |
| ③ | **Moon phase + sign** | Drawn terminator at the real illuminated fraction. |
| ④ | **Next event + real date** | "☽︎ → ♏︎ 30 Jul 04:12", exact to the minute — what makes it an almanac, not a horoscope. |
| ⑤ | **Synodic phase** | "☿︎ morning star · day 16 of 45". Niche, nobody else has it, last because it moves slowly. |

**Do not ship** a whole wheel, a full aspect list, or horoscope text — the app generates
none.

### What actually fits per family
- `accessoryCircular` **72 pt** — one gauge, one glyph, one 9 pt qualifier. Whole budget.
- `accessoryCorner` **80 pt** — glyph inboard + `.widgetLabel`. Rising uses it as a
  `Gauge`, others as ~20 characters. **The curve is system-drawn** — never hand-roll it,
  and never place the glyph on the arc. Corner slots are position-specific: the gauge is
  concentric with the display's corner radius, so it mirrors per corner.
- `accessoryRectangular` **158×57** — three lines, hard stop: kicker, glyph-led value,
  dated footer. The flagship.
- `accessoryInline` **one line** — the face's own font **and colour**; custom colour is
  impossible, so design monochrome-first. The only family where words are worth it.
- **Smart Stack widget 158×72** — icon, kicker, big value, gauge, dated footer.
- **X-Large: deliberately dropped.** A single-complication face, so it competes with the
  app's own Wheel screen instead of adding a discovery surface.

### Three rendering modes, and only one is yours
Read `\.widgetRenderingMode`. `.fullColor` is a **minority** of faces; `.accented`
collapses to one hue ramp; `.vibrant` desaturates into the face tint. So every family is
authored **glyph-and-gauge first** — the glyph names the subject, the gauge carries the
quantity, colour is only reinforcement. Nothing loses meaning when hue is stripped, which
also keeps it readable for red-green colour-blind users.

### Timeline — nothing polls, nothing loads
Entries are stamped with the exact instant each becomes valid and rendered with the app
not running. **Never design a loading, refreshing or "last updated" state — they do not
exist.** A value is exact or absent: no "about", no "~", no rounding language. Rising
needs an entry per sign boundary plus ~6 min gauge steps.

### Two states you must design
- **No place set.** The Ascendant needs latitude *and* longitude, so it cannot be computed
  without a saved place. An error on a watch face is worse than useless — the user cannot
  act on it there. **Degrade to a place-independent value** (Moon phase + sign). The
  footer is the only tell and it names the fix, not the failure.
- **Stale place.** Location comes from the App Group and does not follow the user when
  they travel. **Decision: no badge on the face.** It is unactionable there, fires on
  every trip for a value most travellers still want, and would train people to distrust a
  number that is usually right. Instead the place is always visible where it *is*
  actionable — **the Now screen gives up its own title to show "LOS ANGELES"**,
  discoverable in one tap from the complication that led there. Cheapest thing on the
  layout to spend, and it cost no vertical space.

## Moon phase: never an emoji
🌑/🌕 quantise to eight phases, so 18.0% and 31.4% render identically — and they arrive in
someone else's colour and drawing style, breaking a monochrome glyph vocabulary. Use
`MoonPhaseDisc` (drawn terminator at the true fraction) on Now, on Events, and in every
complication family. It holds down to 15 pt.

## Type scale that survives German and Japanese

| Role | 41 mm | 49 mm | Weight |
|---|---|---|---|
| Centre readout | 12 / 13 | 11.5 / 12.5 | Bold / Semibold |
| Planet glyph | 13 | 13 | Regular |
| Sign glyph (ring) | 10 | 9.5 | Regular (♈ ♋ ♎ ♑ only at 41 mm) |
| Row value (mono) | 13.5 | 14.5 | Regular · monospacedDigit |
| Row primary | 12.5 | 13.5 | Regular |
| Section header | 10 | 11 | Semibold |
| Faint / caption | 9.5 | 10.5 | Regular |

Five rules that make 17 languages safe:
1. **Glyphs and numbers carry the data.** Wheel, Positions and four of five
   complications contain **no translatable prose** — byte-identical in all 17 locales.
   The biggest win available, and the real reason to lean on glyphs.
2. **No uppercase for CJK** — `.textCase(nil)`, tracking 0 outside Latin scripts.
3. **A label never shares a line with its value.** "Nächster Zeichenwechsel" cannot fit
   beside a date at 176 pt, so it gets its own row. German gets vertical space instead of
   shrinking.
4. **One step of shrink, then wrap** — `.minimumScaleFactor(0.85)` + `.lineLimit(2)` on
   prose only, **never** on numerics, which stay `.monospacedDigit()` at full size so a
   degree value can never quietly compress.
5. **Locale resolves from the App Group at render time**, not the system — a widget
   extension is a separate process and would otherwise show English despite the in-app
   picker.

## What I dropped on the watch, and why
- **Aspect lines** — ten bodies give 13–20 aspects at 1.0× orb; at r 54 pt those chords
  cross in the middle 40 pt and average to a grey smear that hides the glyphs they
  relate. Retrograde amber is the only chart-level colour that survives.
- **House cusps and numbers** — a third layer of small type competing with the sign ring.
  AC/MC alone answer what a wrist glance asks.
- **Cusp table, six-system picker, place editor** — configuration, not consultation;
  multi-field entry that would take a dozen crown turns. The watch inherits the phone's
  settings.
- **Aspects list screen** — five fields per row at 176 pt; fits only at ~9 pt, and it is
  20 rows of scrolling nobody acts on from the wrist.
- **Moon-phase emoji**, **X-Large family**, **loading states** — see above.

---

---

## Design tokens

### Color
| Token | Hex / value | Use |
|---|---|---|
| Accent (primary) | `#FF4D9D` magenta | `.tint`, nav selection, slider, chevrons, counts |
| Accent cyan | `#35E7FF` | secondary accent, sextile, widget dates |
| Accent violet | `#C061FF` | tertiary, opposition |
| Aurora green | `#4DF0A0` | trine, "station direct" |
| Sign chip fill | `#9D4EDD` | zodiac chips in rows (glyph `#FFFFFF`) |
| Card fill | `white @ 5.5%` (Events `@ 7.5%`) | over `.ultraThinMaterial` |
| Card border | `#B496FF @ 28%` | 0.75pt stroke |
| Divider | `#B496FF @ 14%` | row separators |
| Text primary | `#ECE6FF` | body / values |
| Text secondary | `#C8B9EB @ ~62%` | labels |
| Text head | `#BEAAEB @ ~60%` | uppercase card headers (tracking 1.2) |
| Text faint | `#BEAAEB @ ~40%` | "Day X of Y", event codes |
| Planet glyph | `#F2ECFF` + violet glow | wheel + rows |
| Ring / spokes | `#966EFF @ 42%` / `@ 20%` | wheel rings / spokes+ticks |
| Retrograde | `#FFB020` | `℞` markers and retro motion (v2: amber, glows) |
| Card glow | `#7828C8 @ 50%`, r 22, y 12 | card drop shadow |

### Background (deep space)
Vertical `#0C0525 → #10082E`; magenta radial `#3A0E6B` from (18%, 0%); cyan radial
`#0E3A6B` from (92%, 26%); ~90 seeded faint stars. See `NebulaBackground.swift`.

### Aspect palette (neon)
Conjunction `#FF5A7A` · Sextile `#35E7FF` · Square `#FFB020` · Trine `#4DF0A0` ·
Opposition `#C061FF`. Aspect chips: 24×24, radius 7, **glyph in `#0C0525`** on the
neon fill, with a soft glow of the same color.

### Chart wheel (v2)
- Three rings: outer `0.46s` (violet @ 42%), middle `0.33s` (cyan @ 25%), inner
  `0.17s` (violet @ 16%); spokes @ 20%.
- **Degree ticks** every 10° (skip the 30° spokes), 6pt long, inside the outer ring.
- **Glass sign tiles** on the wheel (`WheelSignTile`): white @ 6% fill, violet @ 50%
  stroke, glyph `#D9C9FF`. (Rows still use the solid `SignChip`.)
- Chords drawn twice: halo (lineWidth 5, opacity 0.2, round cap) + core (1.6).
- Planet glyphs white with violet glow, at `0.29s`.
- **Center readout**: date (12pt, secondary) over time (14pt semibold, primary).

### Typography
System (SF Pro). Nav titles: 34pt heavy (iPhone) / 32 (iPad) / 28 (macOS),
tracking ≈ −0.3, violet glow, with a small secondary **context subtitle** beside it
("Geocentric · tropical", "13 in orb", …). Headers: caption/semibold/uppercase/
tracking 1.2. Numerics `.monospacedDigit()`.

### Radius / spacing
Cards r20 continuous, padding 16, gaps 16. Stepper buttons r12 with visible border
(`#B496FF @ 20%`) + violet fill (150,110,255 @ 18%), hover/pressed @ 30%.

---

## Per-platform layout specs

### iPhone
Existing `TabView` structure. Chart = Moment card + wheel card stacked.

### iPad
Segmented control centered under the status bar. Content grid (16pt gap):
- Chart: `moment | wheel` with `tightest-aspects` (top-5) under Moment; wheel column
  slightly wider (0.92fr / 1.08fr).
- Positions: `moment | table`. Aspects/Events: single centered column max 640pt.
- Cycle: `picker+phase | upcoming events` (1fr / 1fr).

### macOS
Sidebar 196pt: traffic lights row, wordmark in the magenta→cyan gradient, five
icon+label items (selected = accent-soft fill + accent text), spacer, faint
date·time footer. Content pane uses the same grids as iPad, max 860pt.
Sidebar background: `rgba(10,5,26,0.35)` + blur, right hairline `#B496FF @ 14%`.

### Cycle card (v2 merge)
Picker and phase are ONE card: header → body picker row → hairline →
glyph + phase title/detail + `℞` (amber, glowing) → **PhaseProgressBar**
(fraction = day/length) → faint "Day X of Y".

### watchOS / visionOS / tvOS / widgets / live activity / notifications
See `DesignSystem/NebulaSurfaces.swift` for exact patterns and values, and the
reference canvas for the target look.

## Interactions & behavior
Unchanged from the current app (tabs, orb slider re-detection, moment stepping,
time-zone sheet, cycle picker, demo animation). `ChartViewModel` continues to drive
all data.

## Assets
- `Assets.xcassets/AccentColor.colorset` → **`#FF4D9D`**.
- No image assets; all glyphs are Unicode with the text-presentation selector
  (`\u{FE0E}`) so they render monochrome (Moon phases 🌑/🌕 stay emoji).

## Integration map
1. Add `DesignSystem/*.swift` to the app target (NebulaSurfaces goes in the widget /
   watch / TV targets as relevant).
2. `AppBackground` → `NebulaBackground`. `.glassCard()` → `.nebulaCard()`
   (`dense: true` for Events). `CardHeader` → `NebulaCardHeader`.
3. `AspectColor.swift` → `AspectType.nebulaColor`; double-stroke wheel chords.
4. Row sign glyphs → `SignChip`; wheel sign glyphs → `WheelSignTile`.
5. Cycle phase row → merged card + `PhaseProgressBar`.
6. iPad: replace the single column with the grids above (`NavigationSplitView` not
   required — segmented control + `Grid`/`HStack` is faithful).
7. macOS: replace toolbar icon capsule with the sidebar (`NavigationSplitView`).
8. `.tint(NebulaPalette.tint)` at app root; update AccentColor asset.

## Files
- `DesignSystem/NebulaPalette.swift` — color/gradient tokens.
- `DesignSystem/NebulaBackground.swift` — backdrop + seeded star field.
- `DesignSystem/NebulaGlass.swift` — `nebulaCard()`, `nebulaGlow()`,
  `NebulaCardHeader`, `SignChip`, `WheelSignTile`, `PhaseProgressBar`.
- `DesignSystem/NebulaAspectColor.swift` — neon aspect colors + chord glow.
- `DesignSystem/NebulaSurfaces.swift` — iOS widgets, live activity, vision/TV notes.
- `DesignSystem/NebulaWatch.swift` — watch type scale, corner-safe insets, wheel
  geometry, **two-track de-clustering**, crown parameters.
- `DesignSystem/NebulaComplications.swift` — ranked candidates, per-family budgets,
  rendering modes, timeline entry dates, no-place / stale-place decisions, App Group
  locale.
- `DesignSystem/MoonPhaseDisc.swift` — drawn terminator at the true illuminated
  fraction (replaces every 🌑/🌕 emoji).
- `reference/Ephemeris Sky (All Platforms).html` — interactive canvas, iPhone/iPad/Mac
  plus watch, vision, TV, widgets and notifications.
- `reference/Ephemeris Sky (Apple Watch).html` — the watch deliverable: 41 mm and 49 mm
  screens at true 1× size, the full complication matrix (5 families × 5 values × 3
  rendering modes), corner and centre face slots, fallback states, type scale, drop list.

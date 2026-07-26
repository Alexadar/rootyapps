# Handoff: Ephemeris Sky — "Nebula" theme (v3, iPhone / iPad / macOS)

## Overview
"Nebula" is the vivid, immersive dark theme of **Ephemeris Sky** (the SwiftUI ephemeris /
astrology app). It's the **visual language** — deep-space gradient + animated star field,
sheer violet-edged glass cards, magenta→cyan accents, neon aspect palette, glowing chart wheel —
layered over the app's existing data flow and controls (nothing about the data or navigation
logic changes).

This doc describes **what is actually shipping** on the three supported platforms:

- **iPhone** — single-column `TabView`; native iOS 26 Liquid Glass bottom tab bar.
- **iPad** — **identical to iPhone** (one universal view, no iPad-specific layout).
- **macOS** — single scrolling column under a native toolbar of icon buttons.

The app is always dark (`.preferredColorScheme(.dark)`). Navigation chrome (top bar, tab bar,
toolbar) is the **native system Liquid Glass** — the design does not add custom top-bar chrome.

> **Not covered (intentionally):** watchOS, visionOS, tvOS, widgets, live activities,
> notifications, and the older iPad two-column / macOS sidebar concepts. Those were earlier
> aspirations and are **not built**; they've been removed from this handoff.

## About the design files
`DesignSystem/` is **ready-to-use SwiftUI source** for the theme (uses `Color(rgbHex:)` from the
app's `ColorHex.swift`). It mirrors the app's live files 1:1 and is the source of truth for this
handoff.

`reference/Ephemeris Sky (All Platforms).html` is an **older aspirational canvas** that still shows
extra platforms and the unbuilt two-column/sidebar layouts. It is **out of date** and is not the
reference for the current design — treat this README + `DesignSystem/` as authoritative until the
HTML is regenerated.

---

## Design tokens

### Color
| Token | Hex / value | Use |
|---|---|---|
| Accent (primary) | `#FF4D9D` magenta | `.tint`, tab/selection, slider, chevrons, counts |
| Accent cyan | `#35E7FF` | secondary accent, sextile |
| Accent violet | `#C061FF` | tertiary, opposition |
| Aurora green | `#4DF0A0` | trine, "station direct" |
| Sign chip fill | `#9D4EDD` | zodiac chips (glyph `#FFFFFF`) |
| Card fill | `white @ 5.5%` (Events `@ 7.5%`) | overlaid on `.ultraThinMaterial @ 0.54` |
| Card border | `#B496FF @ 28%` | 0.75pt stroke |
| Divider | `#B496FF @ 14%` | row separators |
| Text primary | `#ECE6FF` | body / values |
| Text secondary | `#C8B9EB @ 85%` | labels |
| Text head | `#BEAAEB @ 90%` | uppercase card headers (tracking 0.6) |
| Text faint | `#BEAAEB @ 55%` | "Day X of Y", event codes |
| Planet glyph | `#F2ECFF` + violet glow | wheel + rows |
| Ring / spokes | `#966EFF @ 42%` | wheel rings + spokes |
| Retrograde `℞` | `#E67E22` orange | retrograde markers |
| Card glow | `#7828C8 @ 50%`, r 22, y 12 | card drop shadow |

### Background & motion (`NebulaBackground.swift` + `MotionParallax.swift`)
Three layers, back to front:
1. **Static** vertical gradient `#0C0525 → #10082E`.
2. **Static** radial glows — magenta `#3A0E6B` from (18%, 0%) r520; cyan `#0E3A6B` from
   (92%, 26%) r460. *These never move.*
3. **Star field** — 90 seeded stars (xorshift, seed `0xEDA5`), drawn in a `Canvas` via
   `TimelineView(.animation(minimumInterval: 0.1))` (**~10 fps**). Each star **twinkles** on its
   own sine phase, per-star speed **1.2–2.6** (`a = baseA · (0.4 + 0.6·twinkle)`, never fully off),
   radius 0.6–1.7, base alpha 0.25–0.75.

**iOS tilt-parallax:** `MotionParallax` (CoreMotion) reads gravity, low-pass-smoothed, zeroed at
launch. Only the **stars** shift (in-canvas, over a 26pt overscan margin so edges never expose);
the gradient and glows stay put. Shared singleton so tilt persists across tab switches. **macOS**
gets a no-op stub — the backdrop is static there.

### Glass card (`NebulaGlass.nebulaCard`)
`.ultraThinMaterial` at **`.opacity(0.54)`** (sheer, so the sky reads through) + a `cardFill`
overlay (`white @ 5.5%`, `7.5%` for the dense Events card) + `#B496FF @ 28%` 0.75pt border +
drop-glow `#7828C8 @ 50%` r22 y12. Corner radius **20** continuous, padding **16**, gaps **16**.

### Aspect palette (neon) — `Views/AspectColor.swift`
Aspect colors live on `AspectType` in the app (`AspectColor.swift`); `NebulaAspectColor.swift`
here is the equivalent drop-in. Conjunction `#FF5A7A` · Sextile `#35E7FF` · Square `#FFB020` ·
Trine `#4DF0A0` · Opposition `#C061FF` · default `#9A93FF`. Row/list chips: 24×24, radius 6, white
glyph on the neon fill.

### Chart wheel (`Views/ChartWheel.swift`)
- Rings (fractions of the wheel size `s`): outer `0.46s`, inner `0.33s`, planet ring `0.27s`;
  12 spokes — all in `#966EFF @ 42%`, 1pt.
- **Zodiac sign tiles**: solid-violet `SignChip` style (violet fill, white glyph) placed around the
  band.
- **Aspect chords drawn twice**: a wide translucent halo + a thin bright core, in the aspect color.
- **Planet glyphs**: white `#F2ECFF` with a violet glow (`ctx.drawLayer` + shadow), on the `0.27s`
  ring.

### Typography
System (SF Pro). The **navigation/large title is the native system title** (white via dark mode) —
no custom nav typography. Card headers: caption / semibold / uppercase / tracking 0.6
(`NebulaCardHeader`). Numerics use `.monospacedDigit()`.

### Steppers / controls
The ◄ ► moment steppers use `.buttonStyle(.bordered)` tinted by the app accent. Orb is a standard
`Slider` (accent tint). Time zone is a searchable sheet. (See `MomentControls.swift`.)

---

## Per-platform layout (as built)

### iPhone — `Views/Platform/iOS/IOSContentView.swift`
Native `TabView` with the iOS 26 Liquid Glass bottom tab bar: **Chart · Positions · Aspects ·
Cycle · Events**. Each tab is a `NavigationStack` → single-column `ScrollView` → `VStack(spacing:16)`
of `.nebulaCard()` sections, over `AppBackground()`. Native Liquid Glass nav bar (transparent at the
scroll edge, frosts content scrolling under); white large title from `.preferredColorScheme(.dark)`.

### iPad
**Same code, same look as iPhone.** `ContentView` branches only on `#if os(macOS)` vs `os(iOS)`, so
iPad runs the identical `IOSContentView` — a single-column universal `TabView`. No size-class
branching, no `NavigationSplitView`, no two-column dashboards, no segmented control.

### macOS — `Views/Platform/macOS/MacOSContentView.swift`
A single scrolling column (content **max 720pt**, centered, padding 28/24) under a **native toolbar**.
The toolbar's `.principal` `ToolbarItemGroup` holds a row of icon buttons (Chart/Positions/Aspects/
Cycle/Events); the active one is a magenta pill (`accent @ 18%` capsule fill + `accent @ 55%` 1pt
stroke), the rest `textSecondary`. Selection swaps content via a `switch`. Window: min 820×640,
default 900×1010. **No sidebar, wordmark, or date footer.**

### Cycle card — `Views/CycleView.swift`
A "Current phase" card: header → body glyph + phase title/detail → retrograde `℞` (orange `#E67E22`)
when applicable → faint "Day X of Y" (no progress-bar widget). Below it, the upcoming-events list.

## Interactions & behavior
Unchanged from the app: tab navigation, ◄ ►/step-size moment stepping, orb slider, time-zone sheet,
cycle picker. `ChartViewModel` drives all data. A reel-only demo animation is gated behind env flags
(`EPHEMERIS_DEMO`, `EPHEMERIS_DEMO_LOOP`, `EPHEMERIS_TAB`, `EPHEMERIS_TZ`) and is inert in normal use.

## Assets
- `Assets.xcassets/AccentColor.colorset` → **`#FF4D9D`**.
- No image assets; glyphs are Unicode with the text-presentation selector (`\u{FE0E}`) so they render
  monochrome (Moon phases 🌑/🌕 stay emoji).

## Integration map (for applying Nebula to another app)
1. Add `DesignSystem/*.swift` to the app target.
2. Root backdrop → `NebulaBackground()`; call `motion.start()` on appear for the tilt-parallax
   (iOS). `.tint(NebulaPalette.accent)` + `.preferredColorScheme(.dark)` at the app root; set the
   AccentColor asset to `#FF4D9D`.
3. Cards → `.nebulaCard()` (`dense: true` for long/overflowing lists). Card headers →
   `NebulaCardHeader`. Row sign glyphs → `SignChip`.
4. Aspect colors → `AspectType.color` (or the `NebulaAspectColor` drop-in); draw wheel chords as a
   halo + core double-stroke.
5. **Leave navigation native** — do NOT set a `UINavigationBarAppearance`; the iOS 26 Liquid Glass
   bar (and native macOS toolbar) is the intended top bar.

## Files
- `DesignSystem/NebulaPalette.swift` — color / gradient tokens.
- `DesignSystem/NebulaBackground.swift` — static gradient + glows + animated twinkle star field (parallax-aware).
- `DesignSystem/MotionParallax.swift` — iOS CoreMotion tilt source (shared singleton); macOS no-op.
- `DesignSystem/NebulaGlass.swift` — `nebulaCard()`, `nebulaGlow()`, `NebulaCardHeader`, `SignChip`.
- `DesignSystem/NebulaAspectColor.swift` — neon aspect-color drop-in (mirrors `Views/AspectColor.swift`).
- `reference/Ephemeris Sky (All Platforms).html` — **stale** aspirational canvas (pending regeneration).

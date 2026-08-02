# TrueCourse — Design System (drop-in)

The view-layer identity for **TrueCourse**, a universal E6B flight computer (iPhone · iPad ·
Mac · Apple Watch). The look: a **matte glass-cockpit instrument** — near-black surfaces,
monospaced tabular readouts, one accent per calculator group, and a low-blue **Night**
(red-shift) theme that preserves dark adaptation in the flight deck.

> **Scope guard.** Everything here is *presentation only*. Do **not** touch the oracle-first
> `*Kit` math packages, the ViewModels, or the set of inputs/outputs each screen shows. Stay
> offline (system fonts/colors only). Keep it building on iOS / iPadOS / macOS / watchOS.

## What Claude Code should do

These files are written to match a shared component API, so the call sites in every
calculator sub-screen stay unchanged (`.instrumentCard()`, `NumberField`, `ResultRow`,
`CardHeader`, `SubScreenPicker`, `AppBackground`). Apply by replacing the *internals* of the
matching view-layer files:

| This file | Replaces / augments |
|---|---|
| `TCColors.swift`         | **new** — day+night palette tokens, metrics, `CalcSection.accent` |
| `CalculatorModel.swift`  | **new** — the calculator catalog + section membership (wayfinding data) |
| `TCTheme.swift`          | `Theme.swift` (`instrumentCard()`, `CardHeader`, `SectionLabel`) + `AppBackground.swift` |
| `TCComponents.swift`     | `Components.swift` (`NumberField`, `ResultRow`) |
| `TCSegmented.swift`      | the `SubScreenPicker` in `CalculatorDetailView.swift` |
| `TCCharts.swift`         | **new** — `WindTriangleView` + `CGEnvelopeChart` (the two hero visuals) |
| `FavoritesStore.swift`   | **new** — persisted favourites + `ThemeStore` (Dark/Night) |
| `CatalogGrid.example.swift` | reference for restyling the catalog (grouped grid + favourites) |
| `RootView.example.swift`    | reference for the **cross-platform** root — size-class switch |
| `WatchReadout.example.swift`| reference for the watchOS input-light layout |

Three one-line hooks make the whole system flow automatically:

1. Theme the app once at the root — this recolours **everything**, Dark or Night:
   ```swift
   .tcTheme(theme.selected)      // theme: ThemeStore()  (@AppStorage-backed)
   ```
2. Tint a detail screen with the calculator's accent (read from the env palette):
   ```swift
   .tint(tc.accent(calc.section))                 // ResultRow emphasis + SubScreenPicker pick this up
   .background(AppBackground(accent: tc.accent(calc.section)))
   ```
3. In the catalog, inject a `FavoritesStore` via `@StateObject`.

Every calculator screen reads the active palette via `@Environment(\.tc)`; nothing else in
the sub-screens needs editing — they already call the shared components.

## The two hero visuals

- `WindTriangleView(solution:)` — an honest vector triangle (heading/TAS + wind = track/GS)
  over a compass ring, drawn with `Canvas`. Feed it the `WindSolution` your Wind ViewModel
  already computes.
- `CGEnvelopeChart(envelopes:takeoff:landing:…)` — the loaded CG point (and its
  takeoff→landing travel) against the category envelope, built on **Swift Charts**. Green
  inside the envelope, red outside. Feed it the aircraft's real limits.

See **`DESIGN_GUIDELINES.md`** for the full rationale, token table, type scale, and rules.

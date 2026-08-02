# KERF — Design System (redesign drop-in)

View-layer redesign of the construction calculator: from a dark-amber utility to a
**light field instrument** — warm concrete "paper" body, one dark graphite readout,
a single hi-vis signal accent, monospaced hardware numerals, and glove-XL controls.
Sunlight-readable and built for a gloved hand on a job site.

> **Scope guard.** Everything here is *presentation only*. Do **not** touch the `*Kit`
> math packages, their oracle tests, the ViewModels, or the set of inputs/outputs each
> screen shows. Stay offline (system fonts/colours only). Keep it building on iOS/macOS.

## What to do

These files match the app's **existing shared component API**, so the call sites in every
sub-screen stay unchanged (`.card()`, `NumberField`, `ResultRow`, `CardHeader`,
`SubScreenPicker`, `AppBackground`). Apply by replacing the *internals* of the matching
files in `KerfCalc/Views/`:

| This file | Replaces / augments in `KerfCalc/Views/` |
|---|---|
| `KCColors.swift`       | token half of `KCTheme.swift` + `ToolSection.accent` / adds `Tool.accent`, `Tool.code` |
| `KCTheme.swift`        | `KCTheme.swift` (`card()`, `CardHeader`, `AppBackground`) + **new** `HeroReadout` |
| `KCComponents.swift`   | `Components.swift` (`NumberField`, `ResultRow`) + **new** `StepperRow`, `CheckRow` |
| `KCSegmented.swift`    | the `SubScreenPicker` in `Components.swift` |
| `KCKeypad.swift`       | **new** — the Spec hard-key vocabulary (`KeyFace`, `CalcKey`, `SpecKeypad`) |
| `KCFormulaCard.swift`  | **new** — the formula + citation card (the validation differentiator) |
| `FavoritesStore.swift` | keep / replace — persisted catalog favourites |
| `KCCategoryChips.swift` | **new** — compact category switcher (Formulas trades · Reference sections) |
| `SpecCalcView.example.swift`  | reference for restyling `Calc/CalcView.swift` (CM-Pro glove pad) |
| `CatalogGrid.example.swift`   | reference for restyling `ToolsRootView` (search + favourites + trade grid) |
| `ToolDetailView.example.swift`| reference for restyling a tool detail; includes `ToolDetailRegularExample` — the **side-by-side** regular layout (inputs left · results right) |
| `ReferenceView.example.swift` | reference for the adaptive Reference tab (chips on compact · two-column board on regular) |
| `RootView.example.swift`      | reference for the **cross-platform** root: compact tabs + chips → regular **rail + category sidebar + content**, ⌘1–3 on Mac |

## Category switching — one mental model

- **Compact:** `CategoryChips` under the search field (All + trades with counts; active chip
  = graphite with the trade dot and a signal count).
- **Regular:** the category sidebar owns the same choice (All / trades / Favorites); the rail
  owns the three surfaces (Spec · Formulas · Reference, ⌘1–3).
- Trade dots are the constant across both.

## Two one-line hooks make the accent flow everywhere

1. In each tool detail, tint the whole screen with the tool's accent:
   ```swift
   .tint(tool.accent)                              // ResultRow(emphasis:) + SubScreenPicker pick this up
   .background(AppBackground(accent: tool.accent)) // faint top wash
   ```
2. In the catalog, adopt the grouped grid (see `CatalogGrid.example.swift`) and inject
   `FavoritesStore` via `@StateObject`.

The hero number is different from Overtone Lab's approach: on a **light** theme, tinted
text on a light card is weak, so the one hero readout per screen lives on the dark
instrument surface via **`HeroReadout`** (signal on graphite). `ResultRow(emphasis:)` is
still available for a secondary "loud" line in the trade accent.

## Retired

- **Amber** is gone. Global tab selection is graphite (`KC.textPrimary`); wayfinding is
  the per-trade `tool.accent`; the single loud colour is `KC.signal`. Update the one
  `.tint(KC.amber)` in `ContentView` and set `.preferredColorScheme(.light)`.
- `CalcView`'s amber keypad is replaced by `SpecKeypad` (CM-Pro hard keys, glove-XL).

See **`DESIGN_GUIDELINES.md`** for the token table, type scale, component rules, and the
cross-platform behaviour.

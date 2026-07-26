# Overtone Lab — Design System (redesign drop-in)

View-layer redesign of Overtone Lab: from generic Liquid Glass to a **near-black studio
instrument** look — one accent per section, monospaced hardware readouts, matte cards, and a
single restrained Liquid Glass surface (the nav bar).

> **Scope guard.** Everything here is *presentation only*. Do **not** touch the `*Kit` math
> packages, the ViewModels, or the set of inputs/outputs each screen shows. Stay offline
> (system fonts/colors only). Keep it building on iOS/macOS 26.

## What Claude Code should do

These files are written to match the app's **existing shared component API**, so the call
sites in every sub-screen stay unchanged (`.glassCard()`, `NumberField`, `ResultRow`,
`CardHeader`, `SubScreenPicker`, `AppBackground`). Apply by replacing the *internals* of the
matching files in `OverToneLab/Views/`:

| This file | Replaces / augments in `OverToneLab/Views/` |
|---|---|
| `OTLColors.swift`     | **new** — colour/spacing tokens + `ToolSection.accent` / `Tool.accent` |
| `OTLTheme.swift`      | `Theme.swift` (`glassCard()`, `CardHeader`) + `AppBackground.swift` |
| `OTLComponents.swift` | `Components.swift` (`NumberField`, `ResultRow`) |
| `OTLSegmented.swift`  | the `SubScreenPicker` in `ToolDetailView.swift` |
| `FavoritesStore.swift`| **new** — persisted favourites for the catalog |
| `CatalogGrid.example.swift` | reference for restyling `RootCatalogView.swift` (direction **1b**, grouped + favourites) |
| `RootView.example.swift` | reference for the **cross-platform** root — size-class switch: compact → grid+push, regular → `NavigationSplitView` (iPad landscape / Mac) |

Two one-line hooks make the accent flow everywhere automatically:

1. In `ToolDetailView`, tint the whole screen with the tool's accent:
   ```swift
   .tint(tool.accent)          // ResultRow emphasis + SubScreenPicker pick this up
   .background(AppBackground(accent: tool.accent))
   ```
2. In `RootCatalogView`, adopt direction **1b** (see `CatalogGrid.example.swift`) and inject
   a `FavoritesStore` via `@StateObject`.

Nothing else in the sub-screens needs editing — they already call the shared components.

See **`DESIGN_GUIDELINES.md`** for the full rationale, token table, type scale, and rules.

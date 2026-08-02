# Aurora HUD — Space Weather Design System (drop-in)

The view-layer identity for **eartharound.swift**, the validated space-weather tracker
(iPhone · iPad · Mac · Watch-ready). The look: an **esports broadcast HUD** — matte arena-black
surfaces, chamfered (cut-corner) stat cards, monospaced tabular readouts, and one restrained
color system framed as the matchup the app actually reports: **Sun vs Earth**. A low-blue
**Night** (red-shift) theme preserves dark adaptation for aurora chasers in the field.

> **Scope guard.** Everything here is *presentation only*. Do **not** touch the oracle-first
> `SpaceWeatherKit` packages (GeomagKit, FlareKit, SolarWindKit, AuroraKit, HpoKit,
> SolarIndexKit) or their tests, the `SpaceWeatherStore`, or the set of inputs/outputs each
> panel shows. Stay offline (system fonts/colors only). Keep it building on iOS / iPadOS /
> macOS (and watchOS when the target lands).

## What Claude Code should do

These files match the app's existing shared component API, so panel call sites stay unchanged
(`Panel`, `PanelHeader`, `MetricTile`, `ScaleChip`, `MeaningLine`, `FlagPill`, `StaleBadge`,
`.swCard()`, `SpaceBackground`). Apply by replacing the *internals* of the matching view-layer
files:

| This file | Replaces / augments |
|---|---|
| `SWColors.swift`     | **new** — dark+night palette tokens, metrics, `SWSide` accents, severity ramp, and a compatibility bridge for the old static `SW` enum |
| `PanelCatalog.swift` | **new** — the panel registry + side membership (wayfinding data) |
| `SWTheme.swift`      | `DesignSystem/Theme.swift` (`swCard()`, `SpaceBackground`, `PanelHeader`) |
| `SWComponents.swift` | `Views/Components.swift` (`Panel`, `StaleBadge`, `MetricTile`, `ScaleChip`, `MeaningLine`, `FlagPill`) |
| `SWCharts.swift`     | `Views/Charts.swift` (`Hp30Chart`, `KpBarChart`, `XRayFluxChart`) |
| `SWSegmented.swift`  | every `.pickerStyle(.segmented)` (root tab switch, Hp30 range) |
| `ThemeStore.swift`   | **new** — persisted Dark/Night choice |
| `RootView.example.swift`    | reference restyle of `SpaceWeatherRootView` — header wordmark, matchup strip, tabs, Night toggle |
| `WatchReadout.example.swift`| reference for a future watchOS readout (one hero value, two stats) |

Three one-line hooks make the whole system flow automatically:

1. Theme the app once at the root — this recolours **everything**, Dark or Night:
   ```swift
   .swTheme(theme.selected)      // theme: ThemeStore()  (@AppStorage-backed)
   ```
2. Tint a panel with its side's accent (read from the env palette):
   ```swift
   .tint(sw.side(SWPanel.kp.side))          // PanelHeader tick + SWSegmented pick this up
   ```
3. Keep severity semantic: level colors come from `sw.severity(_:)` (0…5 NOAA level →
   quiet / caution / warning), never from per-metric hues.

Every view reads the active palette via `@Environment(\.sw)`. Views not yet migrated keep
working through the static `SW` bridge in `SWColors.swift`, which now maps the old token names
(`SW.cyan`, `SW.violet`, `SW.magenta`, …) onto the restrained system — so even before
touch-ups, nothing renders off-palette.

### Call-site touch-ups (small, mechanical)

- `DashboardView.swift` — swap explicit tile colors for semantics:
  `color: SW.cyan` → `color: sw.side(.link)` (solar wind), `flareColor(_:)` →
  `sw.severity(flareClass:)`, `color: SW.aurora` (aurora tile) → `color: sw.brand`.
- `GeomagView.swift` — `color: SW.violet` (Hp30 hero) → `color: sw.brand`;
  `color: SW.magenta` (9+ ceiling) → `color: sw.warning`; replace the range `Picker` with
  `SWSegmented`.
- `SpaceWeatherRootView.swift` — replace the tab `Picker` with `SWSegmented`, add the Night
  toggle from `RootView.example.swift`, apply `.swTheme(theme.selected)`.

## The two hero visuals

- `Hp30Chart(readings:)` — the 30-minute geomagnetic feed as a broadcast match timeline:
  brand-tinted area with the G1 threshold as a caution rule; the live point pulses at the
  leading edge. Feed it the `Hpo.Reading` array the store already holds.
- `KpBarChart(series:showForecast:)` — the 3-day Kp scoreboard. Quiet bars are neutral;
  bars color only when a level is actually reached (`severity`), forecast bars are ghosted.

See **`DESIGN_GUIDELINES.md`** for the full rationale, token table, type scale, and rules.

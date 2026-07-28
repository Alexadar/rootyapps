# Marine Nav — “Chart Table” UI redesign

SwiftUI templates for the presentation-layer redesign. Drop-in replacements for
`MarineNav/ContentView.swift` and the five files in `MarineNav/Tools/`, plus two
new files. **Nothing under `Kits/` is touched, referenced differently, or needed
to change.** No StoreKit, no networking, no location.

The visual design these were written from — baseline recreation, all five screens
in Day / Dark / Night-dim / Night-red, and the iPad/Mac split — is the HTML
design doc `Marine Nav.dc.html` in the same delivery.

---

## What the design is

A NOAA tide table read as a **helm instrument**. Used outdoors, in motion,
possibly at night, possibly with wet hands: glanceability beats density.

- **Warm chart paper** in daylight (high contrast, no shadows — shadows die in
  glare and glow in the dark; a hairline reads in both).
- **Every digit monospaced and tabular**, so a value never jitters as it updates.
- **The hero number is flush to the canvas**, not boxed in a row — it is the
  instrument, not a table cell.
- **Provenance is two surfaces**, never a footnote: a badge strip inside the
  first screenful (`Offline · NOAA-validated · No subscription`) and a
  named-authority footer per tool with its measured residual.
- **MODEL CAVEAT text gets a framed disclosure** with a caution glyph, so it
  reads as a stated limit rather than small print. All four caveats are kept
  verbatim in substance.
- **Times stay station-local and labelled** (`PDT`), on the chart axis and on
  every table header.

### Two-stage night mode

`.nightDim` removes all white light and desaturates; `.nightRed` goes to a single
red hue for dark adaptation. In `.nightRed` hue is no longer available as a
signal, so `MarinePalette.signByGlyph` flips true and rising/falling and
flood/ebb are told apart by **glyph** (▲ / ▼), never by colour.

---

## Files

| File | Status | What it is |
|---|---|---|
| `DesignSystem.swift` | **new** | Mode, palettes, type, metrics, and the four replaced seams: `ToolSection`, `ResultRow`, `NumberField`, `ProvenanceFooter` — plus `MarineCard`, `MarineSegmented`, `ModelCaveat`, `ProvenanceBadges`, `ToolScreen`, `HeroReadout` |
| `MarineCharts.swift` | **new** | `TideCurve`, `CurrentGraph`, `VariationDial` |
| `ContentView.swift` | replaces | Root `NavigationSplitView`, restyled catalog rows, appearance menu. The seams moved out of this file |
| `TidesToolView.swift` | replaces | Hero screen |
| `CurrentsToolView.swift` | replaces | |
| `DeclinationToolView.swift` | replaces | |
| `DistanceBearingToolView.swift` | replaces | |
| `SightReductionToolView.swift` | replaces | |

`Catalog.swift`, `StationCatalog.swift`, `MarineNavApp.swift`, `project.yml`,
`marinenav.icon` and `tools/genicon.swift` are unchanged. Add the two new files
to the `MarineNav` sources group (XcodeGen picks the folder up automatically) and
run `xcodegen generate`.

---

## The rules that were kept

**All math stays in the Kits.** Every displayed number still arrives from
`Harmonics` / `Currents` / `WMM` / `Vincenty` / `Navigation`. The view models
gained only selection and formatting:

- `nextExtreme` / `nextEvent` — `first { $0.date > now }` over the events the Kit
  already returned.
- `countdown` — seconds between now and that event, formatted.
- `chartMarkers` — the same events mapped to a 0…1 axis fraction.
- `nowFraction`, `nowLabel`, `dayLabel`, `latText`, `lonText`,
  `indexCorrectionSigned` — formatting only.

The charts receive samples and draw them. No interpolation of a physical
quantity, no unit conversion invented in a view (`knots(_:)` stays in the view
model exactly as it was, on the published 51.4444 cm/s definition).

**Ranges.** Every numeric input keeps its explicit `range:` and still clamps in
`onChange`. The new `−` / `+` buttons clamp too, so they cannot walk a value out
of a Kit's legal domain.

**Accessibility identifiers.** Every `tool.<rawValue>`, `input.<name>`,
`result.<name>` and `chart.<name>` from the structural build is preserved, on the
same element kind, so `ReelTour` still drives the app. Where a value moved into a
composed hero block, the old identifier is kept on a `.hidden()` sibling carrying
the same string — the query still resolves. **Run `ReelTour` before shipping** and
check the five `tool.*` taps and the two `swipeUpGently` scrolls: the sidebar is
still a `List` of `NavigationLink`s with a navigation-bar back button, and it was
deliberately **not** replaced with a tab bar for exactly this reason.

**PRODUCT_NAME** is untouched. No `Swift` / `.swift` in any shipped string.

---

## Bugs fixed in this pass

1. **Locale decimal separator** (`54,6` on a European locale). All numeric entry
   now formats through `MarineFormat.number(_:)`, which pins
   `Locale(identifier: "en_US_POSIX")`. Navigational entry is dot-separated in
   every locale.
2. **The bare tide `Path`.** `TideCurve` now has gridlines every 3 h, an hour axis
   in station-local time with the zone named, a **labelled** chart-datum line
   (`MLLW 0.00 ft` — a curve without a zero is a guess), extremes annotated in
   place with time over height, and a now marker with a readout capsule.
3. **The bare current `Path`.** `CurrentGraph` fills flood above the zero line
   and ebb below, labels both mean axes with their set, and draws slacks hollow
   and maxima solid.

## One thing the design needs and the Kits do not expose

The chart's **day/night (civil twilight) bands** want sunrise and sunset for the
station and the day. `CelestialNavKit` exposes GHA/Dec and the altitude
corrections but no rise/set solver, and `TidesKit` has none — so, per the rule,
it is **not** computed in the view. `TideCurve.twilight` is an optional array of
`ChartShading`; pass nothing and the bands are not drawn (that is the current
state). Lighting it up means adding a rise/set API to `CelestialNavKit` with its
own oracle (Nautical Almanac rise/set tables), which is a Kit change and
therefore out of scope for this pass.

## Not done, deliberately

No station search or favourites, no map, no onboarding, no settings screen, no
new tools, no icon change (`marinenav.icon` still fits: a tide curve on deep
navy, and `tools/genicon.swift` remains the generator). The appearance mode lives
in a toolbar menu on the root, persisted in `@AppStorage("marine.mode")`.

## Verification still owed

These templates were authored against the source but **not compiled here**. Before
review: `xcodegen generate`, then `xcodebuild` for
`-destination generic/platform=iOS` and `platform=macOS` (both must report BUILD
SUCCEEDED), then `swift test` in each of `Kits/*/` to prove the math is untouched.
Expect small mechanical fixes on the first build — `Vincenty.Inverse` /
`GeomagField` member names and `TideEvent.kind.rawValue` casing are the likely
spots.

---

## Adopted 2026-07-27 — with these deviations

Installed into the app: `DesignSystem.swift` and `MarineCharts.swift` → `MarineNav/Views/`;
`ContentView.swift` and the five tool views → `MarineNav/` and `MarineNav/Tools/`, overwriting in
place. All eight had to land together — the four seams and the two charts move between files, so a
partial install is 7 `invalid redeclaration` errors. No `project.yml` change was needed
(`sources: - path: MarineNav` is recursive). **This folder is kept, uncompiled, as the record of
why the design is what it is.**

It compiled on the first attempt on both platforms — the three "likely mechanical fix" spots this
README predicted (`Vincenty.Inverse` / `GeomagField` members, `TideEvent.kind.rawValue` casing) were
all already correct. What did need fixing:

| # | Defect | Fix |
|---|---|---|
| 1 | **`.hidden()` removes a view from the accessibility tree**, so `result.nowSlope` / `result.nowSet` / `result.dip` did **not** resolve — this README's claim that "the query still resolves" is wrong | Added `HeroReadout.stateIdentifier`, put each identifier on the real visible element, deleted the three overlays |
| 2 | `result.form.\(label)` made identifiers value-dependent — the Dip row's was literally `result.form.Dip (40 ft)` and changed as the user typed | Explicit stable identifiers on every sight-form row |
| 3 | **`.auto` appearance never followed the system.** `ToolScreen` forced `.preferredColorScheme` while the root passed `nil` for `.auto` and read the scheme back out of the environment — it self-confirmed | Removed it from `ToolScreen`; the root is the sole owner |
| 4 | `ForEach(currentStations)` keyed by `Identifiable.id` = station id **without** the bin | `id: \.stationKey` |
| 5 | Hour labels sat in 1/9-width cells while gridlines were at `i/8` — every label missed its line | `HourAxis` positions by true fraction in a `GeometryReader` |
| 6 | 96 samples mapped `i/95` while markers mapped `t/24h` — a 15-minute error at the right edge | 97 samples spanning 00:00–24:00 inclusive |
| 7 | Extreme dots resolved y from the **nearest 15-min sample**, so a high water could sit visibly below its own crest | `ChartMarker.y` carries the Kit's own value |
| 8 | Marker labels clipped at the top of the plot and collided with the hour axis and the FLOOD/EBB captions | Shared `labelPosition` flips and clamps them inside the plot |
| 9 | The station `Picker` rendered its selected value as the control label, printing the station name a second time beside the card's own — three wrapped lines on Golden Gate | Replaced with a `Menu` + compact "Change" control |
| 10 | `region` is `""` for every current station, so `"\(region) · \(id)"` read `" · SFB1203"` | Join non-empty components (the catalog is generated; fixed in the view) |
| 11 | Steppers were 40×40 against a doc comment promising 44 pt; `MarineMetrics.tapTarget` was dead | Use the constant |
| 12 | Tool title rendered twice on iOS (`ToolScreen` + `.navigationTitle`) | Content title wins; `.navigationTitle` kept for macOS only |
| 13 | `.scrollContentBackground(.hidden)` on a `ScrollView` is a no-op | Removed (the one on the sidebar `List` is load-bearing and kept) |
| 14 | **Performance**: `curve`/`extremes`/`nowHeight`/`nowSlope` were computed properties, and the redesign reads `extremes` five times per body pass (~370 height evaluations each), while `station` re-parsed the constituent table on every access | Memoised `Snapshot` per (station, unit, day) in both view models. Also fixes four independent `Date()` calls that could sample four different instants |
| 15 | Sidebar identifier was on the `HStack` inside the `NavigationLink`, so `buttons["tool.*"]` — ReelTour's **primary** query — never matched and the tour ran on silent fallbacks | Moved onto the link |

Left exactly as authored, deliberately: `ChartShading` / `TideCurve.twilight` stay declared and
unlit (they need a rise/set solver no Kit exposes — computing it in a view would break the house
rule), and the two pre-existing view-layer exceptions (`magneticHeading`, `knots`) carry over
untouched.

**Verified after adoption:** iOS + macOS BUILD SUCCEEDED · 103/103 Kit tests green · a new
`marinenavUITests/IdentifierChecks.swift` (7 tests) asserts every identifier resolves and pins the
ReelTour contract · Tides still matches NOAA for San Francisco to ≤3 min and ≤0.02 ft.

⚠️ **The reel capture must now run with `ONLY_TESTING=marinenavUITests/ReelTour`**, or
`IdentifierChecks` executes inside the screen recording.

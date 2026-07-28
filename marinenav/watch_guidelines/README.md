# Marine Nav — Apple Watch

The wrist half of the “Chart Table” system: visual language **and** functional
spec, mirroring the shape of `swiftui_guidelines/`. Self-contained — it compiles
against the four Kits, `StationCatalog.swift`, CoreLocation, WidgetKit and
AppIntents, and nothing else. No package added. No network. No StoreKit.

Read `swiftui_guidelines/README.md` first; everything below either carries a rule
over from it or says explicitly why it deviates.

---

## 1 · The idea

The phone app is a chart table. The watch is **the instrument mounted at the
helm**: one number, its trend, the next turn, and a crown that scrubs the day.
Everything the phone shows and the watch does not is one deliberate scroll or one
page away — never crammed in.

The one thing the watch does *better* than the phone:

- **F1 scrubbing.** Turning the crown moves the readout across the station's day.
  Nothing on the phone matches it, and it is free: the harmonic series is exact at
  any instant.
- **F4 Sight Mark.** A wrist is a stopwatch you are already wearing. One second of
  time error is about a quarter of a mile — this is the app's strongest reason to
  exist on this device.

## 2 · Visual language

Carried over unchanged: monospaced tabular digits in fixed-width slots; hairline
borders and no shadows; the station's own time zone named on every screen;
provenance and model caveats as product surface; sign-by-glyph in red mode.

### ⚠ Deviations, and why

| # | Phone | Watch | Why |
|---|---|---|---|
| 1 | Day = warm chart paper `#EAE6DC` | **Canvas is black in every mode**; Day becomes a *sunlight profile* — pure-white ink, heavier weights, thicker strokes, brighter accents | OLED black costs no power, the always-on state must be dark, and a paper-white rectangle at full brightness destroys night vision. “Day” on a wrist is about **contrast**, not about paper |
| 2 | `.auto` follows the system light/dark scheme | `.auto` resolves to **Dusk** | watchOS has no light/dark setting to follow. Resolving it by station twilight would need a rise/set solver no Kit exposes — see §7 |
| 3 | Five appearance names incl. “Dark” | Same five cases; `.dark` is titled **“Dusk”** | On an always-black platform “Dark” names nothing. The `rawValue`s match the phone so the vocabulary and any future sync stay identical |
| 4 | `.nightDim` desaturates a dark UI | Same intent, but the *distance* between Dusk and Night · dim is smaller here | There is no white-light surface left to remove; only ink luminance can come down |
| 5 | Chart has gridlines, hour labels, datum caption, four annotated extremes, now-capsule | Watch curve keeps **waterline, fill, datum rule, bare extreme dots, one cursor** | At ~190 pt the rest is mush. Every dropped item is present as text one scroll down. `WatchTideCurve` is a separate view, not a shrunk `TideCurve` |
| 6 | 12-tick variation dial | 4 cardinal ticks, two needles | The ticks merge below ~80 pt |
| 7 | No location, ever | **CoreLocation, optional**, for F2 “nearest” and F5 | A wrist has no keypad worth typing coordinates on. Still no network. See §4 |
| 8 | 44 pt targets | Rows 40 pt, consequential controls 44 pt, MARK ≈34 % of the screen | 44 pt rows would fit two per screen on a 41 mm |
| 9 | Numeric entry via `TextField` + steppers | **Crown**, detented and clamped | Typing 245° on a 41 mm screen is not a design |

### Palette (all four modes)

`WatchDesign.swift` is the source of truth. Canvas is `.black` throughout.

| Token | Day (sunlight) | Dusk | Night · dim | Night · red |
|---|---|---|---|---|
| surface | `#121A20` | `#0E1720` | `#080D11` | `#120303` |
| ink | `#FFFFFF` | `#EAF2F6` | `#A8B8C2` | `#FF7A63` |
| inkDim | `#A9BCC7` | `#8CA3B0` | `#64757F` | `#A83A28` |
| water | `#6FD3EC` | `#58C4E0` | `#4A8C9E` | `#FF5A3C` |
| flood | `#5FD8C6` | `#4FC0B2` | `#3F8E86` | `#FF7A63` |
| ebb | `#F0B15C` | `#E0A24E` | `#8A7350` | `#FF7A63` |
| caution | `#FF7F5F` | `#E86A4E` | `#9E5A44` | `#FF9A85` |
| stroke | 3 pt | 2.5 pt | 2.5 pt | 2.5 pt |
| `signByGlyph` | false | false | false | **true** |

In red mode `flood == ebb` **on purpose**: the two states are told apart by arrow
direction (`arrow.right` / `arrow.left`), by word (FLOOD / EBB) and by position
(above / below the zero rule) — three redundant non-hue encodings. If a watch
screen ever distinguishes two states only by hue, it is wrong.

### Type ramp

SF for words; every value monospaced, tabular, and inside a `WatchSlot` of fixed
width so a value going 9.9 → 10.0 does not shove its unit sideways.

| Role | Size |
|---|---|
| hero | 34 (compact) / 40 (regular) / 46 (large), then `ViewThatFits` drops −6, −12 |
| value | 17 semibold mono |
| valueSmall | 15 medium mono |
| mono13 / mono11 | 13 / 11 medium mono |
| label / labelSmall | 14 / 12 |
| section | 11 semibold, +0.8 tracking, upper |
| caption | 11 |

Spacing: gutter 6/8/10 by size class; card radius 10, padding 8; section gap 10;
row 40; target 44.

## 3 · Device matrix

Nothing branches on a model. `WatchSize.measuring(width)` reads the actual width
from a `GeometryReader`: **compact** ≤176 pt, **regular** 177–199, **large** ≥200.
Layouts use `ViewThatFits`, `minimumScaleFactor` and `.lineLimit`, so the smallest
screen at the largest accessibility text size still resolves.

Screen sizes in **pixels** are per Apple's own comparison page (@2x, so points =
px ÷ 2): <cite index="1-1,1-3">46 mm 416 × 496, 49 mm 410 × 502, 45 mm 396 × 484, 44 mm 368 × 448, 42 mm 374 × 446, 41 mm 352 × 430, 40 mm 324 × 394</cite>.

| Case | px | pt | Class |
|---|---|---|---|
| 40 mm (SE) | 324 × 394 | 162 × 197 | compact |
| 41 mm | 352 × 430 | 176 × 215 | compact |
| 42 mm (S10/11) | 374 × 446 | 187 × 223 | regular |
| 44 mm (SE) | 368 × 448 | 184 × 224 | regular |
| 45 mm | 396 × 484 | 198 × 242 | regular |
| 46 mm (S10/11) | 416 × 496 | 208 × 248 | large |
| 49 mm (Ultra / Ultra 2) | 410 × 502 | 205 × 251 | large |

**The brief said the smallest is 41 mm. If the 40 mm SE is in the support matrix,
the real floor is 162 pt, not 176** — the compact class already covers it, but the
smallest-screen test must be run on a 40 mm, not a 41 mm. Flagged in §8.

### Always-on (dimmed) — a distinct state, not a faded one

Driven by `@Environment(\.isLuminanceReduced)`, which swaps in `WatchTheme.dimmed`:

- hairlines and card fills → **gone** (`ambientHairline` is `.clear`); the curve
  keeps its line but **loses its fill** — a large lit area is what the ambient
  state exists to avoid
- ink steps back to `inkDim`; the hero steps to `ink` at 75 %
- the datum rule goes from dashed to solid-dim: dashes smear when dimmed
- extreme dots are dropped; the cursor stays
- countdowns coarsen to **5-minute granularity** (`WatchFormat.countdown(coarse:)`)
  and the minute tick stops — an ambient view is not a live view
- the crown loses focus (`.focusable(!luminanceReduced)`), so a sleeve cannot
  scrub the day while your wrist is down
- MARK stays full size and pressable; only its wash dims. Losing the sight-mark
  target in the ambient state would defeat the feature

## 4 · Functions

### F1 · Tides Now — `WatchTidesNowView.swift`
Hero height + unit, trend glyph, rate, next turn (kind + station-local clock +
countdown), station name, zone, compact curve. **Crown scrubs** 0…1440 minutes,
detented every 15 min to match the sample grid, so the cursor never lands between
two knowns; haptics on. While scrubbing, the scrub time and zone are stated in
words with a **NOW** button to return — a 30 pt cursor is not enough to tell you
you are looking at 14:20.
Data: `Harmonics.heights` (**97 samples, 00:00…24:00 inclusive**, so index/96 and
time/24 h agree — 96-as-i/95 was a 15-minute error at the right edge on the
phone), `.height`, `.slope`, `.extremes`. One memoised `Snapshot` per
(station, unit, day); one `Date()` per pass.

### F2 · Station picker — `WatchStationPickerView.swift`
Nearest-five by GPS when authorised (distance + initial bearing from
`Vincenty.inverse` — GeodesyKit, not a haversine in a view), then Recent, then the
whole catalog. **Permission-denied is the first path written, not an error
branch**: a plain sentence and the list you need. `notDetermined` shows an
opt-in that says the app works fully without it. No search field — no typing on a
wrist.

### F3 · Currents — `WatchCurrentsView.swift`
Speed in knots, FLOOD/EBB by word + arrow + position, set in °true, next-slack
countdown, event list, mean axes. Flood above the zero rule, ebb below.
Data: `Currents.velocity` / `.events`; `knots(_:)` is the phone's existing
51.4444 cm/s constant, carried over, not a new exception.

### F4 · Sight Mark — `WatchSightMarkView.swift`
A single ≈34 %-of-screen target with nothing else tappable near it, `.success`
haptic as the eyes-free confirmation, and `Date()` read on the **first line** of
the action before any state change, animation or haptic. **UTC is the primary
face** (the almanac is tabulated in UT); local time is secondary. Marks persist to
a JSON file in the watch's own container — no app group, no phone. Notes by
dictation/Scribble; **altitude is never entered here** — it is paired on the
phone, where a range-guarded numeric field exists.
Ultra Action button: `RecordSightMarkIntent` + `AppShortcutsProvider`. Third-party
access is <cite index="14-2">only through the user assigning the app in Settings — Apple's own guide notes third-party apps *may* support the Action button</cite>, so the app **cannot seize it**; the on-screen control is the design and the button is an accelerant. Registering the intent also puts “Mark” in Shortcuts, Siri and the Smart Stack for free.

### F5 · Declination — `WatchDeclinationView.swift`
`WMM.field` at the current position; variation with E/W as a **letter**, the dial
showing which side of true north; true→magnetic with the **crown** driving the
heading (1° detents, clamped 0…360 because the Kits `precondition` illegal
domains), dip and total intensity, caveat, provenance. No fix → last-known
position, labelled stale; no position at all → a statement plus an opt-in, never
a blank or an error.

### F6 · Complications — `MarineNavComplications.swift`
All four accessory families. Content everywhere: height, trend glyph, next turn,
countdown.
**The structural advantage:** harmonic synthesis is exact and offline, so the
provider hands WidgetKit a **289-entry, 5-minute, 24-hour timeline** from one Kit
evaluation pass and `.atEnd` — no frequent-refresh pattern, no budget anxiety.
Every server-backed tide complication is stuck doing the opposite.

| Family | Shows | No station | Stale |
|---|---|---|---|
| Circular | `Gauge(.accessoryCircular)` whose **needle position** is the height between the day's low and high, trend glyph, numeral inside | waves glyph + “Set” | gauge holds, numeral dims; position still true within the day |
| Corner | numeral on the arc; `widgetLabel` = trend arrow + next turn | “Choose a station” | as above |
| Rectangular | station + **zone**, height + unit + trend, next turn with a live `Text(date, style: .timer)` | “Open to choose a tide station” | timer keeps counting; entry text is last-known |
| Inline | `3.56ft ↑ High 11:58 PDT` | “Marine Nav — choose a station” | unchanged text |

Rectangular is the only family with room for the zone, so it **always** carries it
— a tide time with no zone is the bug that started all of this. The gauge is
position-based precisely because accessory families are tinted by the watch face:
colour can never carry meaning there.
⚠ `.containerBackground(.clear, for: .widget)` is on every family — without it the
complication renders correctly in the Simulator and grey on a real device.

### Root — `WatchRootView.swift`
Horizontal `TabView(.page)`: Tides · Currents · Mark · Declination · Settings.
**Not `.verticalPage`** — that style gives the crown to the tab bar, and the crown
belongs to F1 and F5. `.preferredColorScheme` is attached here and nowhere else.

## 5 · Ultra, as progressive enhancement only

The Series/SE app is complete without any of this: (a) the Action Button path for
F4; (b) `large` size class — bigger hero, 62 pt curve, wider slots; (c) Night ·
red pairs with the Ultra's Night Mode watch faces so the whole device is one hue;
(d) the Day/sunlight profile exists for the Ultra's peak brightness on deck. No
Ultra-only feature and no Ultra-only layout branch.

## 6 · Accessibility

- Identifiers go on **real, visible** elements. Never on a `.hidden()` view — it
  is removed from the accessibility tree, which silently broke three identifiers
  on the phone. Composed blocks use `.accessibilityElement(children: .ignore)` +
  an explicit label + the identifier on the same element.
- Identifiers are **value-independent** (`result.extreme.0`, not
  `result.form.Dip (40 ft)`, which changed as the user typed).
- Convention carried over: `tool.<name>`, `input.<name>`, `result.<name>`,
  `chart.<name>`.
- Every label speaks the full quantity, its unit as a **word**, and the
  **station's zone**: *“Now, 3.56 feet above chart datum, rising 0.82 feet per
  hour, at San Francisco.”* · *“Next high water 11:58 PDT, in 2h 17m.”*
- The crown-driven heading also exposes `.accessibilityAdjustableAction`, so
  VoiceOver users are not required to use the crown.

## 7 · Seams — numbers the Kits do not expose

Per the house rule, these are **not** computed in a view:

1. **Sunrise / sunset (civil twilight).** Would let `.auto` follow the sky and let
   the curve band day and night. `CelestialNavKit` has GHA/Dec and altitude
   corrections but no rise/set solver. Unlit here exactly as `ChartShading` is
   unlit on the phone. Lighting it up = a rise/set API with its own oracle
   (Nautical Almanac rise/set tables).
2. **Clock error for F4.** A mark's accuracy is bounded by the watch's clock, and
   with no network there is nothing to compare against. So the screen claims
   millisecond **resolution** and says so in as many words — it never claims
   accuracy. Do not add an NTP check.
3. **Distance to station** uses `Vincenty.inverse` — a Kit call, not new math.

## 8 · Everywhere I had to guess — verify before shipping

| # | Guess | How to check |
|---|---|---|
| 1 | Points assumed = px ÷ 2 for every case (@2x). Ultra's PPI differs (338 vs 326) but the scale factor is what matters | `WKInterfaceDevice.current().screenBounds` on each simulator |
| 2 | **Usable** width is narrower than screen width (corner radius + system insets), so my 176/200 pt class boundaries may land one model off | Log `geo.size.width` inside the app on 40/41/42/45/46/49 mm |
| 3 | Ultra 3 (2025) may have a larger panel than Ultra 2's 410 × 502; I found no confirmed figure and did not design to one | Apple's tech specs / simulator |
| 4 | Whether the 40 mm SE is in the support matrix (the brief said 41 mm is smallest) | Product decision — then test on the true floor |
| 5 | `.digitalCrownRotation(_:from:through:by:sensitivity:isContinuous:isHapticFeedbackEnabled:)` signature and that `.focusable()` is still required to receive it | Compile; drive both screens on device |
| 6 | `Gauge(.accessoryCircular)` + `currentValueLabel` inside a complication renders the numeral at a legible size on 41 mm | Real device, all four families |
| 7 | 289 timeline entries is within WidgetKit's per-widget entry limit and does not get trimmed | Instrument; halve the spacing to 10 min if trimmed |
| 8 | `Text(date, style: .timer)` is permitted in `accessoryRectangular` on watchOS | Real device |
| 9 | `.listStyle(.carousel)` is still the right list style for the picker in this watchOS | Visual check |
| 10 | Action-button assignment via `AppIntent` alone (no extra Info.plist key) | `developer.apple.com/documentation/appintents/actionbuttonarticle`, then a real Ultra |
| 11 | `WKInterfaceDevice.current().play(.success)` is the right haptic for MARK vs `.click` / `.notification` | Feel it on the wrist, gloved |
| 12 | `.privacySensitive` is not needed on any complication (no personal data) | Review |
| 13 | `TideUnit`, `Station`, `TideEvent.kind`, `CurrentEvent.phase`, `GeomagField.h/.f`, `Vincenty.Inverse.azimuth1Deg` spellings — taken from the phone views, not re-read from the Kits | First compile |
| 14 | `WKRunsIndependentlyOfCompanionApp` still being the right key (vs a watch-only app target) given the app is a companion in the same purchase | XcodeGen output + App Store Connect |

## 9 · Files

| File | What |
|---|---|
| `WatchDesign.swift` | Modes, palettes, size classes, type, metrics, formatting, `WatchHero` / `WatchCard` / `WatchNextTurn` / `WatchSlot` / `WatchProvenance` / `WatchCaveat` |
| `WatchCharts.swift` | `WatchTideCurve`, `WatchCurrentCurve`, `WatchVariationDial` |
| `WatchTidesNowView.swift` | F1 |
| `WatchStationPickerView.swift` | F2 + `WatchStationStore` + `WatchLocationProvider` |
| `WatchCurrentsView.swift` | F3 |
| `WatchSightMarkView.swift` | F4 + `SightMarkStore` + `RecordSightMarkIntent` |
| `WatchDeclinationView.swift` | F5 |
| `MarineNavComplications.swift` | F6 — widget bundle (separate extension target) |
| `WatchRootView.swift` | Root, mode owner, `@main` app |

### XcodeGen

Two new targets. `StationCatalog.swift` is shared verbatim — it is pure data plus
`TidesKit`. **`Catalog.swift` is not shared**: its `Tool.destination` returns iOS
views, so it would not compile here; watch provenance strings live in the screens.

```yaml
  marinenavWatch:
    type: application
    supportedDestinations: [watchOS]
    deploymentTarget: { watchOS: "26.0" }
    sources:
      - path: MarineNavWatch          # this folder's Swift files
      - path: MarineNav/StationCatalog.swift
    dependencies:
      - package: TidesKit
        product: TidesKit
      - package: GeomagKit
        product: GeomagKit
      - package: GeodesyKit
        product: GeodesyKit
      - package: CelestialNavKit
        product: CelestialNavKit
      - target: marinenavComplications
    settings:
      base:
        PRODUCT_NAME: "Marine Nav"    # never "Swift" / ".swift" — Guideline 5.2.5
        PRODUCT_BUNDLE_IDENTIFIER: oleksandr.aisixteen.marinenav.watchkitapp
        INFOPLIST_KEY_WKCompanionAppBundleIdentifier: oleksandr.aisixteen.marinenav
        INFOPLIST_KEY_WKRunsIndependentlyOfCompanionApp: YES
        INFOPLIST_KEY_NSLocationWhenInUseUsageDescription: "Used only to list the nearest tide stations and your magnetic variation. Nothing is sent anywhere — Marine Nav makes no network requests."
        INFOPLIST_KEY_ITSAppUsesNonExemptEncryption: NO
  marinenavComplications:
    type: app-extension
    supportedDestinations: [watchOS]
    sources:
      - path: MarineNavWatch/MarineNavComplications.swift
      - path: MarineNavWatch/WatchDesign.swift
      - path: MarineNavWatch/WatchStationPickerView.swift   # WatchStationStore
      - path: MarineNav/StationCatalog.swift
    dependencies:
      - package: TidesKit
        product: TidesKit
```

⚠ The complication extension needs `WatchStationStore`, which currently lives in
`WatchStationPickerView.swift` and drags CoreLocation in with it. **On install,
split `WatchStationStore` into its own file** so the extension does not link
CoreLocation. Noted rather than pre-split, so this folder stays readable as one
screen per file.

## 10 · Verification owed

Authored against the source; **not compiled here**. Before review:

1. `xcodegen generate`, then `xcodebuild -destination 'generic/platform=watchOS'`
   plus the existing iOS and macOS destinations — all three BUILD SUCCEEDED.
2. `swift test` in each `Kits/*/` — 103/103, proving no math moved.
3. Run every `#Preview` at the largest accessibility text size on a 40/41 mm and
   on a 49 mm.
4. On a real device: always-on state for each screen, red mode in the dark, MARK
   with a glove, all four complication families (the grey-background trap), and
   the crown on F1 and F5.
5. Grep for `preferredColorScheme` — exactly one hit, in `WatchRootView`.
6. Grep for `.hidden()` next to `accessibilityIdentifier` — zero hits.

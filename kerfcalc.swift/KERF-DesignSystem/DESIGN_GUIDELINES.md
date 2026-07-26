# KERF — Design Guidelines

A construction calculator for framers, concrete crews, and remodelers. This redesign keeps
the app's function 1:1 and changes only the look — and deliberately makes it feel like a
different, modern, *alternative* tool (not the dark-amber original, not the retro competitor).

---

## 1. Direction

**A light field instrument.** Most calc apps are dark keypads; KERF inverts that for
sunlight readability and a premium, precise feel.

- **Concrete "paper" body** — flat `#EDE9E0`, matte white cards. No gradient wash.
- **One dark instrument** — the readout / hero / formula cards are graphite `#16171B`.
  The number is the hero, and it lives here (never as tinted text on a light card).
- **One hi-vis signal** — `#E8FB4A` marks exactly the loud things: the `=` key, the hero
  number, active precision, favourite stars. Used sparingly, it reads modern, not cheap.
- **Wayfinding by trade** — Framing / Concrete / Takeoff / Materials / Convert each own a
  colour. The accent tints the tile code-badge, the sample readout, the segmented control,
  and the secondary emphasised result.
- **Glove-first** — XL keys and `±` steppers, hit targets ≥ 44pt, minimal chrome.
- **Numbers are monospaced** — JetBrains-Mono-equivalent metrics via `.monospacedDigit()`
  so columns align. (Offline: use the system monospaced design, not a bundled font.)

---

## 2. Colour tokens  (`KCColors.swift`)

| Token | Value | Use |
|---|---|---|
| `background`    | `#EDE9E0` | full-bleed app background |
| `surface`       | `#FFFFFF` | cards, tiles |
| `surfaceRaised` | `#F6F3EC` | nested / raised card |
| `instrument`    | `#16171B` | readout · hero · formula card (the one dark surface) |
| `hairline`      | `black 6%` | 1px card/tile stroke |
| `chipFill`      | `#F1EDE4` | value / sample chip |
| `textPrimary`   | `#16171B` | values, tool names |
| `textSecondary` | `#6E6F75` | labels |
| `textTertiary`  | `#A7A296` | units, chevrons |
| `onInstrument`  | `#F3F2EC` | text on graphite |
| `instrumentDim` | `#7C7D83` | tape / captions on graphite |
| `signal`        | `#E8FB4A` | `=` key · hero number · active · star |
| `onAccent`      | `#101114` | ink on the signal fill |
| `ok` / `warn`   | `#2E9E67` / `#D0603F` | code-check pass / review |

### Trade accents (single source of wayfinding colour)

| Section | Accent | Hex |
|---|---|---|
| Framing   | blue  | `#2E6BFF` |
| Concrete  | slate | `#7C8698` |
| Takeoff   | teal  | `#12B5A5` |
| Materials | coral | `#F0785A` |
| Convert   | ochre | `#D99A2B` |

Exposed as `ToolSection.accent` / `Tool.accent`; `.tint(tool.accent)` at detail level flows
to `ResultRow(emphasis:)` and `SubScreenPicker`. `ToolSection.tint` / `Tool.tint` is the
13%-alpha badge wash.

---

## 3. Shape & spacing

- Radii: card **20**, tile **19**, key **17**, input **11**, chip **8**, segment track **12**.
- Card padding **16**. Grid gap **11**. Screen margin **15–16**.
- Keypad: **glove-XL** — numeric keys ~60pt tall, function/nav rows ~50pt. Gap **8**.
- Hit targets ≥ **44pt**; stepper buttons **40pt**.

---

## 4. Type

- System font — offline, no remote fonts. (Design intent: Archivo for display, JetBrains
  Mono for numerals; ship with SF + `.monospaced` design to stay offline.)
- Large title (tab / screen name) **30 heavy**, kerning −0.4.
- Tile name **16 bold**. Body / label **15**. Caption label: **monospaced**, uppercased,
  tracking ~1.4.
- Keypad digits **27 bold rounded**; `=` **28 heavy**; dimension keys **18 heavy**.
- **All numbers monospaced** (`.system(_, design: .monospaced)`, `.monospacedDigit()`).
- Hero readout **40 bold monospaced**, in `signal` on the instrument surface.

---

## 5. Components

- **Card** — `.card()` (matte white). `raised: true` for the warmer nested surface.
- **HeroReadout** — the dark instrument panel holding the one hero number per screen, in
  `signal`. This replaces "emphasis text on a light card".
- **CardHeader** — mono, uppercased, secondary; optional trailing accent value.
- **NumberField** — label ↔ mono value chip; kept for compatibility.
- **StepperRow** — glove-XL: label ↔ `−` (light) / value / `+` (graphite) / unit.
- **ResultRow** — label ↔ mono value; `emphasis` tints a *secondary* loud line in the accent.
- **CheckRow** — label ↔ OK / CHECK pill (`ok` / `warn`).
- **SubScreenPicker** — pill segmented control; selected pill = graphite + accent underline.
- **SpecKeypad** (`KCKeypad.swift`) — the CM-Pro hard-key pad. `KeyFace`: `digit` (white),
  `op` (warm chip), `equals` (signal), `dim` (white + signal underline: Feet/Inch/⁄),
  `function` (graphite: Rise/Run/Diag/Pitch — solve in place), `nav` (graphite + signal
  caption: Rafter/Stair/Area/Vol — open the matching formula), `edit` (muted: C/⌫).
- **FormulaCard** (`KCFormulaCard.swift`) — dark card showing the actual formula, a green
  VERIFIED badge tied to the oracle test, the cited standard, and an optional worked example.

---

## 6. Spec tab (the CM-Pro reuse, done light)

The keypad keeps the muscle memory — value, then a dimension or function key — but only the
*most-used* hard keys sit on the pad (Rise/Run/Diag/Pitch solve inline; Rafter/Stair/Area/Vol
hand the current value off to the full formula screen). The dark readout carries a faint tape
line, the ft-in-frac result, stored Rise/Run registers, and the precision pills (1/8 · 1/16 ·
1/32). Everything else stays in the validated `DimensionKit` engine.

---

## 7. Formulas tab (the differentiator)

Front door = a **searchable, 2-column trade grid** with a pinned **Favorites** row. Each tile:
a mono trade-tint **code badge** (`RAF`, `CNC`, …), name, subtitle, a **live sample readout**,
and a **star**. Every detail exposes the **formula + the code it cites** via `FormulaCard` —
this is the "bigger and better" claim made legible. Favourites persist with `@AppStorage`
(offline); seed `rafter, concrete, stairs`.

---

## 8. Cross-platform (iPhone · iPad · Mac)

Driven by **horizontal size class**, not device:

- **Compact** (iPhone portrait) → three tabs (**Spec · Formulas · Reference**); Formulas
  pushes to detail in a `NavigationStack`.
- **Regular** (iPhone landscape "Pro", iPad landscape, Mac) → `NavigationSplitView`: grouped
  sidebar (Favorites + trades) left, detail right; the detail lays inputs and outputs **side
  by side**. Landscape also earns the three-pane "Pro" layout (pad · tape/history · quick
  formulas).

Same tokens, `card`, `HeroReadout`, `StepperRow`, `ResultRow`, and the pill `SubScreenPicker`
everywhere; the trade accent still flows from one `.tint(tool.accent)`. See
`RootView.example.swift`.

---

## 9. Rules

**Do**
- One trade accent per tool, everywhere it appears.
- Monospaced digits for every number.
- Exactly one `HeroReadout` per screen; the hero colour is `signal` on graphite.
- Signal only on the loud things (`=`, hero, active, star).
- Glove-XL keys and steppers; ≥ 44pt targets.

**Must not change**
- The `*Kit` math packages and their oracle tests.
- The ViewModels — `@Published` inputs/outputs stay identical.
- The set of inputs & outputs each screen shows. Offline, system assets only.

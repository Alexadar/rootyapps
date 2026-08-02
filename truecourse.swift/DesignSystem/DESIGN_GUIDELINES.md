# TrueCourse — Design Guidelines

A universal E6B flight computer for student pilots, GA pilots, and CFIs — wind triangle,
airspeed, altitude, nav, fuel, climb/descent, weight & balance, and unit conversions across
iPhone, iPad, Mac, and Apple Watch. This system defines the look; the oracle-validated math
and the set of inputs/outputs per screen stay 1:1.

---

## 1. Direction

**Glass-cockpit instrument — honest and legible.** This is a safety and exam tool; the number
is the product. The identity:

- **Matte, near-black surface** — flat `#090C10`, no gradient wash. An optional faint
  section-accent glow at the top of a detail screen is the only light effect.
- **Numbers are the hero** — every value (inputs *and* results) is **SF Mono with tabular
  digits** so columns never jitter as values update. Exactly **one** emphasised hero readout
  per sub-screen, rendered large.
- **One accent per calculator group** — Wind / Airspeed / Altitude / Nav / Fuel /
  Climb·Descent / W&B / Convert each own a colour. The accent is the wayfinding system: it
  tints the tile glyph, the focus ring, the segmented control, and the hero readout's rule.
  It never fills a background behind digits — those stay maximum-contrast.
- **Avionics, not skeuomorphic** — no fake round whiz-wheel, no analog gauges. A single round
  E6B mark is allowed as an app/marketing motif only.
- **Cockpit-readable** — high contrast, sunlight-legible off-white text (never pure `#FFF`,
  which blooms), glove-sized targets (≥ 44pt).

---

## 2. Colour tokens  (`TCColors.swift`)

Tokens are theme-aware and read from the environment palette (`@Environment(\.tc)`).

### Dark (default)

| Token | Value | Use |
|---|---|---|
| `background`    | `#090C10` | full-bleed app background |
| `grouped`       | `#0D1218` | grouped-list / chart backdrop |
| `surface`       | `#141B23` | cards, tiles, segment track |
| `surfaceRaised` | `#1A232D` | result card & input fields |
| `pressed`       | `#233040` | unit chip / pressed |
| `hairline`      | `white 8%` | 1px card & segment stroke |
| `chipFill`      | `white 6%` | NumberField value chip |
| `textPrimary`   | `#EAEFF4` | values, tool names (soft, not `#FFF`) |
| `textSecondary` | `#95A2B1` | labels |
| `textTertiary`  | `#616D7B` | units, hints |
| `brand`         | `#39C6DC` | primary control, focus |
| `caution / warning / normal` | `#F2B441 / #FF5D5D / #45D18A` | amber / red / green — cockpit convention |

### Section accents (single source of wayfinding colour)

| Section | Accent | Hex |
|---|---|---|
| Wind             | cyan   | `#35C4DE` |
| Airspeed         | green  | `#47D18A` |
| Altitude         | sky    | `#5B9BFF` |
| Nav              | magenta| `#E766C8` |
| Fuel             | amber  | `#F2A93E` |
| Climb / Descent  | violet | `#8E8CFF` |
| Weight & Balance | coral  | `#FF8A5B` |
| Convert          | steel  | `#8B98A9` |

Resolve as `tc.accent(section)`. Set `.tint(tc.accent(calc.section))` once at the detail
level and `ResultRow(emphasis:)` + `SubScreenPicker` inherit it.

### Night (red-shift) — the differentiator

A single token swap (`.tcTheme(.night)`) shifts the whole system to a low-blue red palette so
no cool light reaches a night flight deck. Background `#0A0304`, text `#FF6A52`; **all section
accents collapse to a warm monochrome-red scale** — the grouping survives, the blue does not.
Toggle it from one toolbar button (`ThemeStore`); the choice persists via `@AppStorage`.

---

## 3. Shape & spacing

- Radii: card **18**, tile **14**, field **12**, chip / segment pill **8**, segment track **12**.
- Card padding **16**. Grid gap **11**. Screen margin **16**.
- Hit targets ≥ **44pt** — used one-handed, in turbulence, sometimes gloved.

---

## 4. Type

- System font (SF Pro) for the interface — offline, no remote fonts.
- Large title (app / screen name) 34 bold, tracking −0.6. Headline (tile) 17 semibold.
  Body 16. Label: **monospaced**, uppercased, tracking 1.2–1.4.
- **All numbers monospaced** — `.system(_, design: .monospaced)` + `.monospacedDigit()`.
- Hero readout ≈ **54pt** semibold mono, `minimumScaleFactor(0.5)` so it scales with Dynamic
  Type down to the Watch. Units are a smaller secondary weight beside it.

---

## 5. Components

- **Card** — `.instrumentCard()` (matte, hairline). `raised: true` for the result card; wrap
  the hero row in `ResultCard(accent:)` for the section-accent leading rule.
- **CardHeader** — mono, uppercased, tertiary; optional trailing accent value.
- **NumberField** — uppercased mono label + inline range hint; large mono value; fixed-width
  unit chip; decimal pad on iOS; focused state shows the section-accent ring + halo.
- **ResultRow** — label ↔ mono value; `emphasis` renders the hero size (digits stay
  max-contrast, the accent lives in the rule/tint, not the number fill).
- **SubScreenPicker** — pill segmented control; selected pill fills with `.tint`. Replaces
  `.pickerStyle(.segmented)`.
- **CatalogTile / SectionLabel** — accent glyph + name + subtitle; mono accent-ticked group
  header.
- **WindTriangleView / CGEnvelopeChart** — the two hero visuals (§ Charts).

---

## 6. The two hero visualizations  (`TCCharts.swift`)

- **Wind triangle** — `Canvas` vector triangle: air (TAS/heading) + wind = ground (track/GS),
  over a compass ring with an aircraft glyph at the origin rotated to heading. Colours map to
  the Wind / Nav / Fuel accents. Feed the `WindSolution` your ViewModel computes.
- **CG envelope** — **Swift Charts**: axes, gridlines, and points from the chart; the filled
  category-envelope polygon is drawn in a `chartOverlay` mapped through the chart proxy. The
  loaded point is green inside the envelope, red outside; a dashed line shows takeoff→landing
  travel as fuel burns.

Both are VoiceOver-labelled with the solved values and recolour with the theme.

---

## 7. Cross-platform (iPhone · iPad · Mac · Watch)

One codebase, four idioms, driven by **horizontal size class** — not device:

- **Compact width** (iPhone, narrow multitasking) → catalog is a full-screen grouped grid in
  a `NavigationStack` that pushes to detail; inputs and readout **stack**.
- **Regular width** (iPad landscape, Mac, wide multitasking) → the same screens become a
  `NavigationSplitView`: grouped sidebar (Favorites + sections) on the left, detail on the
  right; inputs and readout sit **side by side**.
- **watchOS** → the input-light tools only: one Digital-Crown input, one hero readout, two
  compact stats. Same tokens and mono figures.

Orientation follows the same rule:

- **iPhone landscape** = compact *height* → keep the stack nav, but lay inputs and the
  hero readout side by side (inputs grid left, `ResultCard` right).
- **iPad portrait & landscape** are both regular width → the split view never collapses;
  portrait narrows the sidebar (short labels), landscape gives detail room to put the
  chart beside the inputs.
- **Mac** → same regular layout in a freely resizable window; minimum content width 720 pt.

Everything else is identical across platforms: same palette, `instrumentCard`, `NumberField`,
`ResultRow`, `SubScreenPicker`; the accent still flows from one `.tint`. See
`RootView.example.swift` for the size-class switch and `WatchReadout.example.swift` for the
watch layout.

---

## 8. Accessibility (non-negotiable)

- **Dynamic Type** — the hero readout scales with the system text size and stays legible at
  every step, down to the Watch (`minimumScaleFactor`).
- **Contrast** — all text meets WCAG AA on its surface; text is never pure white.
- **VoiceOver** — every readout speaks its value and unit ("True airspeed, 124.6 knots");
  inputs announce their range and current value; both charts carry a spoken summary.

---

## 9. Rules

**Do**
- One section accent per calculator, everywhere it appears.
- Monospaced tabular digits for every number.
- Exactly one hero readout per sub-screen; reserve the largest type for the computed answer.
- Show input ranges and units inline on every field.

**Don't**
- Skeuomorphic whiz-wheels or fake analog gauges.
- Gradients or glows behind the readout digits.
- Pure `#FFFFFF` text (it blooms in sunlight); proportional figures; emoji; decorative icons.

**Must not change**
- The oracle-first `*Kit` math packages and their tests.
- The ViewModels — `@Published` inputs/outputs stay identical.
- The set of inputs & outputs each screen shows. Offline, system assets only.

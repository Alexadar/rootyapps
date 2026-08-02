# Aurora HUD — Design Guidelines

The space-weather tracker as an **esports broadcast HUD**: the Sun and Earth are the two
sides of a live match, the panels are the stat cards, and severity is the scoreline. The
oracle-validated math and the set of inputs/outputs per panel stay 1:1.

---

## 1. Direction

**Broadcast HUD — competitive, legible, restrained.** Stat-overlay energy without stat-overlay
noise:

- **Matte arena black** — flat `#080B14`, no gradient wash, no glass blur. An optional faint
  side-accent glow at the very top of a screen is the only light effect.
- **Numbers are the score** — every value is **SF Mono with tabular digits**. Exactly **one**
  hero readout per panel, rendered large. Digits stay maximum-contrast; accents live in
  rules, ticks, and fills — never behind digits.
- **The matchup is the color system** — restrained-palette discipline (learned from the
  product design pass): neutral surfaces + one brand tint + a 3-step severity ramp. The only
  thematic hues are the two sides: **Solar amber** for Sun-origin panels (flares, X-ray,
  solar activity, radio) and **Terra mint** for Earth-response panels (Kp, Hp30, aurora),
  with **steel** for the solar-wind link between them. Never more than one accent per card.
- **Chamfered, not rounded** — the esports signature is the cut corner. Cards are sharp
  (r 6) with a 12pt 45° chamfer on the top-trailing corner. No pill bubbles except segments.
- **HUD ticks** — the `//` double-tick is the one decorative motif (panel headers, section
  labels, the wordmark). No emoji, no decorative icons, no scanlines, no glitch effects.
- **Field-readable** — aurora chasers use this outdoors at night: high contrast, soft
  off-white (never pure `#FFF`), ≥44pt targets, and a one-tap red-shift Night theme.

---

## 2. Colour tokens  (`SWColors.swift`)

Tokens are theme-aware and read from the environment palette (`@Environment(\.sw)`).

### Dark (default)

| Token | Value | Use |
|---|---|---|
| `background`    | `#080B14` | full-bleed app background |
| `grouped`       | `#0C111B` | grouped-list / chart backdrop |
| `surface`       | `#111826` | cards, tiles, segment track |
| `surfaceRaised` | `#17202F` | hero/result cards & fields |
| `pressed`       | `#202B3D` | chips / pressed |
| `hairline`      | `white 8%` | 1px card & segment stroke |
| `chipFill`      | `white 6%` | value chips |
| `textPrimary`   | `#E8EEF6` | values, panel titles (soft, not `#FFF`) |
| `textSecondary` | `#93A1B4` | labels, meaning lines |
| `textTertiary`  | `#5E6B7E` | units, sources, hints |
| `brand`         | `#4DF0A0` | the aurora mint — primary control, focus, Hp30 hero |
| `normal / caution / warning` | `#45D18A / #F2B441 / #FF5D5D` | the 3-step severity ramp |

### Side accents (the matchup — the only thematic color)

| Side | Accent | Hex | Panels |
|---|---|---|---|
| **Solar** (Sun)   | amber | `#FF8A3D` | Flares & X-ray, Solar activity, Radio (R) |
| **Terra** (Earth) | mint  | `#4DF0A0` | Kp, Hp30, Aurora, Geomagnetic (G) |
| **Link** (wind)   | steel | `#8B98A9` | Solar wind — the neutral connector |

Resolve as `sw.side(panel.side)`. Set `.tint(sw.side(…))` once per panel/screen and
`PanelHeader` + `SWSegmented` inherit it.

### Severity (semantic, replaces the 6-color NOAA rainbow)

`sw.severity(level)` collapses NOAA 0…5 to the cockpit ramp: **0 → normal**, **1–2 →
caution**, **3–5 → warning**. `sw.severity(flareClass:)` maps A/B/C → normal, M → caution,
X → warning. The full 6-step NOAA color band appears **nowhere**; the level *number*
("G3", "R1") carries the precision.

### Night (red-shift) — the differentiator

One token swap (`.swTheme(.night)`) shifts everything to a low-blue red palette so a phone
check doesn't cost the user their dark adaptation under the aurora. Background `#0A0304`,
text `#FF6A52`; **both side accents collapse to a warm monochrome-red scale** — the grouping
survives, the blue does not. Toggle from the root toolbar (`ThemeStore`), persisted via
`@AppStorage`.

| Token | Night value |
|---|---|
| `background / surface / surfaceRaised` | `#0A0304 / #190708 / #210A0B` |
| `textPrimary / textSecondary / textTertiary` | `#FF6A52 / #C4503C / #7E3226` |
| `brand` | `#FF7A5E` |
| `normal / caution / warning` | `#FF9B6E / #FF8A4C / #FF5236` |
| `solar / terra / link` | `#FF7B52 / #FF9B6E / #C85A44` |

---

## 3. Shape & spacing

- **Chamfer 12** on the top-trailing corner of every card (`ChamferBox`); base radius **6**.
- Radii: tile **5**, field **6**, chip **3**, segment pill **5**, segment track **6**.
- Card padding **14**. Grid gap **10**. Screen margin **16**. Hit targets ≥ **44pt** —
  used outdoors, at night, with cold fingers.

---

## 4. Type

- System font (SF Pro) for the interface — offline, no remote fonts.
- Screen title 28 heavy, tracking −0.4, uppercase wordmark style with a `//` tick.
- Labels: **SF Mono**, uppercased, caption2 semibold, tracking **1.6** — the scoreboard label.
- **All numbers monospaced** — `.system(_, design: .monospaced)` + `.monospacedDigit()`.
- Hero readout ≈ **54pt** semibold mono, `minimumScaleFactor(0.5)`. Units smaller, secondary.
- Meaning lines (the plain-language sentence under each panel) stay SF Pro footnote —
  prose is not a stat.

---

## 5. Components

- **Card** — `.swCard()` (same name as today): matte chamfered surface + hairline.
  `highlighted: true` uses the raised surface for the hero panel (Hp30).
- **PanelHeader** — `//` tick in the current `.tint`, mono uppercased title, source cited
  trailing in tertiary mono. The citation is the trust moat — never drop it.
- **Panel** — unchanged API (`title:source:observedAt:highlighted:`); adds the tick and
  keeps `StaleBadge` (amber past 15 min).
- **MetricTile** — mono value + fixed unit + label. Default ink is `textPrimary`; pass a
  color **only** when it is `sw.severity(…)`, `sw.side(…)`, or `sw.brand`.
- **ScaleChip** — the G/R/S chip: level 0 renders as a neutral outlined chip (quiet is not
  an event); levels 1+ fill with `severity` and dark ink. Chamfered, not rounded.
- **FlagPill** — on-state fills with `caution` at 20%; off-state is outlined tertiary.
- **SWSegmented** — chamfer-track segmented control; selected pill fills with `.tint`.
  Replaces every `.pickerStyle(.segmented)`.

---

## 6. The three charts  (`SWCharts.swift`)

- **Hp30 match timeline** (hero) — brand-tinted monotone line + area fade over the grouped
  backdrop; the G1 threshold is a dashed `caution` rule; the newest reading gets a live
  point. 30-minute cadence is the differentiator — frame it like a live match feed.
- **Kp scoreboard** — bars are neutral steel while quiet (< 4); they take `severity` color
  only when a level is actually in play. Forecast bars ghost to 40%. Y-grid at 0/3/5/7/9.
- **X-ray flux** — the flux line is off-white; the C/M/X class rules are
  normal/caution/warning. The line is the data; the bands are the meaning.

All three recolour with the theme and carry VoiceOver summaries of the latest value.

---

## 7. Cross-platform (iPhone · iPad · Mac · Watch · widgets)

One codebase, driven by **horizontal size class** — not device:

- **Compact width** → the current single-column dashboard in a `NavigationStack`; tabs via
  `SWSegmented`.
- **Regular width** (iPad landscape, Mac) → two-column grid of the same panels
  (`LazyVGrid`, max 640pt columns); the header wordmark and matchup strip span the top.
- **watchOS** (future target) → one hero readout + two stats, same tokens
  (`WatchReadout.example.swift`).
- **Widgets / Live Activities** → same palette; small = Kp hero + severity, medium = Kp +
  24h bars. Night theme follows the app setting.

---

## 8. Accessibility (non-negotiable)

- **Dynamic Type** — hero readouts scale with `minimumScaleFactor`; layouts stack, never clip.
- **Contrast** — WCAG AA on every surface, in both themes; text never pure white.
- **Color independence** — severity is always paired with its level text ("G3"); the ramp is
  reinforcement, never the only signal.
- **VoiceOver** — every readout speaks value + unit + meaning ("Planetary Kp, 5.3, minor
  storm"); charts carry a spoken summary of the latest reading and threshold state.

---

## 9. Rules

**Do**
- One side accent per panel, resolved through `sw.side(…)`; severity only through
  `sw.severity(…)`.
- Monospaced tabular digits for every number; one hero readout per panel.
- Cite the data source in every `PanelHeader`; show data age; go amber when stale.
- Chamfer the top-trailing corner of every card — it is the identity.

**Don't**
- The 6-color NOAA rainbow (the level number carries precision; the ramp carries urgency).
- Gradients or glows behind digits; glass blur; pure `#FFFFFF`; emoji; decorative icons.
- More than one accent hue inside a single card.
- Skeuomorphic magnetospheres or fake radar sweeps — charts are honest plots.

**Must not change**
- The oracle-first `SpaceWeatherKit` packages and their tests.
- `SpaceWeatherStore` and the `@Published` snapshot — inputs/outputs stay identical.
- The set of metrics each panel shows, and every source citation. Offline, system assets only.

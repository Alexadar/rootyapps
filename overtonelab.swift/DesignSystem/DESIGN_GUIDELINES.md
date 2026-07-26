# Overtone Lab — Design Guidelines

A calculation studio for musicians, instrument builders, and audio engineers — 10 precision
tools in 4 sections. This redesign keeps the app's function 1:1 and changes only the look.

---

## 1. Direction

**Studio instrument, not generic glass.** The old look was a violet gradient with
glass-on-glass cards and one accent everywhere. The redesign:

- **Near-black studio surface** — flat `#08080B`, no gradient wash, no radial glow (optional
  faint section-accent glow at the top of a tool screen only).
- **One accent per section** — Tuning / Acoustics / Signal / Design each own a colour. The
  accent is the wayfinding system: it tints the tool icon, the sample readout, the segmented
  control, and the one hero result per screen.
- **Numbers are the hero** — every value (inputs *and* results) is monospaced with tabular
  digits so columns align. Exactly **one** emphasised (hero) readout per sub-screen, in the
  section accent.
- **Matte cards** — surface `#141419`, 1px hairline stroke, radius 20. No `.glassEffect` on
  cards.
- **One Liquid Glass surface** — the navigation bar (kept default-glass per the HIG). That's
  the only place glass lives.

---

## 2. Colour tokens  (`OTLColors.swift`)

| Token | Value | Use |
|---|---|---|
| `background`    | `#08080B` | full-bleed app background |
| `surface`       | `#141419` | cards, tiles, segmented track |
| `surfaceRaised` | `#16161D` | the result/readout card |
| `hairline`      | `white 6%` | 1px card/segment stroke |
| `chipFill`      | `white 5%` | NumberField value chip |
| `textPrimary`   | `#F5F5F7` | values, tool names |
| `textSecondary` | `#9A9AA6` | labels |
| `textTertiary`  | `white 30%` | units, chevrons |
| `star`          | `#F2C14E` | favourite star (filled) |

### Section accents (single source of wayfinding colour)

All **seven** sections own an accent — the four originals plus Timing, Stereo and Utility, added with
the tools that followed. Catalog order is Timing · Tuning · Acoustics · Signal · Stereo · Utility ·
Design; the hues run cool → warm across that order so neighbouring groups stay distinguishable.

| Section | Accent | Hex |
|---|---|---|
| Timing    | blue   | `#5B8DEF` |
| Tuning    | amber  | `#F2B84B` |
| Acoustics | aqua   | `#43C8C0` |
| Signal    | violet | `#8B7BF0` |
| Stereo    | green  | `#6FCF97` |
| Utility   | rose   | `#E08AA0` |
| Design    | coral  | `#F0785A` |

The values above mirror `OverToneLab/Views/OTLColors.swift`, which is the source of truth — a new
section MUST add its case there (the switch is exhaustive, so the compiler will tell you) and MUST be
listed here.

**Contrast (measured, WCAG relative luminance):** every accent clears **4.5:1 against all three
surfaces** — `background` `#08080B`, `surface` `#141419`, `surfaceRaised` `#16161D`. Worst case is
Signal violet at **5.31:1** on `surfaceRaised`; best is Tuning amber at 11.18:1 on `background`.
That headroom is what lets the hero readout be pure accent rather than accent-on-white. Re-check any
new accent at ≥ 4.5:1 on `surfaceRaised` (the tightest of the three).

Exposed as `ToolSection.accent` / `Tool.accent`. Set `.tint(tool.accent)` once at the detail
level and `ResultRow(emphasis:)` + `SubScreenPicker` inherit it.

---

## 3. Shape & spacing

- Radii: card **20**, tile **16**, chip / segment pill **8–9**, segmented track **12**.
- Card padding **16**. Grid gap **9–12**. Screen margin **16–18**.
- Hit targets ≥ **44pt**.

---

## 4. Type

- System font (SF Pro) — offline, no remote fonts.
- Large title (app / tool name) 34 bold, tracking −0.6.
- Headline (tile name) 17 semibold. Body / label 15. Caption label: **monospaced**,
  uppercased, tracking 1.
- **All numbers monospaced** (`.system(_, design: .monospaced)`, `.monospacedDigit()`).
- Hero readout ≈ title2 (28pt) semibold, in the section accent.

---

## 5. Components

- **Card** — `.glassCard()` (now matte). `raised: true` for the result card.
- **CardHeader** — mono, uppercased, secondary; optional trailing accent value.
- **NumberField** — label ↔ value; value is a mono chip on `chipFill`; tertiary fixed-width
  unit; decimal pad on iOS.
- **ResultRow** — label ↔ mono value; `emphasis` renders the hero size in the section accent.
- **SubScreenPicker** — pill segmented control; selected pill fills with `.tint`
  (the section accent). Replaces `.pickerStyle(.segmented)`.
- **Nav bar** — default Liquid Glass; back control tinted with the accent. The lone glass
  surface.

---

## 6. Catalog — direction 1b (chosen)

Front door = a **2-column instrument grid, grouped under each section header**. Each tile:
section-accent top bar, tool icon (accent), name, subtitle, and a **live sample readout** in
mono accent, plus a **star**.

**Favourites.** A star on every tile toggles membership of a **Favorites** group pinned above
the section groups. Favourited tools keep their own section accent. Persist ids with
`@AppStorage` (offline, no account) — see `FavoritesStore.swift`. Seed with
`partch, benchmark`.

---

## 7. Cross-platform (iPhone · iPad · Mac)

Universal SwiftUI, iOS + macOS 26 — one codebase, three idioms. The layout is driven by
**horizontal size class**, not device:

- **Compact width** (iPhone, iPad multitasking narrow) → the catalog is a full-screen grouped
  grid inside a `NavigationStack` that pushes to detail. This is directions 1b / the prototype.
- **Regular width** (iPad landscape, Mac, wide multitasking) → the same screens become a
  **`NavigationSplitView`**: grouped sidebar (Favorites + sections, one row per tool) on the
  left, tool detail on the right. On regular width the detail lays inputs and outputs out
  **side by side**; on compact they stack.

Everything else is identical across platforms: same tokens, `glassCard`, `NumberField`,
`ResultRow`, and the pill `SubScreenPicker`; the section accent still flows from one
`.tint(tool.accent)`. The window titlebar / nav bar stays the single Liquid Glass surface.
Mac window default 820×900 (`.windowResizability(.contentSize)` already set).

See `RootView.example.swift` for the size-class switch and the split-view sidebar.

---

## 8. Rules

**Do**
- One section accent per tool, everywhere it appears.
- Monospaced digits for every number.
- Exactly one hero readout per sub-screen.
- Liquid Glass on the nav bar only; cards are matte.

**Must not change**
- The `*Kit` math packages and their oracle tests.
- The ViewModels — `@Published` inputs/outputs stay identical.
- The set of inputs & outputs each screen shows. Offline, system assets only.

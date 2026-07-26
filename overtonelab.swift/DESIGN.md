# Overtone Lab — Design reference

> This started as a redesign brief. **The redesign has since been built and shipped** (macOS 1.0 live
> 2026-07-09), so this file now describes the app as it actually is. The math, data flow, and
> functionality are final; anything visual is still open, within the rules in §4.
> Token-level detail lives in `DesignSystem/DESIGN_GUIDELINES.md` — that and the code are the source
> of truth for colour; this file is the map.

---

## 1. What the app is
**Overtone Lab** is an offline calculation studio for musicians, instrument builders and audio
engineers — **26 precision tools in 7 sections**. It began as a consolidation of 10 formerly
standalone calculators into one app (App Store 4.3: one substantial app, not many thin ones) and has
roughly doubled since. Each tool is exact and reference-validated (`docs/VALIDATION.md`).

- **Platforms:** universal SwiftUI, iOS + macOS, deployment target **26.0** (Liquid Glass era).
- **Offline, private:** no network, no account, no analytics. Sandbox-only. Buy once, $9.99.
- **Aesthetic:** dark studio-instrument — flat near-black `#08080B`, matte cards, **one accent per
  section**, monospaced numbers. Liquid Glass is confined to the nav bar.
- **Bundle:** `oleksandr.aisixteen.overtonelab` · product name `Overtone Lab` · category Music.

---

## 2. Sections → tools → sub-screens
Navigation adapts to horizontal size class: **compact** (iPhone) = grouped 2-column catalog grid in a
`NavigationStack` that pushes to detail; **regular** (iPad landscape / Mac) = `NavigationSplitView`
with a grouped sidebar. In both, a tool's sub-screens are swapped by a pill `SubScreenPicker`.

| Section | Accent | Tool | Sub-screens |
|---|---|---|---|
| **Timing** | blue `#5B8DEF` | Tempo | Note · Tempo · Samples · Varispeed |
| | | Delay | Tempo · Distance · Comb |
| | | Timecode | Frames → TC · TC → Frames |
| | | Pitch | Note↔Freq · Harmonics · Beats · Doppler |
| **Tuning** | amber `#F2B84B` | Partch | Interval · Ratio · Reference |
| | | Comma | EDO · Interval · Temperament |
| | | Mersenne | Tension · Frets · Reference |
| **Acoustics** | aqua `#43C8C0` | Sabine | Reverb · Modes · Reference |
| | | Webster | Horn · Helmholtz · Reference |
| | | Bernoulli | Pipe · End · Reference |
| | | Formant | Vocal Tract · Vowels · Reference |
| | | SPL | Distance · Summation · Reference |
| | | Room Modes | Modes · Ratio · Reference |
| | | Air | Absorption · Reference |
| | | SBIR | Boundary · Two-source · Reference |
| **Signal** | violet `#8B7BF0` | Butterworth | Filter · Crossover · Reference |
| | | Fletcher | Weighting · Reference |
| | | Benchmark | Tone · Target · Reference |
| | | Passive | RC / RL · LC · Reference |
| | | Biquad | Design · Reference |
| | | Compressor | Gain · Time · Reference |
| **Stereo** | green `#6FCF97` | SRA | Array · Presets · Reference |
| **Utility** | rose `#E08AA0` | Levels | dB Convert · Compare · Dynamic Range |
| | | File | File Size · Sample Rate |
| | | Pan | _single screen_ |
| **Design** | coral `#F0785A` | Thiele | Driver · Sealed · Ported · Reference |

Most tools also carry a **Reference** screen: 3–4 explanatory cards (concept, formula, caveats).
`ToolCatalog.swift` is the single source of truth for titles, subtitles and SF Symbols;
`OTLColors.swift` for accents and each tile's live sample readout.

---

## 3. Structure & files
```
overtonelab.swift/
  OverToneLab/
    OverToneLabApp.swift        @main
    ContentView.swift           → RootView
    Views/
      RootView.swift            size-class switch: grid+NavigationStack | NavigationSplitView
      RootCatalogView.swift     the compact catalog grid (section groups + Favorites)
      ToolDetailView.swift      SubScreenPicker + the tool's sub-view
      ToolCatalog.swift         enum Tool + ToolSection (title, subtitle, SF Symbol)
      OTLColors.swift           tokens + ToolSection.accent + Tool.sample   ← colour source of truth
      OTLSegmented.swift        SubScreenPicker (pill segmented control)
      Theme.swift               .glassCard(), CardHeader
      Components.swift          NumberField, ResultRow
      FavoritesStore.swift      @AppStorage favourite ids
      AppBackground.swift · ColorHex.swift · Format.swift
    Tools/<Section>/<Tool>/
      <Tool>ToolView.swift      wrapper: owns the VM + sub-screen picker
      <VM>.swift                @MainActor ObservableObject (math bridge — DO NOT change)
      <SubScreen>View.swift     card layouts (inputs + results)
  Kits/<Section>/<Kit>/         22 pure-math SPM packages + oracle tests (DO NOT change)
  DesignSystem/                 tokens/components staging + DESIGN_GUIDELINES.md (not in the build)
  overtonelabUITests/           ValueChecks · FavoritesChecks · ReelTour
  marketing/                    raw captures, aso output, reels config, metadata.md
```

`DesignSystem/` is **not** compiled — it duplicates several primitives that now live in
`OverToneLab/Views/`. Edit the ones under `Views/`; adding `DesignSystem/` to `project.yml` would
double-declare the types.

### Shared component API (restyle internals, keep the call sites)
- `SomeView.glassCard(cornerRadius:raised:)` → matte padded card
- `CardHeader(title:, trailing:)` → small uppercased mono label inside a card
- `NumberField(title:, value: $Double, unit:, range:)` → labeled numeric input (decimal pad on iOS)
- `ResultRow(label:, value:, unit:, emphasis:)` → label ↔ value; `emphasis` = the one hero number
- `SubScreenPicker(titles:, selection:)` → pill segmented control, fills with the section accent
- `Color(rgbHex: 0xRRGGBB)` · `Fmt.f/signed/pct/deg/secs` · `AppBackground()`

---

## 4. Design rules
1. **One product, not 26 bolted together.** The catalog is the front door; section identity carries it.
2. **Numbers are the hero.** All numbers monospaced with tabular digits; exactly **one** emphasised
   readout per sub-screen, in the section accent.
3. **Matte, not glass-on-glass.** Cards are `#141419` with a hairline stroke; Liquid Glass only on the
   nav bar.
4. **The accent is the wayfinding system.** Set `.tint(tool.accent)` once at detail level and let
   `ResultRow(emphasis:)` and `SubScreenPicker` inherit it.
5. **Universal.** Right on iPhone, iPad and Mac from one codebase, driven by size class.

**Free to change:** layout, spacing, type scale, card styling, catalog presentation, motion, icons,
accents, empty/loading polish, app icon.

**Must not change:** the `*Kit` packages and their oracle tests, the ViewModels' `@Published`
inputs/outputs, and the set of inputs/outputs each screen shows. Stay offline (system assets only,
no remote fonts/images/CDNs). Keep it building on iOS/macOS 26.

---

## 5. Running it / navigating for captures
Scheme `overtonelab.swift` (`overtonelabReel` for the UITest tour). Two launch env hooks jump
straight to a screen:
- `OVERTONELAB_TOOL=<tool>` — the `Tool` enum raw value, e.g. `partch`, `sabine`, `benchmark`,
  `thiele`, `roommodes`, `sbir`.
- `OVERTONELAB_SCREEN=<index>` — 0-based sub-screen.

Capture scripts: `make_sim_shots.sh` (iPhone/iPad), `make_mac_shots.sh` (Mac window via Quartz +
`screencapture`), `make_all_reels.sh` / `make_mac_reel.sh` (reels). App-Store preview videos must be
rendered by `marketing/reels/store_preview.py` — **framed reels are a Guideline 2.3.4 rejection**.

---

## 6. Reference
- Apple **Adopting Liquid Glass** HIG (glass materials, toolbars, tab bars).
- `DesignSystem/DESIGN_GUIDELINES.md` — tokens, radii, type scale, component rules.
- `docs/VALIDATION.md` — the oracle policy every displayed number answers to.

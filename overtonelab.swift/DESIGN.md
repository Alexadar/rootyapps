# Overtone Lab — Design Handoff

> Brief for a visual redesign. The **math, data flow, and functionality are final** — this pass is about the *look*: layout, hierarchy, color, typography, motion, and the browse/detail experience. Keep every input and output; make it feel like one premium, coherent product.

---

## 1. What the app is
**Overtone Lab** is an offline calculation studio for musicians, instrument builders and audio engineers — **10 precision tools in 4 sections**. It's a consolidation of 10 formerly-standalone calculators into one app (App Store 4.3: one substantial app, not many thin ones). Each tool is exact and reference-validated.

- **Platforms:** universal SwiftUI, iOS + macOS, deployment target **26.0** (Liquid Glass era).
- **Offline, private:** no network, no account, no analytics. Sandbox-only.
- **Current aesthetic:** dark-first, Liquid Glass cards over a violet gradient. Accent violet `#8A6BE0` (rgb 138,107,224).
- **Bundle:** `oleksandr.aisixteen.overtonelab` · category Music.

---

## 2. Sections → tools → sub-screens
Navigation today: **Catalog** (browse, grouped by section) → tap a tool → **Tool detail** (a segmented picker swaps the tool's sub-screens). Every sub-screen is a stack of glass cards with labeled inputs and emphasized results.

**20 tools across 6 sections** (order: Timing · Tuning · Acoustics · Signal · Utility · Design).

| Section | Tool | Sub-screens | What it does |
|---|---|---|---|
| **Timing** | Tempo | Note · Tempo · Samples · Varispeed | Note/bar length, time↔samples, varispeed |
| | Delay | Tempo · Distance · Comb | Tempo-sync delay, distance/alignment, comb notch |
| | Timecode | Frames→TC · TC→Frames | SMPTE 24/25/30 + 29.97 drop-frame |
| | Pitch | Note↔Freq · Harmonics · Beats · Doppler | 12-TET note/freq/wavelength, harmonics, beats, Doppler |
| **Tuning** | Partch | Interval · Ratio · Reference | Just intonation — cents, nearest just ratio, Tenney, 12-TET dev |
| | Comma | EDO · Interval · Temperament | Equal divisions, interval analysis, meantone/temperament |
| | Mersenne | Tension · Frets · Reference | String tension↔frequency, fret spacing |
| **Acoustics** | Sabine | Reverb · Modes · Reference | Room RT60 (Sabine/Eyring), Schroeder freq, axial modes |
| | Webster | Horn · Helmholtz · Reference | Exponential-horn cutoff/flare, Helmholtz resonance |
| | Bernoulli | Pipe · End · Reference | Open/closed pipe resonance, end correction |
| | Formant | Vocal Tract · Vowels · Reference | Vocal-tract formants (quarter-wave) + Peterson-Barney vowels |
| | SPL | Distance · Summation · Reference | Inverse-square distance law, source summation |
| **Signal** | Butterworth | Filter · Crossover · Reference | Filter magnitude/dB, Linkwitz-Riley crossover |
| | Fletcher | Weighting · Reference | A / C / Z frequency weighting |
| | Benchmark | Tone · Target · Reference | ITU-R BS.1770 integrated LUFS, streaming targets |
| | Passive | RC/RL · LC · Reference | Real-component RC/RL/LC corner & resonance |
| **Utility** | Levels | dB Convert · Compare · Dynamic Range | dBu/dBV, voltage/power ratios, bit-depth dynamic range |
| | File | File Size · Sample Rate | Uncompressed size, Nyquist |
| | Pan | Pan Law | Equal-power / linear / compromise pan gains |
| **Design** | Thiele | Driver · Sealed · Ported · Reference | Thiele-Small: box Qtc/Fc/F3, vented port length |

Every tool also has a **Reference** screen: 3–4 explanatory cards (concept, formula, caveats).

---

## 3. Current structure & files (what you'll restyle)
```
overtonelab.swift/
  OverToneLab/
    OverToneLabApp.swift        @main
    ContentView.swift           → RootCatalogView
    Views/
      AppBackground.swift       gradient + radial violet glow   ← restyle
      Theme.swift               .glassCard(), CardHeader          ← restyle
      Components.swift          NumberField, ResultRow            ← restyle
      ColorHex.swift            Color(rgbHex:)                    (keep)
      Format.swift              Fmt.f / signed / deg / pct / …    (keep)
      ToolCatalog.swift         enum Tool + ToolSection (metadata: title, subtitle, SF Symbol)
      RootCatalogView.swift     browse: NavigationStack + section groups + glass rows  ← redesign
      ToolDetailView.swift      ScrollView + SubScreenPicker (segmented) + sub-view    ← redesign
    Tools/{Tuning,Acoustics,Signal,Design}/<Tool>/
      <Tool>ToolView.swift      wrapper: owns VM + sub-screen picker
      <VM>.swift                @MainActor ObservableObject (math bridge — DO NOT change)
      <SubScreen>View.swift     glass-card layouts (inputs + results)  ← restyle
  Kits/{Tuning,Acoustics,Signal,Design}/<Kit>/   pure-math SPM packages + oracle tests (DO NOT change)
```

### Shared component API (used by every sub-screen — restyle the internals, keep the call sites)
- `SomeView.glassCard(cornerRadius: 22)` → padded card with `.glassEffect(.regular, in:)`
- `CardHeader(title:, trailing:)` → small uppercased section label inside a card
- `NumberField(title:, value: $Double, unit:)` → labeled numeric input row (decimal pad on iOS)
- `ResultRow(label:, value:, emphasis: Bool)` → label ↔ value row; `emphasis` = the headline number
- `Color(rgbHex: 0xRRGGBB)` · `Fmt.f(x, places)`, `Fmt.signed`, `Fmt.pct`, `Fmt.deg`, `Fmt.secs`
- `AppBackground()` → full-bleed background behind every screen

Sub-screens are `VStack(spacing: 16)` of `.glassCard()` blocks: a header, `NumberField` inputs, then `ResultRow` outputs (the key number uses `emphasis: true` and the accent tint), sometimes a caption footnote.

---

## 4. Design goals
1. **Feel like one product, not 10 bolted together.** The catalog is the front door — make section identity and tool discovery beautiful and obvious.
2. **Numbers are the hero.** These are calculators; results must be instantly scannable — strong typographic hierarchy between labels, inputs, and the emphasized answer.
3. **Premium Liquid Glass.** Tasteful depth, legibility over glass, dark-first (consider a light variant). No glass-on-glass mud.
4. **Section color language (optional).** Today everything is one violet. You may give each section a distinct accent (Tuning/Acoustics/Signal/Design) while keeping a unified family — or keep one accent. Your call.
5. **Universal.** Looks right on iPhone, iPad, and Mac (the detail max-width is currently 640).

### Free to change
Layout, spacing, type scale, card styling, the catalog presentation (list vs. grid vs. hero cards), how sub-screens are switched (segmented today — could be tabs, a menu, or a single scroll), icons/symbols, accent(s), motion, empty/loading polish, app icon.

### Must not change
The `*Kit` math packages, the ViewModels (`@Published` inputs/outputs), and the set of inputs/outputs each screen shows. Stay offline (no remote fonts/images/CDNs — inline/system assets only). Keep it building on iOS/macOS 26.

---

## 5. Running it / navigating for screenshots
Build scheme `overtonelab.swift`. Two launch env hooks jump straight to a screen (used for captures):
- `OVERTONELAB_TOOL=<tool>` — e.g. `partch`, `sabine`, `benchmark`, `thiele` (the `Tool` enum raw values).
- `OVERTONELAB_SCREEN=<index>` — 0-based sub-screen.

Current screenshots (first functional cut, to be replaced): `overtonelab.swift/marketing/raw/ios/`.

---

## 6. Reference
- Apple **Adopting Liquid Glass** HIG (glass materials, toolbars, tab bars).
- Accent today `#8A6BE0`; background `#0C0A18 → #161029` with a `#5B3A9E` radial glow at top.
- Tool metadata (titles, subtitles, SF Symbols) lives in `ToolCatalog.swift` — the single source of truth for the catalog.

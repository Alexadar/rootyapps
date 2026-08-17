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

| Section | Accent | Hex |
|---|---|---|
| Tuning    | amber  | `#F2B84B` |
| Acoustics | aqua   | `#43C8C0` |
| Signal    | violet | `#8B7BF0` |
| Design    | coral  | `#F0785A` |

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

## 8. Apple Watch (watchOS 26, dark only)

A 26-tool catalog and a keyboardless 41 mm screen are incompatible, so the watch app is a
**curation, not a port**. Same tokens, same accents, same one-hero-readout rule.

**Ships (7)** — Tempo, Delay, Pitch, SPL, Sabine, Levels, Pan. One or two inputs, one number
out. **Cut (19)** — Thiele/Biquad (too many inputs), Room Modes/Formant (the answer is a
list), Air/SBIR/SRA (4+ inputs of crown work), Timecode/File (slower than a keyboard), and
the bench/studio tools that are read as curves or tables.

**Front door — "Straight In".** The app opens on the last-used tool already showing a number
(zero taps). Swipe/crown-page between the seven; long-press opens the picker. A bounded list
of seven is what makes this safe — over 26 it would be a maze.

**Digital Crown replaces every number field.** Tap a card to make it the crown target (accent
ring). Two-tier acceleration only — fine detent and fast spin, no third speed. Haptic detent
per step, stronger at limits. Hero recomputes live; no Done button.

| Quantity | Detent | Fast | Why |
|---|---|---|---|
| Tempo | 1 BPM | 5 BPM | Range 30–300 |
| Frequency | logarithmic | ⅓ octave | 40 Hz and 4 kHz feel the same |
| Note / pitch | 1 semitone | 1 octave | Snaps chromatic — never between notes |
| Room volume | 5 m³ | 25 m³ | Rooms are estimated; finer implies false precision |
| Distance | 0.5 m | 2 m | Sub-metre matters near a source |
| Level | 0.5 dB | 3 dB | Audible floor / power doubling |

**Tap tempo ships.** Four taps locks BPM to the mean of the last eight intervals, ±0.5 BPM,
haptic per tap. It is the one input the wrist does better than the phone.

**Layout rule — stack, never row.** Labels sit *above* their value. A side-by-side row breaks
the moment the label is a German compound (`Nachhallzeit`, `Schröder-Frequenz`); a stack just
gets taller and the number never moves or shrinks. No label is measured at English width.
49 mm buys a bigger hero (56 → 64 pt) and both inputs without scrolling — not more content.

**Notation is never CSS-uppercased.** `text-transform: uppercase` corrupts technical strings:
it cases `ΣSα` → `ΣSΑ`, where uppercase Alpha is glyph-identical to a Latin A, so the label
reads as the wrong quantity. Author caption labels in their final case instead, and keep
Greek/math symbols and superscripts (`m³`, `ΣSα`, `Qtc`) out of any uppercasing transform.

**Complication** — pins *one chosen tool*, not the app, and shows that tool's last computed
answer in its section accent (250 ms, 0.81 s). No network or timeline refresh; the value
changes only when the user does. Tapping opens that tool directly.

See `OTLWatch.example.swift` for the root, `CrownField`, `StackedReadout`, and `TapTempo`.

---

## 10. Audio Analysis (MusicUnderstanding — future OS)

A **source**, not tool #27. Analysis measures real audio and hands values to the existing
calculators. Same tokens, same accents, same one-hero-readout rule.

**Availability — absent, not disabled.** The Measure entry is appended to the catalog model
behind `#available`, so on the released SDK it is a missing array element: no tab, no greyed
row, no "coming soon", nothing reflows. `MeasurementStore`, the provenance chip, and the deep
links are all framework-independent and can ship in a patch with the row never inserted. The
mic usage description ships with the gated build only.

**Navigation — results outlive the stack.** `MeasurementStore` is a `@StateObject` on
`RootView`, a sibling of `FavoritesStore`. Analysis is an ordinary push, so popping it
discards a view and not a session: measure once → visit three calculators → back, intact.
The session is `Codable` end to end and persists on `scenePhase` change, so backgrounding and
cold start both survive. Re-opening Measure shows the last session with *Measure again*.

**Provenance — three signals, none of them colour.** A waveform glyph before the caption, a
2 pt dotted underline under the value, and the word *Measured* in the caption line. Editing
clears all three instantly — there is no "measured but modified". Provenance rides in
`accessibilityValue`, not a decorative image. Rotor actions: *Revert to typed*, and one that
reads the source.

**Routing.** BPM → `tempo`, `delay`. Key → `pitch`, `partch`, `comma`. Integrated/short-term
LUFS and peak → `benchmark` (peak also `levels`). Bars/sections → `timecode`. Instrument
activity → `sra`, `pan`. Every handed value lands in the input field and stays **fully
editable** — measurement is a starting point, never a lock. Parked on purpose: pace (nothing
consumes it), segments/phrases (too noisy at phone width), structure → room tools (the physics
does not support the link).

**The `benchmark` collision — choice (b), with a hard boundary.** Analysis measures loudness;
`benchmark` alone reasons about it. **Analysis renders no target, no delta, and no verdict** —
that single rule is what stops LUFS existing in two places, and it is easy to test: if a
screen compares against something, it is `benchmark`.

**BPM is optional.** `beatsPerMinute` is nil until two beats land. The UI shows
`—— listening`, never a zero and never a spinner that lies; Send buttons are absent (not
disabled) while nil.

**Time-series — bands, never curves.** Every value Apple returns is already a `CMTimeRange`, so
a smooth line would imply interpolation nobody measured; a band is also a hit target and an
accessibility element for free. Structure, pace, and instrument activity share **one ruler and
one playhead** so they read as one piece of audio. **Strength is height and a number, never
opacity alone.**

**The watchOS call — receive, never capture.** A wrist mic at hip height under a sleeve is not
a measurement this app can stand behind, sustained capture is expensive for a worse answer than
the phone in the same room, and a live meter has no crown target so it would be the first watch
screen to break `CrownFocusChecks`. Tap tempo already gets BPM more reliably. The watch
displays measured values with identical marking; the first crown detent overrides.

**New state axes** (all tested both directions): field provenance typed↔measured; revert
restores the pre-handoff value, not a default; session presence none/live/complete; BPM
nil/determined; framework absent/present; session cold/restored.

**New deep links** (existing `LaunchOverride` pattern): `OVERTONELAB_MEASURE=1`,
`OVERTONELAB_SESSION=<json>` (seeds a fixture session so UI tests can exercise provenance with
no microphone), `OVERTONELAB_TOOL=<t>&measured=1`.

**Known friction, stated rather than designed around:**
- `Tool` is a closed enum where every case implies a Kit and a detail view, so Measure cannot
  be a case of it. The catalog model becomes `.source(.measure) | .tool(Tool)` — the one
  structural change, touching `CatalogGrid` and the sidebar only.
- `ReelTour` must fork into two tours; a screenshot freezes its build.
- A `MeasureKit` oracle can only assert at the boundary (a −23 LUFS tone reads −23, a 120 BPM
  click reads 120). Section labels and pace have no ground truth and are passed through
  untested by design.
- Mic permission is a new first-run event for an app that has never asked for anything —
  triggered by the Listen button, never at launch.

See `OTLAnalysis.example.swift` for `CatalogEntry`, `MeasurementStore`, `MeasuredValue`, and
`BandTrack`.

---

## 11. Rules

**Do**
- One section accent per tool, everywhere it appears.
- Monospaced digits for every number.
- Exactly one hero readout per sub-screen.
- Liquid Glass on the nav bar only; cards are matte.

**Must not change**
- The `*Kit` math packages and their oracle tests.
- The ViewModels — `@Published` inputs/outputs stay identical.
- The set of inputs & outputs each screen shows. Offline, system assets only.

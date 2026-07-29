# Storypole — SwiftUI design templates

Drop-in design layer for the shipping build. **Every type and every initialiser keeps the name and
signature it already has**, so no call site in `Tools/`, `ContentView` or `WatchRootView` changes.
No arithmetic moved into a view; no number formatting, rounding or unit display was touched.

## Where each file goes

| File | Destination | Replaces |
|---|---|---|
| `Tokens.swift` | `DesignShared/Tokens.swift` | whole file — adds `SPType`, spacing scale, dark mode |
| `ToolCatalog.swift` | `DesignShared/ToolCatalog.swift` | whole file — **only** the `accent` switch differs |
| `Components.swift` | `Storypole/Views/Components.swift` | whole file — adds `Readout`, `SectionEyebrow`, `spCard(_:rule:)` |
| `TapeView.swift` | `Storypole/Calc/TapeView.swift` | whole file |
| `CalcView.swift` | `Storypole/Calc/CalcView.swift` | **body only** — keep the existing `CalcModel` above it |
| `ToolsRootView.swift` | `Storypole/Views/ToolsRootView.swift` | whole file |
| `WatchComponents.swift` | `StorypoleWatch/WatchComponents.swift` | whole file |

`CalcView.swift` here contains the view only. Paste it under the existing `CalcModel` class, or keep
your file and replace its `body`, `keypad` and `historyStrip`.

## The direction

A jobsite instrument, not an app that happens to do maths.

1. **One yellow.** `SP.tapeBody` appears on the blade and nowhere else, so yellow always means
   *this is the tape*. Keel red is the only interactive colour.
2. **The plaque.** The fraction is the headline, alone on its line, in mono at `.largeTitle`.
   The decimal is one whisper line beneath it. Defect ④ is a hierarchy problem, so it is fixed in
   the hierarchy.
3. **Live keys look live.** `ft`, `in` and `/` are tinted `accentSoft` with accent ink — visibly a
   group, and visibly never disabled. Nothing in the keypad is ever dimmed.
4. **The blade earns its space.** 76 pt tall, real graduation hierarchy (1/2 ft short, 1 ft tall),
   a hook at true zero, and a cursor you can read across a garage. Labels stay feet-and-inches.
   When `Tape.smallest(for:)` returns `nil`, nothing is drawn — no fallback tape.
5. **Precision is a decision.** The denominator is six accent chips, not a system segment.
6. **Section colour is structural.** Each of the seven sections owns a hue; the tile wears it as a
   3 pt top rule and the eyebrow as a 3 pt capsule. Both have dark-mode values.
7. **Dark is designed, not derived.** Warm graphite (`0x16140F`), not black; the accent brightens to
   `0xF4763A` and the blade desaturates so it does not glow. watchOS resolves to the dark set.

## Floors held

- Dynamic Type everywhere. The only pinned sizes are blade tick labels and watch chrome glyphs.
- `SP.hit` = 44 pt minimum on every control; keys are 56 pt.
- Every `accessibilityIdentifier` from the shipping build is preserved, plus
  `denominator.<n>` for the new chips.
- Results combine into one element with a label and a value.
- Crown fields keep `accessibilityAdjustableAction`.
- Colour is never the only signal: the invalid field also says "Not a measurement"; derived
  spacing keeps its text.

## Verify

```bash
cd storypole && xcodegen generate
xcodebuild -scheme storypole -destination 'generic/platform=iOS' build
xcodebuild -scheme storypole -destination 'platform=macOS'       build
```

Plus the `#Preview`s — each design file ships a light and a dark one. No simulator.

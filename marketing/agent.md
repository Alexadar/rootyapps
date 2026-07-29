# Marketing Screenshot Generator

Agent guide for generating App Store marketing screenshots.

## Quick Reference

```bash
# Generate screenshots for an app (use fantastic conda env)
cd /Users/oleksandr/Projects/rootyapps/marketing
/Users/oleksandr/miniconda3/envs/fantastic/bin/python generate_screenshots.py ../appname.swift/marketing/aso/mac/params.yaml
/Users/oleksandr/miniconda3/envs/fantastic/bin/python generate_screenshots.py ../appname.swift/marketing/aso/ios/params.yaml
/Users/oleksandr/miniconda3/envs/fantastic/bin/python generate_screenshots.py ../appname.swift/marketing/aso/ipad/params.yaml
```

## Directory Structure

Each app follows this pattern:

```
appname.swift/marketing/
├── raw/                    # Input: raw captures from device/simulator
│   ├── mac/
│   ├── ios/
│   │   ├── *.png           # raw screenshots
│   │   └── video/          # raw app-preview capture(s) — .mov from simctl recordVideo
│   └── ipad/
└── aso/                    # Output: App Store Optimization
    ├── mac/
    │   ├── params.yaml     # Configuration
    │   └── 2880x1800/      # Generated output
    ├── ios/
    │   ├── params.yaml
    │   ├── 1242x2688/      # generated screenshots
    │   └── video/          # rendered reels (full demo + 30s App-Store cut)
    └── ipad/
        ├── params.yaml
        └── 2048x2732/
```

**video/ folders are git-skeleton-only:** raw captures and rendered reels are heavy &
regenerable (and get uploaded to App Store Connect, not stored in git), so `.gitignore`
tracks only the `.gitkeep` — see `**/marketing/**/video/*` in the root `.gitignore`.

**Localized apps nest by locale**, with the primary language under `en/` rather than loose at
the top (`raw/en/ios/`, `aso/de/ios/1320x2868/`). Only the locales that actually get their own
media have a folder — see the next section for why that is a short list.

## macOS capture: never `screencapture`

`screencapture` grabs a **display region**. Whatever is in front lands in the image — a
notification banner, another app, or a second copy of the app another agent launched a moment
earlier. It also cannot see an occluded window. The failure is silent: the wrong screenshot looks
completely plausible, so it ships.

Use `marketing/tools/capture_mac_window.sh`, which wraps `CaptureWindow.swift` (ScreenCaptureKit):

```bash
tools/capture_mac_window.sh "/path/to/My App.app" out.png EARTHAROUND_MODE=simple
LAUNCH_ARGS='-AppleLanguages (de) -AppleLocale de' tools/capture_mac_window.sh "$APP" de.png
tools/capturewindow --list        # JSON: every candidate window with pid, id, title, size
```

Three properties matter, and each exists because the obvious approach gets it wrong:

- **Selected by pid, not by app name or window title.** Neither is unique. Two agents running the
  same app produce two windows with identical bundle id and title; "first match" is a coin flip.
  The launcher runs the executable *inside* the bundle rather than `open` — `open` defers to
  LaunchServices, which may just activate an existing instance — so `$!` is provably our process.
- **Occlusion-proof.** `SCContentFilter(desktopIndependentWindow:)` asks the window server for
  that window's own composited content, so nothing on top can contaminate it, and there is no
  desktop, dock or drop shadow in frame.
- **Refuses to guess.** Zero or multiple matches exit non-zero and capture nothing rather than
  produce a plausible-looking wrong image. Pass `--largest` to opt into a deterministic tie-break.

Teardown kills **only that pid**. Never `pkill -f "<App>"` between shots — that reaches into
other agents' processes and kills their app mid-capture.

Requires Screen Recording permission for the calling shell, granted once. That is unavoidable:
any API that can read window pixels is gated behind it.

## Multi-language: strings and media

Two different rules, and conflating them is the expensive mistake.

**Strings — localize everything, into ONE catalog.** Ship as many languages as you can write.
The pattern that survives contact with a widget + watch app (see `eartharound.swift/Localization/`):

- One `strings*.json` source of truth per topic, keyed by the **English source string**, since
  that literal IS SwiftUI's lookup key. A generator emits the `.xcstrings`. Never hand-edit the
  catalog — it is a build artifact.
- Put the catalog in the shared design folder. Files compiled source-level into several targets
  (`DesignShared/`, a widget shared with a watch complication) resolve against their own
  `Bundle.main`, and one catalog serving all of them is what stops the same sentence drifting
  between processes.
- **Get the string inventory from Xcode, not from grep:** `xcodebuild -exportLocalizations`
  reports every extractable string. Anything the extractor cannot see — prose returned by a
  package at runtime — must be enumerated by sweeping that code across its whole input domain.
  Both times we guessed the inventory by reading source, we missed strings.
- Verify domain terms against **that language's own authority**, not a dictionary: NICT for
  Japanese space weather, DLR for German, OQLF/Termium for French. This caught two real errors
  (`電波障害` → `短波通信障害`, `fulguración` → `llamarada`) that no amount of re-reading found.
- Latent bugs that are invisible in English and show up the moment you add a locale:
  `.uppercased()` without a locale (Turkish dotted i), array-index severity lookups, a number
  formatted with `String(format:)` (POSIX — always `1.7`, never `1,7`), an English fragment
  interpolated into a translated sentence, and a brand name sitting inside a translatable string.
- Notifications must be rendered at **post time** from a locale read out of the app group. A
  background task has no view, so `LocalizedStringKey` and plain `String(localized:)` both miss
  the in-app language picker.

**Media — localize 2–4 locales, not all of them.** Screenshots inherit: Apple serves the primary
language's images in every locale you don't override, so the marginal locale costs a full
re-shoot on every future UI change and buys images most users would have understood anyway.
Localized screenshots do lift conversion (~20–30% is the figure ASO vendors report), so pick the
few markets that justify it — Japanese is consistently named the highest-ROI single localization
— and let the rest inherit.

**Keywords are the exception: they never inherit.** Every locale needs its own complete set,
which is why localized *text* is worth doing broadly even when localized *media* is not. If the
app name is frozen in one language, the localized head noun has to appear in full in that
locale's own subtitle/keywords or the app is invisible to its own market's queries. Validate the
sets mechanically (`aso/check_keywords.py`): 30/100 character budgets, no word repeated between
subtitle and keywords, no space after a comma, no plural of an included singular.

Capture per locale by forcing the language at launch, so the shot cannot depend on whatever the
in-app picker was last left at:

```bash
./make_sim_shots.sh de              # iPhone, German → raw/de/ios/
PLATFORM=ipad ./make_sim_shots.sh ja
# under the hood: xcrun simctl launch … -AppleLanguages "(de)" -AppleLocale de
```

**CJK captions need a different font, and the failure is silent.** `Helvetica.ttc` — the
generator's default — has no CJK glyphs, so a Japanese headline rendered as `□□□□□□` while the
app UI inside the phone frame was flawless Japanese. Nothing errored, and it would have shipped.
`load_or_get_font(path, size, text)` now walks a font chain (Helvetica → Hiragino Sans GB for
ja/zh → AppleSDGothicNeo for ko → Arial Unicode) and picks the first that can actually render
the caption. Note that font *metrics* cannot detect this: a missing glyph falls back to `.notdef`,
which has a normal non-zero width, so `getbbox` reports success. Coverage is tested by
rasterising the character and comparing it to U+FFFF, which never has a glyph.

Caption text lives in `marketing/captions.json` and is stamped into each
`aso/<locale>/<platform>/params.yaml` by `gen_params.py`. Captions are **rewritten** per language,
not translated — they render as large display text, and a literal translation of a punchy English
line overflows in German and Finnish.

**Re-shoot after any string change.** A screenshot captured before a terminology fix keeps the
old wording forever; nothing in the pipeline notices.

## App Preview Reels (video)

Same dual purpose as screenshots: **internal acceptance review** + **ASO upload**. One
capture session yields two cuts:

- **Full demo** — whole-app walkthrough, any length (your acceptance review / site / social).
- **App Store cut** — **15–30 s**, **886×1920** (6.9" iPhone), H.264 or ProRes 422 HQ, ≤30 fps, ≤500 MB.

Capture on the booted simulator via `xcrun simctl io booted recordVideo`, then conform with
`ffmpeg` (scale/pad to 886×1920, cap fps, encode H.264 yuv420p). Optional soundtrack from
Stable Audio 3 medium (MPS) muxed in. Reference app: `ephemeris.swift` (already live — used
to validate that a simulator-captured reel passes App Store review). Pipeline is per-app and
replicated after it's proven.

## params.yaml Schema

```yaml
platform: ios|mac|ipad|watch|ios-landscape|ipad-landscape

paths:
  raw_folder: /absolute/path/to/raw/screenshots
  output_folder: /absolute/path/to/aso/output

style:
  # Background
  bg_gradient: true
  bg_color_top: '#1D1D1F'
  bg_color_bottom: '#000000'

  # Text colors
  title_color: '#ffffff'
  subtitle_color: '#F5F5F7'

  # Screenshot styling
  screenshot_zoom: 1.0        # Scale factor (1.0 = fit to space)
  screenshot_move_down: 0     # Percentage to shift viewport down
  screenshot_move_left: 0     # Pixels to shift left
  border_width: 12
  border_color: '#ffffff'
  border_radius: 40
  shadow: true

  # Layout (TwoColumnStyle - mac, landscape)
  text_col_percent: 42
  screenshot_col_percent: 58

  # Layout (TopBottomStyle - ios, ipad, watch)
  text_row_percent: 25
  screenshot_row_percent: 75

  # Spacing
  text_padding: 80
  screenshot_padding: 80

texts:
  - title: "Main Title"
    subtitle: "Optional subtitle\nSupports newlines"
  - title: "Second Screenshot"
    subtitle: "Description"
```

## Platform Configurations

| Platform | Size | Layout | Default Zoom |
|----------|------|--------|--------------|
| mac | 2880x1800 | TwoColumnStyle | 2.5 |
| ios | 1242x2688 | TopBottomStyle | 1.0 |
| ios-landscape | 2688x1242 | TwoColumnStyle | 1.3 |
| ipad | 2048x2732 | TopBottomStyle | 1.0 |
| ipad-landscape | 2732x2048 | TwoColumnStyle | 1.2 |
| watch | 416x496 | TopBottomStyle | 1.0 |

## Layout Styles

### TwoColumnStyle (Landscape)
- Text on left column, screenshot on right
- Used for: mac, ios-landscape, ipad-landscape
- Key params: `text_col_percent`, `screenshot_col_percent`

### TopBottomStyle (Portrait)
- Text on top row, screenshot on bottom
- Used for: ios, ipad, watch
- Key params: `text_row_percent`, `screenshot_row_percent`

## Workflow

1. **Capture raw screenshots** from simulator/device
2. **Place in** `appname.swift/marketing/raw/{platform}/`
3. **Create/edit** `params.yaml` in output folder
4. **Run generator:**
   ```bash
   python generate_screenshots.py path/to/params.yaml
   ```
5. **Output** appears in `{output_folder}/{WxH}/screenshot_XX.png`

## Tips

- Screenshots are matched to texts by sort order (alphabetical filename)
- Number of output screenshots = min(raw files, text entries)
- Use `screenshot_zoom > 1` to crop/focus on UI details
- Use `screenshot_move_down` to shift the visible portion
- Explicit `\n` in subtitle text creates line breaks

## Apps with Marketing Folders

- goldencalc.swift
- goldencalclite.swift
- indoxtext.swift
- typingmill.swift
- bigpinkcat.swift
- monstro_shooter.swift
- froggo.swift (uses `media/` instead of `marketing/`)

## Python API

```python
from screenshots_generator import generate_mac_screenshots, TwoColumnStyle

# Custom style
style = TwoColumnStyle(
    screenshot_zoom=2.5,
    bg_color_top='#FF69B4',
    bg_color_bottom='#8B008B'
)

generate_mac_screenshots(
    raw_folder="/path/to/raw",
    target_folder="/path/to/output",
    texts=[("Title", "Subtitle"), ...],
    style=style
)
```

## Dependencies

- PIL/Pillow
- PyYAML
- Python 3.8+

Use the `fantastic` conda environment (already has deps installed):

```bash
/Users/oleksandr/miniconda3/envs/fantastic/bin/python
```

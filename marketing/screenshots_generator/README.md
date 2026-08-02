# Screenshot Generator

App Store marketing screenshots with zoom/crop.

## Quick Start

```python
from screenshots_generator import generate_mac_screenshots
generate_mac_screenshots()  # 2.5x zoom, default paths
```

## Multi-language layout (all apps follow this)

```
<app>/marketing/raw/<loc>/<platform>/NN_<name>.png    captures, straight off the device/sim
<app>/marketing/aso/<loc>/<platform>/params.yaml      caption texts for that locale+platform
<app>/marketing/aso/<loc>/<platform>/<W>x<H>/         framed, store-ready output
```

`<loc>` is the SHORT code (`en`, `de`, `ja`, `pt-BR`, `nb`, `zh-Hans`). App Store Connect wants
`en-US` / `de-DE` / `fr-FR` / `es-ES` / `no` — keep ONE mapping dict in the uploader, never two.

Captions are matched to captures **by sorted order**, so `params.yaml` `texts[i]` pairs with the
i-th file in `raw/<loc>/<platform>/`. Name captures `01_`, `02_`, … and keep that order identical
across locales.

## Two ways this silently ships the wrong thing

**1. Stale files.** Nothing in this pipeline deletes. Change a shot plan from 5 shots to 4 and you
are left with 8 raw files and 5 framed ones; the generator takes `[:len(texts)]` — the first N
*alphabetically* — so `01_dashboard_dark.png` and a leftover `01_simple_dark.png` both land in the
first two slots. `collect_captures()` now prints a loud warning naming the ignored files, and
`purge_stale_outputs()` deletes framed images numbered beyond the new count. Heed the warning:
the guards report and clean up, they cannot know which file you meant.

**2. Tofu.** A missing glyph renders as `.notdef` (□) with a perfectly normal advance width, so
`getbbox` reports success and nothing raises — a Japanese caption ships as □□□□ over a flawless
Japanese screenshot. Always pass the caption text to `load_or_get_font(path, size, text)`; it walks
`_FONT_CHAIN` and proves coverage by rasterising and comparing against U+FFFF (`font_covers()`).
Never re-implement font selection locally — that is how this bug got shipped three times.

**3. A screenshot freezes the build it was taken from.** Re-capture after ANY string or UI change.
A control deleted from the app stays in the store listing forever otherwise.

## Structure

- `helpers.py` - Image utils (crop, gradient, shadow), font coverage (`font_covers`,
  `load_or_get_font`), and the pipeline guards (`collect_captures`, `purge_stale_outputs`)
- `styles.py` - `TwoColumnStyle` class
- `generator.py` - `generate_mac_screenshots()`

## API

```python
generate_mac_screenshots(
    raw_folder="/path/to/raw",           # default: goldencalc.swift/marketing/screenshots/raw/mac
    target_folder="/path/to/output",      # default: goldencalc.swift/marketing/screenshots/aso/mac
    texts=[("Title", "Subtitle"), ...],   # default: 5 pairs
    style=TwoColumnStyle(...)             # default: style_default
)
```

## Styles

```python
TwoColumnStyle(
    screenshot_zoom=2.5,      # zoom multiplier
    screenshot_crop='full',   # crop region
    bg_color_top='#1D1D1F',
    bg_color_bottom='#000000'
)
```

**Pre-configured:**
- `style_default` - 2.5x zoom
- `style_zoom_high` - 3.0x zoom
- `style_top_zoom` - top 50% + 2.5x
- `style_middle_zoom` - middle 50% + 2.5x
- `style_bottom_zoom` - bottom 50% + 2.5x

**Crop regions:**
`full`, `top50`, `middle50`, `bottom50`, `top33`, `middle33`, `bottom33`

## Default Paths

```
Raw:    /Users/oleksandr/Projects/rootyapps/goldencalc.swift/marketing/screenshots/raw/mac
Output: /Users/oleksandr/Projects/rootyapps/goldencalc.swift/marketing/screenshots/aso/mac
```

## Examples

```python
# High zoom
from screenshots_generator import style_zoom_high
generate_mac_screenshots(style=style_zoom_high)

# Custom
custom = TwoColumnStyle(screenshot_zoom=3.5, screenshot_crop='middle50')
generate_mac_screenshots(style=custom)

# Different app
generate_mac_screenshots(
    raw_folder="/path/to/other/raw",
    target_folder="/path/to/other/output"
)
```

## How Zoom Works

1. Load screenshot
2. Crop if specified
3. Calculate base size to fit space
4. Multiply by `screenshot_zoom`
5. Clip if larger than space

Result: `zoom=2.5` → screenshot 2.5× larger than default.

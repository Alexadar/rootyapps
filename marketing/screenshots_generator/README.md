# Screenshot Generator

App Store marketing screenshots with zoom/crop.

## Quick Start

```python
from screenshots_generator import generate_mac_screenshots
generate_mac_screenshots()  # 2.5x zoom, default paths
```

## Structure

- `helpers.py` - Image utils (crop, gradient, shadow)
- `styles.py` - `TwoColumnStyle` class
- `generator.py` - `generate_mac_screenshots()`

## API

```python
generate_mac_screenshots(
    raw_folder="/path/to/raw",           # default: goldencalc/raw/mac
    target_folder="/path/to/output",      # default: goldencalc/aso/mac
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

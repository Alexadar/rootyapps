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
├── raw/                    # Input: raw screenshots from device
│   ├── mac/
│   ├── ios/
│   └── ipad/
└── aso/                    # Output: App Store Optimization
    ├── mac/
    │   ├── params.yaml     # Configuration
    │   └── 2880x1800/      # Generated output
    ├── ios/
    │   ├── params.yaml
    │   └── 1242x2688/
    └── ipad/
        ├── params.yaml
        └── 2048x2732/
```

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

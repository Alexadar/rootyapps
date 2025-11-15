#!/usr/bin/env python3
"""
Generate App Store screenshots using params.yaml configuration

Usage:
    python generate_screenshots.py path/to/params.yaml

Example:
    python generate_screenshots.py ../goldencalc.swift/marketing/screenshots/aso/mac/params.yaml
"""

import sys
import yaml
from pathlib import Path
from screenshots_generator import generate_mac_screenshots
from screenshots_generator.styles import TwoColumnStyle

def load_params(params_path):
    """Load parameters from YAML file"""
    with open(params_path, 'r') as f:
        return yaml.safe_load(f)

def create_style_from_params(params):
    """Create TwoColumnStyle from YAML params"""
    style_params = params.get('style', {})

    # Map YAML params to TwoColumnStyle parameters
    return TwoColumnStyle(
        text_col_percent=style_params.get('text_col_percent', 42),
        screenshot_col_percent=style_params.get('screenshot_col_percent', 58),
        screenshot_zoom=style_params.get('screenshot_zoom', 1.7),
        screenshot_move_down=style_params.get('screenshot_move_down', -60),
        bg_gradient=style_params.get('bg_gradient', True),
        bg_color_top=style_params.get('bg_color_top', '#1D1D1F'),
        bg_color_bottom=style_params.get('bg_color_bottom', '#000000'),
        title_color=style_params.get('title_color', '#ffffff'),
        subtitle_color=style_params.get('subtitle_color', '#F5F5F7'),
        text_padding=style_params.get('text_padding', 80),
        screenshot_padding=style_params.get('screenshot_padding', 80),
        border_width=style_params.get('border_width', 12),
        border_color=style_params.get('border_color', '#ffffff'),
        border_radius=style_params.get('border_radius', 40),
        shadow=style_params.get('shadow', True),
    )

def extract_texts_from_params(params):
    """Extract text pairs from YAML params"""
    texts_list = params.get('texts', [])
    return [(item['title'], item['subtitle']) for item in texts_list]

def main():
    # Check if params path is provided
    if len(sys.argv) < 2:
        print("❌ Usage: python generate_screenshots.py path/to/params.yaml")
        print("\nExample:")
        print("  python generate_screenshots.py ../goldencalc.swift/marketing/screenshots/aso/mac/params.yaml")
        sys.exit(1)

    # Load params
    params_path = Path(sys.argv[1])

    if not params_path.exists():
        print(f"❌ params.yaml not found at {params_path}")
        sys.exit(1)

    print(f"📄 Loading parameters from {params_path}")
    params = load_params(params_path)

    # Extract configuration
    paths = params.get('paths', {})
    raw_folder = paths.get('raw_folder')
    output_folder = paths.get('output_folder')

    if not raw_folder or not output_folder:
        print("❌ Missing 'paths.raw_folder' or 'paths.output_folder' in params.yaml")
        sys.exit(1)

    # Create style from params
    style = create_style_from_params(params)

    # Extract texts
    texts = extract_texts_from_params(params)

    if not texts:
        print("❌ No texts found in params.yaml")
        sys.exit(1)

    print(f"📁 Raw folder: {raw_folder}")
    print(f"📁 Output folder: {output_folder}")
    print(f"🎨 Style: zoom={style.screenshot_zoom}x, move_down={style.screenshot_move_down}px")
    print(f"📝 Texts: {len(texts)} configured")

    # Generate screenshots
    generate_mac_screenshots(
        raw_folder=raw_folder,
        target_folder=output_folder,
        texts=texts,
        style=style,
        sizes=[(2880, 1800)]  # macOS App Store size
    )

if __name__ == "__main__":
    main()

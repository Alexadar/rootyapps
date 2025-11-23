#!/usr/bin/env python3
"""
Generate App Store screenshots using params.yaml configuration

Usage:
    python generate_screenshots.py path/to/params.yaml

Example:
    python generate_screenshots.py ../goldencalc.swift/marketing/screenshots/aso/mac/params.yaml
    python generate_screenshots.py ../goldencalclite.swift/marketing/aso/ios/params.yaml
"""

import sys
import yaml
from pathlib import Path
from screenshots_generator import (
    generate_mac_screenshots,
    generate_ios_screenshots,
    generate_ios_landscape_screenshots,
    generate_ipad_screenshots,
    generate_ipad_landscape_screenshots,
    generate_watch_screenshots
)
from screenshots_generator.styles import TwoColumnStyle, TopBottomStyle

# Platform configurations
PLATFORM_CONFIG = {
    'mac': {
        'generator': generate_mac_screenshots,
        'style_class': TwoColumnStyle,
        'default_size': (2880, 1800),
        'scale_base': 2880,
    },
    'ios': {
        'generator': generate_ios_screenshots,
        'style_class': TopBottomStyle,
        'default_size': (1242, 2688),
        'scale_base': 1242,
    },
    'ios-landscape': {
        'generator': generate_ios_landscape_screenshots,
        'style_class': TwoColumnStyle,
        'default_size': (2688, 1242),
        'scale_base': 2688,
    },
    'ipad': {
        'generator': generate_ipad_screenshots,
        'style_class': TopBottomStyle,
        'default_size': (2048, 2732),
        'scale_base': 2048,
    },
    'ipad-landscape': {
        'generator': generate_ipad_landscape_screenshots,
        'style_class': TwoColumnStyle,
        'default_size': (2732, 2048),
        'scale_base': 2732,
    },
    'watch': {
        'generator': generate_watch_screenshots,
        'style_class': TopBottomStyle,
        'default_size': (416, 496),
        'scale_base': 416,
    },
}

def load_params(params_path):
    """Load parameters from YAML file"""
    with open(params_path, 'r') as f:
        return yaml.safe_load(f)

def create_style_from_params(params, platform='mac'):
    """Create style from YAML params based on platform"""
    style_params = params.get('style', {})
    config = PLATFORM_CONFIG.get(platform, PLATFORM_CONFIG['mac'])
    StyleClass = config['style_class']

    # Common parameters
    common_params = {
        'bg_gradient': style_params.get('bg_gradient', True),
        'bg_color_top': style_params.get('bg_color_top', '#1D1D1F'),
        'bg_color_bottom': style_params.get('bg_color_bottom', '#000000'),
        'title_color': style_params.get('title_color', '#ffffff'),
        'subtitle_color': style_params.get('subtitle_color', '#F5F5F7'),
        'text_padding': style_params.get('text_padding', 80),
        'screenshot_padding': style_params.get('screenshot_padding', 80),
        'border_width': style_params.get('border_width', 12),
        'border_color': style_params.get('border_color', '#ffffff'),
        'border_radius': style_params.get('border_radius', 40),
        'shadow': style_params.get('shadow', True),
        'screenshot_zoom': style_params.get('screenshot_zoom', 1.0),
    }

    if platform in ['mac', 'ios-landscape', 'ipad-landscape']:
        # TwoColumnStyle specific
        return StyleClass(
            text_col_percent=style_params.get('text_col_percent', 42),
            screenshot_col_percent=style_params.get('screenshot_col_percent', 58),
            screenshot_move_down=style_params.get('screenshot_move_down', 0),
            **common_params
        )
    else:
        # TopBottomStyle specific (ios, ipad, watch)
        return StyleClass(
            text_row_percent=style_params.get('text_row_percent', 25),
            screenshot_row_percent=style_params.get('screenshot_row_percent', 75),
            **common_params
        )

def extract_texts_from_params(params):
    """Extract text pairs from YAML params"""
    texts_list = params.get('texts', [])
    return [(item['title'], item.get('subtitle', '')) for item in texts_list]

def main():
    # Check if params path is provided
    if len(sys.argv) < 2:
        print("Usage: python generate_screenshots.py path/to/params.yaml")
        print("\nExample:")
        print("  python generate_screenshots.py ../goldencalc.swift/marketing/screenshots/aso/mac/params.yaml")
        print("  python generate_screenshots.py ../goldencalclite.swift/marketing/aso/ios/params.yaml")
        sys.exit(1)

    # Load params
    params_path = Path(sys.argv[1])

    if not params_path.exists():
        print(f"params.yaml not found at {params_path}")
        sys.exit(1)

    print(f"Loading parameters from {params_path}")
    params = load_params(params_path)

    # Detect platform from params or path
    platform = params.get('platform', None)
    if not platform:
        # Try to detect from path
        path_str = str(params_path).lower()
        for p in ['ios', 'ipad', 'watch', 'mac']:
            if f'/{p}/' in path_str or path_str.endswith(f'/{p}'):
                platform = p
                break
        if not platform:
            platform = 'mac'  # Default

    if platform not in PLATFORM_CONFIG:
        print(f"Unknown platform: {platform}. Using 'mac'")
        platform = 'mac'

    config = PLATFORM_CONFIG[platform]
    print(f"Platform: {platform}")

    # Extract configuration
    paths = params.get('paths', {})
    raw_folder = paths.get('raw_folder')
    output_folder = paths.get('output_folder')

    if not raw_folder or not output_folder:
        print("Missing 'paths.raw_folder' or 'paths.output_folder' in params.yaml")
        sys.exit(1)

    # Create style from params
    style = create_style_from_params(params, platform)

    # Extract texts
    texts = extract_texts_from_params(params)

    if not texts:
        print("No texts found in params.yaml")
        sys.exit(1)

    print(f"Raw folder: {raw_folder}")
    print(f"Output folder: {output_folder}")
    print(f"Style: {style.__class__.__name__} (zoom={style.screenshot_zoom}x)")
    print(f"Texts: {len(texts)} configured")

    # Get size from params or use default
    size = params.get('size', list(config['default_size']))
    if isinstance(size, list):
        size = tuple(size)

    # Generate screenshots
    config['generator'](
        raw_folder=raw_folder,
        target_folder=output_folder,
        texts=texts,
        style=style,
        sizes=[size]
    )

if __name__ == "__main__":
    main()

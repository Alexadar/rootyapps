"""Screenshot generation functions"""

from pathlib import Path
from typing import List, Tuple
from .styles import style_default


def generate_mac_screenshots(
    raw_folder="/Users/oleksandr/Projects/rootyapps/goldencalc.swift/marketing/screenshots/raw/mac",
    target_folder="/Users/oleksandr/Projects/rootyapps/goldencalc.swift/marketing/screenshots/aso/mac",
    texts=None,
    style=None,
    sizes=None
):
    """
    Generate macOS marketing screenshots

    Args:
        raw_folder: Folder containing raw screenshots
        target_folder: Output folder for generated screenshots
        texts: List of (title, subtitle) tuples for each screenshot
        style: ScreenshotStyle instance (uses style_default if None)
        sizes: List of (width, height) tuples for output sizes (default: [(2880, 1800)])
    """
    if style is None:
        style = style_default

    if texts is None:
        texts = [
            ("Golden Ratio Calculator", "Precision & Beauty"),
            ("Professional Tools", "For Designers & Engineers"),
            ("Instant Results", "Fast & Accurate"),
            ("Beautiful Interface", "Native macOS Design"),
            ("Always Available", "Works Offline"),
        ]

    if sizes is None:
        sizes = [(2880, 1800)]

    # Get raw screenshots
    raw_path = Path(raw_folder)
    screenshot_files = sorted([f for f in raw_path.glob('*') if f.suffix.lower() in ['.png', '.jpg', '.jpeg']])

    if not screenshot_files:
        print(f"❌ No screenshots found in {raw_folder}")
        return

    print(f"📁 Found {len(screenshot_files)} screenshots")
    print(f"🎨 Using style: {style.__class__.__name__} (zoom={style.screenshot_zoom}x, crop={style.screenshot_crop})")

    # Generate for macOS sizes
    for size in sizes:
        print(f"\n📐 Generating for size: {size[0]}x{size[1]}")
        size_folder = Path(target_folder) / f"{size[0]}x{size[1]}"

        for idx, screenshot_file in enumerate(screenshot_files[:len(texts)]):
            title, subtitle = texts[idx]
            output_filename = f"screenshot_{idx + 1:02d}.png"
            output_path = size_folder / output_filename

            print(f"  {idx + 1}. '{title}' + '{subtitle}'")

            success = style.render(
                str(screenshot_file),
                str(output_path),
                size,
                title,
                subtitle
            )

            if success:
                print(f"     ✓ Saved to {output_path}")
            else:
                print(f"     ✗ Failed")

    print(f"\n✅ macOS screenshot generation complete!")

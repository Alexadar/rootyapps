"""Screenshot generation functions"""

from pathlib import Path
from typing import List, Tuple
from .styles import style_default, TopBottomStyle


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


def generate_ios_screenshots(
    raw_folder: str,
    target_folder: str,
    texts=None,
    style=None,
    sizes=None
):
    """
    Generate iOS marketing screenshots (iPhone 6.5" Display)

    Args:
        raw_folder: Folder containing raw screenshots
        target_folder: Output folder for generated screenshots
        texts: List of (title, subtitle) tuples for each screenshot
        style: TopBottomStyle instance
        sizes: List of (width, height) tuples (default: [(1242, 2688)])
    """
    if style is None:
        style = TopBottomStyle()

    if texts is None:
        texts = [
            ("Welcome", "Get Started"),
        ]

    if sizes is None:
        sizes = [(1242, 2688)]  # iPhone 6.5" Display

    # Get raw screenshots
    raw_path = Path(raw_folder)
    screenshot_files = sorted([f for f in raw_path.glob('*') if f.suffix.lower() in ['.png', '.jpg', '.jpeg']])

    if not screenshot_files:
        print(f"❌ No screenshots found in {raw_folder}")
        return

    print(f"📁 Found {len(screenshot_files)} screenshots")
    print(f"🎨 Using style: {style.__class__.__name__} (zoom={style.screenshot_zoom}x)")

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

    print(f"\n✅ iOS screenshot generation complete!")


def generate_ipad_screenshots(
    raw_folder: str,
    target_folder: str,
    texts=None,
    style=None,
    sizes=None
):
    """
    Generate iPad marketing screenshots (iPad 13" Display)

    Args:
        raw_folder: Folder containing raw screenshots
        target_folder: Output folder for generated screenshots
        texts: List of (title, subtitle) tuples for each screenshot
        style: TopBottomStyle instance
        sizes: List of (width, height) tuples (default: [(2048, 2732)])
    """
    if style is None:
        style = TopBottomStyle()

    if texts is None:
        texts = [
            ("Welcome", "Get Started"),
        ]

    if sizes is None:
        sizes = [(2048, 2732)]  # iPad 13" Display

    # Get raw screenshots
    raw_path = Path(raw_folder)
    screenshot_files = sorted([f for f in raw_path.glob('*') if f.suffix.lower() in ['.png', '.jpg', '.jpeg']])

    if not screenshot_files:
        print(f"❌ No screenshots found in {raw_folder}")
        return

    print(f"📁 Found {len(screenshot_files)} screenshots")
    print(f"🎨 Using style: {style.__class__.__name__} (zoom={style.screenshot_zoom}x)")

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

    print(f"\n✅ iPad screenshot generation complete!")


def generate_watch_screenshots(
    raw_folder: str,
    target_folder: str,
    texts=None,
    style=None,
    sizes=None
):
    """
    Generate Apple Watch marketing screenshots (Series 10/11)

    Args:
        raw_folder: Folder containing raw screenshots
        target_folder: Output folder for generated screenshots
        texts: List of (title, subtitle) tuples for each screenshot
        style: TopBottomStyle instance
        sizes: List of (width, height) tuples (default: [(416, 496)])
    """
    if style is None:
        style = TopBottomStyle(
            text_row_percent=20,
            screenshot_row_percent=80,
            border_width=4,
            border_radius=20,
            text_padding=20,
            screenshot_padding=20
        )

    if texts is None:
        texts = [
            ("Welcome", ""),
        ]

    if sizes is None:
        sizes = [(416, 496)]  # Watch Series 10/11

    # Get raw screenshots
    raw_path = Path(raw_folder)
    screenshot_files = sorted([f for f in raw_path.glob('*') if f.suffix.lower() in ['.png', '.jpg', '.jpeg']])

    if not screenshot_files:
        print(f"❌ No screenshots found in {raw_folder}")
        return

    print(f"📁 Found {len(screenshot_files)} screenshots")
    print(f"🎨 Using style: {style.__class__.__name__} (zoom={style.screenshot_zoom}x)")

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

    print(f"\n✅ Watch screenshot generation complete!")


def generate_ios_landscape_screenshots(
    raw_folder: str,
    target_folder: str,
    texts=None,
    style=None,
    sizes=None
):
    """
    Generate iOS landscape marketing screenshots (iPhone 6.5" Display Landscape)

    Args:
        raw_folder: Folder containing raw screenshots
        target_folder: Output folder for generated screenshots
        texts: List of (title, subtitle) tuples for each screenshot
        style: TwoColumnStyle instance
        sizes: List of (width, height) tuples (default: [(2688, 1242)])
    """
    from .styles import TwoColumnStyle

    if style is None:
        style = TwoColumnStyle(
            text_col_percent=35,
            screenshot_col_percent=65,
            screenshot_zoom=1.3,
            border_width=8,
            border_radius=30,
            text_padding=60,
            screenshot_padding=60
        )

    if texts is None:
        texts = [
            ("Welcome", "Get Started"),
        ]

    if sizes is None:
        sizes = [(2688, 1242)]  # iPhone 6.5" Display Landscape

    # Get raw screenshots
    raw_path = Path(raw_folder)
    screenshot_files = sorted([f for f in raw_path.glob('*') if f.suffix.lower() in ['.png', '.jpg', '.jpeg']])

    if not screenshot_files:
        print(f"❌ No screenshots found in {raw_folder}")
        return

    print(f"📁 Found {len(screenshot_files)} screenshots")
    print(f"🎨 Using style: {style.__class__.__name__} (zoom={style.screenshot_zoom}x)")

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

    print(f"\n✅ iOS Landscape screenshot generation complete!")


def generate_ipad_landscape_screenshots(
    raw_folder: str,
    target_folder: str,
    texts=None,
    style=None,
    sizes=None
):
    """
    Generate iPad landscape marketing screenshots (iPad 13" Display Landscape)

    Args:
        raw_folder: Folder containing raw screenshots
        target_folder: Output folder for generated screenshots
        texts: List of (title, subtitle) tuples for each screenshot
        style: TwoColumnStyle instance
        sizes: List of (width, height) tuples (default: [(2732, 2048)])
    """
    from .styles import TwoColumnStyle

    if style is None:
        style = TwoColumnStyle(
            text_col_percent=35,
            screenshot_col_percent=65,
            screenshot_zoom=1.2,
            border_width=10,
            border_radius=35,
            text_padding=80,
            screenshot_padding=80
        )

    if texts is None:
        texts = [
            ("Welcome", "Get Started"),
        ]

    if sizes is None:
        sizes = [(2732, 2048)]  # iPad 13" Display Landscape

    # Get raw screenshots
    raw_path = Path(raw_folder)
    screenshot_files = sorted([f for f in raw_path.glob('*') if f.suffix.lower() in ['.png', '.jpg', '.jpeg']])

    if not screenshot_files:
        print(f"❌ No screenshots found in {raw_folder}")
        return

    print(f"📁 Found {len(screenshot_files)} screenshots")
    print(f"🎨 Using style: {style.__class__.__name__} (zoom={style.screenshot_zoom}x)")

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

    print(f"\n✅ iPad Landscape screenshot generation complete!")

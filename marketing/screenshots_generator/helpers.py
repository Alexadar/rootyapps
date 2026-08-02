"""Helper functions for screenshot generation"""

from PIL import Image, ImageDraw, ImageFont, ImageFilter
from typing import Tuple, List
import os


def create_gradient_background(width: int, height: int, color_top: str, color_bottom: str) -> Image.Image:
    """Create a vertical gradient background"""
    base = Image.new('RGB', (width, height), color_top)
    draw = ImageDraw.Draw(base)

    r1, g1, b1 = tuple(int(color_top.lstrip('#')[i:i+2], 16) for i in (0, 2, 4))
    r2, g2, b2 = tuple(int(color_bottom.lstrip('#')[i:i+2], 16) for i in (0, 2, 4))

    for y in range(height):
        ratio = y / height
        r = int(r1 + (r2 - r1) * ratio)
        g = int(g1 + (g2 - g1) * ratio)
        b = int(b1 + (b2 - b1) * ratio)
        draw.line([(0, y), (width, y)], fill=(r, g, b))

    return base


def create_rounded_rectangle_mask(size: Tuple[int, int], radius: int) -> Image.Image:
    """Create a mask for rounded rectangle"""
    mask = Image.new('L', size, 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle([(0, 0), size], radius=radius, fill=255)
    return mask


def add_shadow(image: Image.Image, offset: Tuple[int, int], blur: int, color: str) -> Image.Image:
    """Add drop shadow to an image"""
    shadow = Image.new('RGBA', (image.width + abs(offset[0]) + blur * 2,
                                image.height + abs(offset[1]) + blur * 2), (0, 0, 0, 0))

    shadow_draw = ImageDraw.Draw(shadow)
    shadow_color = tuple(int(color.lstrip('#')[i:i+2], 16) for i in (0, 2, 4)) + (100,)

    shadow_pos = (blur + max(0, offset[0]), blur + max(0, offset[1]),
                  blur + max(0, offset[0]) + image.width,
                  blur + max(0, offset[1]) + image.height)

    shadow_draw.rectangle(shadow_pos, fill=shadow_color)
    shadow = shadow.filter(ImageFilter.GaussianBlur(blur))

    return shadow


def crop_screenshot(screenshot: Image.Image, crop_region: str = 'full', move_down_percent: int = 0) -> Image.Image:
    """
    Crop screenshot to focus on specific region and optionally move down

    Args:
        screenshot: PIL Image
        crop_region: Crop region (full, top50, etc.)
        move_down_percent: Move crop window down by this percentage (0-100)
    """
    width, height = screenshot.size

    if crop_region == 'full' or not crop_region:
        if move_down_percent > 0:
            # Move down means crop from bottom
            offset = int(height * move_down_percent / 100)
            return screenshot.crop((0, offset, width, height))
        return screenshot
    elif crop_region == 'top50':
        crop_height = height // 2
        offset = int(height * move_down_percent / 100)
        return screenshot.crop((0, offset, width, offset + crop_height))
    elif crop_region == 'bottom50':
        crop_height = height // 2
        offset = height // 2 + int(height * move_down_percent / 100)
        return screenshot.crop((0, offset, width, min(height, offset + crop_height)))
    elif crop_region == 'middle50':
        quarter = height // 4
        offset = quarter + int(height * move_down_percent / 100)
        return screenshot.crop((0, offset, width, offset + height // 2))
    elif crop_region == 'top33':
        crop_height = height // 3
        offset = int(height * move_down_percent / 100)
        return screenshot.crop((0, offset, width, offset + crop_height))
    elif crop_region == 'middle33':
        third = height // 3
        offset = third + int(height * move_down_percent / 100)
        return screenshot.crop((0, offset, width, offset + third))
    elif crop_region == 'bottom33':
        crop_height = height // 3
        offset = 2 * height // 3 + int(height * move_down_percent / 100)
        return screenshot.crop((0, offset, width, min(height, offset + crop_height)))
    else:
        return screenshot


# Tried in order; the first one that can render the caption wins. Helvetica leads because it is
# the established look for Latin and Cyrillic — it just has no CJK glyphs at all.
_FONT_CHAIN = (
    '/System/Library/Fonts/Helvetica.ttc',
    '/System/Library/Fonts/Hiragino Sans GB.ttc',        # ja + zh
    '/System/Library/Fonts/AppleSDGothicNeo.ttc',        # ko
    '/System/Library/Fonts/Supplemental/Arial Unicode.ttf',  # universal last resort
    '/Library/Fonts/Arial.ttf',
)

_coverage_cache = {}


def _renders(font: ImageFont.FreeTypeFont, ch: str) -> bool:
    """True if `font` has a real glyph for `ch`.

    Font metrics cannot answer this: a missing glyph falls back to .notdef, which is the tofu
    box — it has a perfectly normal non-zero width, so `getbbox` reports success while the
    caption renders as □□□□. The only reliable check is to rasterise the character and compare
    it against a codepoint that is guaranteed absent.
    """
    key = (font.path, font.size, ch)
    if key in _coverage_cache:
        return _coverage_cache[key]

    def raster(c: str) -> bytes:
        img = Image.new('L', (max(8, font.size * 2), max(8, font.size * 2)), 0)
        ImageDraw.Draw(img).text((2, 2), c, font=font, fill=255)
        return img.tobytes()

    result = raster(ch) != raster('￿')   # U+FFFF is a noncharacter: never has a glyph
    _coverage_cache[key] = result
    return result


def font_covers(font: ImageFont.FreeTypeFont, text: str) -> bool:
    """True if `font` has a real glyph for every character in `text`."""
    return all(_renders(font, ch) for ch in text if not ch.isspace())


def load_or_get_font(font_path: str, size: int, text: str = '') -> ImageFont.FreeTypeFont:
    """Load a font that can actually render `text`.

    Pass the caption so a Japanese, Korean or Chinese line does not silently come out as tofu
    boxes — which is exactly what happened before this existed: the app UI inside the frame was
    perfect Japanese while the marketing headline above it was □□□□□□, and nothing errored.
    """
    if font_path and os.path.exists(font_path):
        return ImageFont.truetype(font_path, size)

    fallback = None
    for path in _FONT_CHAIN:
        if not os.path.exists(path):
            continue
        try:
            font = ImageFont.truetype(path, size)
        except Exception:
            continue
        fallback = fallback or font
        if not text:
            return font
        if all(_renders(font, ch) for ch in text if not ch.isspace()):
            return font

    return fallback or ImageFont.load_default()


def wrap_text(text: str, font: ImageFont.FreeTypeFont, max_width: int) -> List[str]:
    """Wrap text to fit within max_width, respecting explicit newlines"""
    lines = []

    # First split by explicit newlines
    for paragraph in text.split('\n'):
        words = paragraph.split()
        if not words:
            lines.append('')
            continue

        current_line = []
        for word in words:
            test_line = ' '.join(current_line + [word])
            bbox = font.getbbox(test_line)
            width = bbox[2] - bbox[0]

            if width <= max_width:
                current_line.append(word)
            else:
                if current_line:
                    lines.append(' '.join(current_line))
                current_line = [word]

        if current_line:
            lines.append(' '.join(current_line))

    return lines


def collect_captures(raw_path, texts, label=""):
    """Raw captures paired with caption texts, with the count mismatch made LOUD.

    Neither the capture step nor the framing step deletes anything, so changing a shot plan leaves
    old captures sitting beside the new ones — and the caller slices `[:len(texts)]`, i.e. the first
    N ALPHABETICALLY. `01_dashboard_dark.png` and a leftover `01_simple_dark.png` both survive, both
    sort into the first two slots, and the wrong pair ships. Earth Around shipped exactly that.

    Returns the same sorted list the callers expect; it only reports.
    """
    files = sorted(f for f in raw_path.glob('*')
                   if f.suffix.lower() in ('.png', '.jpg', '.jpeg'))
    tag = f" [{label}]" if label else ""
    if len(files) != len(texts):
        print(f"⚠️  {len(files)} captures but {len(texts)} caption texts{tag} — "
              f"using the first {min(len(files), len(texts))} ALPHABETICALLY:")
        for f in files[:len(texts)]:
            print(f"       {f.name}")
        if len(files) > len(texts):
            print(f"    ↳ {len(files) - len(texts)} capture(s) ignored. If the shot plan changed, "
                  f"DELETE the stale names in {raw_path} — do not rely on this slice.")
    return files


def purge_stale_outputs(size_folder, keep, pattern="screenshot_*.png"):
    """Delete framed outputs numbered above `keep`.

    The framing step overwrites screenshot_01..N and leaves screenshot_(N+1).. untouched, so a
    5-shot set re-rendered as 4 keeps a stale fifth image — which then uploads as if it were current.
    """
    from pathlib import Path
    folder = Path(size_folder)
    if not folder.exists():
        return
    removed = []
    for f in sorted(folder.glob(pattern)):
        digits = ''.join(c for c in f.stem if c.isdigit())
        if digits and int(digits) > keep:
            f.unlink()
            removed.append(f.name)
    if removed:
        print(f"🧹 removed {len(removed)} stale output(s) beyond #{keep}: {', '.join(removed)}")

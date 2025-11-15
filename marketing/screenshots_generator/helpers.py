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


def load_or_get_font(font_path: str, size: int) -> ImageFont.FreeTypeFont:
    """Load a font or return default"""
    if font_path and os.path.exists(font_path):
        return ImageFont.truetype(font_path, size)

    try:
        return ImageFont.truetype('/System/Library/Fonts/Helvetica.ttc', size)
    except:
        try:
            return ImageFont.truetype('/Library/Fonts/Arial.ttf', size)
        except:
            return ImageFont.load_default()


def wrap_text(text: str, font: ImageFont.FreeTypeFont, max_width: int) -> List[str]:
    """Wrap text to fit within max_width"""
    words = text.split()
    lines = []
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

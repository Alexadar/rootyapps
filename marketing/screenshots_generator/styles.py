"""Style classes for screenshot generation"""

from PIL import Image, ImageDraw
from typing import Tuple
import os
from .helpers import (
    create_gradient_background,
    create_rounded_rectangle_mask,
    add_shadow,
    crop_screenshot,
    load_or_get_font,
    wrap_text
)


class ScreenshotStyle:
    """Base style class for screenshot generation"""

    def __init__(
        self,
        bg_gradient=True,
        bg_color_top='#1D1D1F',
        bg_color_bottom='#000000',
        title_color='#ffffff',
        subtitle_color='#F5F5F7',
        text_padding=80,
        screenshot_zoom=2.5,
        screenshot_crop='full',
        screenshot_move_down=0,
        screenshot_padding=80,
        border_width=12,
        border_color='#ffffff',
        border_radius=40,
        shadow=True,
        layout_type='default'
    ):
        self.bg_gradient = bg_gradient
        self.bg_color_top = bg_color_top
        self.bg_color_bottom = bg_color_bottom
        self.title_color = title_color
        self.subtitle_color = subtitle_color
        self.text_padding = text_padding
        self.screenshot_zoom = screenshot_zoom
        self.screenshot_crop = screenshot_crop
        self.screenshot_move_down = screenshot_move_down
        self.screenshot_padding = screenshot_padding
        self.border_width = border_width
        self.border_color = border_color
        self.border_radius = border_radius
        self.shadow = shadow
        self.layout_type = layout_type

    def render(self, screenshot_path: str, output_path: str, canvas_size: Tuple[int, int], title: str, subtitle: str = "") -> bool:
        """Must be implemented by subclass"""
        raise NotImplementedError("Subclass must implement render()")


class TwoColumnStyle(ScreenshotStyle):
    """2-column layout: text left, screenshot right"""

    def __init__(
        self,
        text_col_percent=42,
        screenshot_col_percent=58,
        screenshot_zoom=2.5,
        screenshot_crop='full',
        screenshot_move_down=0,
        **kwargs
    ):
        super().__init__(layout_type='2cols', screenshot_zoom=screenshot_zoom, screenshot_crop=screenshot_crop, screenshot_move_down=screenshot_move_down, **kwargs)
        self.text_col_percent = text_col_percent
        self.screenshot_col_percent = screenshot_col_percent

    def render(self, screenshot_path: str, output_path: str, canvas_size: Tuple[int, int], title: str, subtitle: str = "") -> bool:
        """Render 2-column screenshot"""

        # Load screenshot (no crop yet)
        screenshot = Image.open(screenshot_path).convert('RGBA')
        original_size = screenshot.size

        canvas_width, canvas_height = canvas_size
        text_col_width = int(canvas_width * self.text_col_percent / 100)
        screenshot_col_width = canvas_width - text_col_width

        # Create background
        if self.bg_gradient:
            canvas = create_gradient_background(canvas_width, canvas_height, self.bg_color_top, self.bg_color_bottom)
        else:
            canvas = Image.new('RGB', (canvas_width, canvas_height), self.bg_color_top)
        canvas = canvas.convert('RGBA')
        draw = ImageDraw.Draw(canvas)

        # === TEXT COLUMN ===
        scale_factor = canvas_width / 2880
        title_font = load_or_get_font(None, int(140 * scale_factor))
        subtitle_font = load_or_get_font(None, int(70 * scale_factor))

        text_padding = int(self.text_padding * scale_factor)
        title_lines = wrap_text(title, title_font, text_col_width - text_padding * 2)
        subtitle_lines = wrap_text(subtitle, subtitle_font, text_col_width - text_padding * 2) if subtitle else []

        # Draw text
        current_y = (canvas_height - len(title_lines) * 170 * scale_factor - len(subtitle_lines) * 100 * scale_factor) // 2
        for line in title_lines:
            draw.text((text_padding, int(current_y)), line, font=title_font, fill=self.title_color)
            current_y += 170 * scale_factor

        if subtitle_lines:
            current_y += 30 * scale_factor
            for line in subtitle_lines:
                draw.text((text_padding, int(current_y)), line, font=subtitle_font, fill=self.subtitle_color)
                current_y += 100 * scale_factor

        # === SCREENSHOT COLUMN: ZOOM FIRST, THEN MOVE ===
        screenshot_padding = int(self.screenshot_padding * scale_factor)
        available_width = screenshot_col_width - screenshot_padding * 2
        available_height = canvas_height - screenshot_padding * 2

        # Step 1: Calculate base size that would fit the ORIGINAL screenshot
        screenshot_ratio = screenshot.width / screenshot.height
        available_ratio = available_width / available_height

        if screenshot_ratio > available_ratio:
            base_width = available_width
            base_height = int(base_width / screenshot_ratio)
        else:
            base_height = available_height
            base_width = int(base_height * screenshot_ratio)

        # Step 2: Apply ZOOM relative to the base fitted size (not absolute)
        # This ensures zoom is proportional to canvas size and never overflows
        zoomed_width = int(base_width * self.screenshot_zoom)
        zoomed_height = int(base_height * self.screenshot_zoom)

        print(f"    Original: {original_size}, Base fit: {base_width}x{base_height}, Zoom: {self.screenshot_zoom}x, Zoomed: {zoomed_width}x{zoomed_height}")

        # Step 3: Resize to zoomed size
        screenshot_zoomed = screenshot.resize((zoomed_width, zoomed_height), Image.Resampling.LANCZOS)

        # Step 4: Add border to the FULL zoomed screenshot BEFORE cropping
        border_width = int(self.border_width * scale_factor)
        border_radius = int(self.border_radius * scale_factor)
        bordered_full_width = zoomed_width + border_width * 2
        bordered_full_height = zoomed_height + border_width * 2

        # Create border around full screenshot
        border_bg = Image.new('RGBA', (bordered_full_width, bordered_full_height), self.border_color)
        border_mask = create_rounded_rectangle_mask((bordered_full_width, bordered_full_height), border_radius)
        border_bg.putalpha(border_mask)

        screenshot_mask = create_rounded_rectangle_mask((zoomed_width, zoomed_height), max(0, border_radius - border_width))
        screenshot_zoomed.putalpha(screenshot_mask)
        border_bg.paste(screenshot_zoomed, (border_width, border_width), screenshot_zoomed)

        print(f"    Full bordered screenshot: {bordered_full_width}x{bordered_full_height}")

        # Step 5: Crop viewport from the bordered screenshot
        if self.screenshot_move_down > 0:
            offset_y = int(bordered_full_height * self.screenshot_move_down / 100)
            viewport_height = min(bordered_full_height - offset_y, available_height)
            screenshot_final = border_bg.crop((0, offset_y, bordered_full_width, offset_y + viewport_height))
            print(f"    MoveDown: {self.screenshot_move_down}%, Offset: {offset_y}px, Viewport: {screenshot_final.size}")
        else:
            viewport_height = min(bordered_full_height, available_height)
            screenshot_final = border_bg.crop((0, 0, bordered_full_width, viewport_height))

        bordered_width = screenshot_final.width
        bordered_height = screenshot_final.height
        print(f"    Final viewport with borders: {bordered_width}x{bordered_height}")

        # Position screenshot (center in column, allow overflow)
        screenshot_x = text_col_width + (screenshot_col_width - bordered_width) // 2
        screenshot_y = (canvas_height - bordered_height) // 2

        # Add shadow
        if self.shadow:
            shadow = add_shadow(screenshot_final, (30, 30), int(60 * scale_factor), '#000000')
            shadow_x = screenshot_x - int(60 * scale_factor)
            shadow_y = screenshot_y - int(60 * scale_factor)
            # Clip shadow to canvas bounds
            if shadow_x < 0 or shadow_y < 0 or shadow_x + shadow.width > canvas_width or shadow_y + shadow.height > canvas_height:
                paste_x = max(0, shadow_x)
                paste_y = max(0, shadow_y)
                crop_x = max(0, -shadow_x)
                crop_y = max(0, -shadow_y)
                crop_w = min(shadow.width - crop_x, canvas_width - paste_x)
                crop_h = min(shadow.height - crop_y, canvas_height - paste_y)
                shadow_cropped = shadow.crop((crop_x, crop_y, crop_x + crop_w, crop_y + crop_h))
                canvas.paste(shadow_cropped, (paste_x, paste_y), shadow_cropped)
            else:
                canvas.paste(shadow, (shadow_x, shadow_y), shadow)

        # Clip screenshot to canvas bounds while preserving border
        if screenshot_x < 0 or screenshot_y < 0 or screenshot_x + bordered_width > canvas_width or screenshot_y + bordered_height > canvas_height:
            paste_x = max(0, screenshot_x)
            paste_y = max(0, screenshot_y)
            crop_x = max(0, -screenshot_x)
            crop_y = max(0, -screenshot_y)
            crop_w = min(bordered_width - crop_x, canvas_width - paste_x)
            crop_h = min(bordered_height - crop_y, canvas_height - paste_y)
            screenshot_cropped = screenshot_final.crop((crop_x, crop_y, crop_x + crop_w, crop_y + crop_h))
            canvas.paste(screenshot_cropped, (paste_x, paste_y), screenshot_cropped)
            print(f"    Overflow clipped: paste at ({paste_x}, {paste_y}), crop from ({crop_x}, {crop_y}), size {crop_w}x{crop_h}")
        else:
            canvas.paste(screenshot_final, (screenshot_x, screenshot_y), screenshot_final)

        # Save
        final_image = canvas.convert('RGB')
        os.makedirs(os.path.dirname(output_path), exist_ok=True)
        final_image.save(output_path, 'PNG', quality=95)

        return True


# Pre-configured styles
style_default = TwoColumnStyle(screenshot_zoom=2.5)
style_zoom_high = TwoColumnStyle(screenshot_zoom=3.0)
style_top_zoom = TwoColumnStyle(screenshot_crop='top50', screenshot_zoom=2.5)
style_middle_zoom = TwoColumnStyle(screenshot_crop='middle50', screenshot_zoom=2.5)
style_bottom_zoom = TwoColumnStyle(screenshot_crop='bottom50', screenshot_zoom=2.5)

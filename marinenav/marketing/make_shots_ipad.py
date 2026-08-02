#!/usr/bin/env python3
"""Compose Marine Nav iPad App-Store screenshots (13" iPad, 2064x2752) from raw sim
captures: deep-navy ground + headline + subhead + the rounded app screenshot.

Screenshots MAY be framed (unlike app previews — see marketing/reels/README.md).
Every screenshot is a real capture of the shipped UI; nothing is mocked up.

Run: marketing/venv/bin/python3 marketing/make_shots_ipad.py
"""
from PIL import Image, ImageDraw, ImageFont
from pathlib import Path

APP = Path(__file__).resolve().parent.parent          # marinenav/
RAW = APP / "marketing" / "raw" / "ipad"
OUT = APP / "marketing" / "aso" / "ipad" / "2064x2752"
OUT.mkdir(parents=True, exist_ok=True)

W, H = 2064, 2752
NAVY  = (0x0B, 0x1A, 0x2B)
DEEP  = (0x06, 0x10, 0x1C)
AQUA  = (0x4A, 0xD8, 0xFB)
INK   = (0xFF, 0xFF, 0xFF)
MUTED = (0xD5, 0xE3, 0xEE)

BOLD = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"
REG  = "/System/Library/Fonts/Supplemental/Arial.ttf"

def font(path, size):
    return ImageFont.truetype(path, size)

# The differentiator has to be VISIBLE in the store listing, not merely true in
# the code (App Review 4.3(b)) — so "offline", "NOAA" and "no subscription" all
# appear in the captions.
SCENES = [
    ("01_tides",           ["Tide times that work", "with no signal."],
                           "NOAA harmonic constants, computed on your device."),
    ("02_currents",        ["Slack, flood", "and ebb."],
                           "Know when the gate turns — to the minute, offline."),
    ("03_declination",     ["True to magnetic,", "done properly."],
                           "World Magnetic Model 2025, built in. No lookup needed."),
    ("04_distanceBearing", ["Great-circle", "passage planning."],
                           "Vincenty on WGS-84 — distance, course, arrival."),
    ("05_sightReduction",  ["Sight reduction,", "by the book."],
                           "Reproduces Bowditch's worked example exactly."),
]

def rounded(img, radius):
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, img.size[0], img.size[1]], radius, fill=255)
    out = Image.new("RGBA", img.size, (0, 0, 0, 0))
    out.paste(img, (0, 0), mask)
    return out

def vertical_gradient(size, top, bottom):
    g = Image.new("RGB", (1, size[1]))
    for y in range(size[1]):
        t = y / max(size[1] - 1, 1)
        g.putpixel((0, y), tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))
    return g.resize(size)

def wrap_lines(draw, lines, f, max_w):
    """Shrink until the longest line fits — captions must never clip."""
    while True:
        widest = max(draw.textbbox((0, 0), ln, font=f)[2] for ln in lines)
        if widest <= max_w or f.size <= 40:
            return f
        f = font(BOLD, f.size - 4)

def compose(name, headline, sub):
    canvas = vertical_gradient((W, H), NAVY, DEEP)
    d = ImageDraw.Draw(canvas)

    # wordmark
    fw = font(BOLD, 46)
    d.text((132, 108), "MARINE NAV", font=fw, fill=AQUA)

    # headline
    fh = wrap_lines(d, headline, font(BOLD, 108), W - 264)
    y = 190
    for ln in headline:
        d.text((132, y), ln, font=fh, fill=INK)
        y += int(fh.size * 1.16)

    # subhead
    fs = font(REG, 50)
    y += 14
    d.text((132, y), sub, font=fs, fill=MUTED)
    y += int(fs.size * 1.9)

    # the real capture, rounded, centred, filling the rest
    shot = Image.open(RAW / f"{name}.png").convert("RGB")
    avail_h = H - y - 96
    scale = min((W - 264) / shot.width, avail_h / shot.height)
    sw, sh = int(shot.width * scale), int(shot.height * scale)
    shot = shot.resize((sw, sh), Image.LANCZOS)
    shot = rounded(shot, 56)

    x = (W - sw) // 2
    # soft edge under the shot so it sits on the ground rather than floating
    d.rounded_rectangle([x - 6, y - 6, x + sw + 6, y + sh + 6], 62,
                        outline=(0x1B, 0x33, 0x4A), width=6)
    canvas.paste(shot, (x, y), shot)

    out = OUT / f"{name}.png"
    canvas.convert("RGB").save(out, "PNG")          # RGB, no alpha, per store rules
    print(f"  {out.relative_to(APP)}  {canvas.size[0]}x{canvas.size[1]}")

if __name__ == "__main__":
    print(f"composing {len(SCENES)} screenshots -> {OUT.relative_to(APP)}")
    for name, headline, sub in SCENES:
        compose(name, headline, sub)

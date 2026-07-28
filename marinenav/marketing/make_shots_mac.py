#!/usr/bin/env python3
"""Compose Marine Nav Mac App-Store screenshots (2880x1800) from raw window captures.

The raw shots are single-window grabs (`screencapture -l <CGWindowID> -o`), so they carry
the real app and nothing of the desktop behind it. Composed onto the same deep-navy ground
as the iPhone set so the two listings read as one product.

Run: marketing/venv/bin/python3 marketing/make_shots_mac.py
"""
from PIL import Image, ImageDraw, ImageFont
from pathlib import Path

APP = Path(__file__).resolve().parent.parent
RAW = APP / "marketing" / "raw" / "mac"
OUT = APP / "marketing" / "aso" / "mac" / "2880x1800"
OUT.mkdir(parents=True, exist_ok=True)

W, H = 2880, 1800                       # required Mac App Store size
NAVY, DEEP = (0x0B, 0x1A, 0x2B), (0x06, 0x10, 0x1C)
AQUA, INK, MUTED = (0x4A, 0xD8, 0xFB), (0xFF, 0xFF, 0xFF), (0xD5, 0xE3, 0xEE)
BOLD = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"
REG  = "/System/Library/Fonts/Supplemental/Arial.ttf"

def font(p, s): return ImageFont.truetype(p, s)

SCENES = [
    ("01_tides",           "Tide times that work with no signal.",
                           "NOAA harmonic constants, computed on your Mac."),
    ("02_currents",        "Slack, flood and ebb.",
                           "Know when the gate turns — to the minute, offline."),
    ("03_declination",     "True to magnetic, done properly.",
                           "World Magnetic Model 2025, built in. No lookup needed."),
    ("04_distanceBearing", "Great-circle passage planning.",
                           "Vincenty on WGS-84 — distance, course, arrival."),
    ("05_sightReduction",  "Sight reduction, by the book.",
                           "Reproduces Bowditch's worked example exactly."),
]

def rounded(img, r):
    m = Image.new("L", img.size, 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, *img.size], r, fill=255)
    o = Image.new("RGBA", img.size, (0, 0, 0, 0)); o.paste(img, (0, 0), m); return o

def gradient(size, top, bot):
    g = Image.new("RGB", (1, size[1]))
    for y in range(size[1]):
        t = y / max(size[1] - 1, 1)
        g.putpixel((0, y), tuple(int(top[i] + (bot[i] - top[i]) * t) for i in range(3)))
    return g.resize(size)

def fit(draw, text, f, max_w):
    while draw.textbbox((0, 0), text, font=f)[2] > max_w and f.size > 34:
        f = font(BOLD, f.size - 3)
    return f

def compose(name, headline, sub):
    c = gradient((W, H), NAVY, DEEP)
    d = ImageDraw.Draw(c)
    d.text((132, 96), "MARINE NAV", font=font(BOLD, 40), fill=AQUA)
    fh = fit(d, headline, font(BOLD, 86), W - 264)
    d.text((132, 156), headline, font=fh, fill=INK)
    d.text((132, 156 + int(fh.size * 1.35)), sub, font=font(REG, 40), fill=MUTED)

    top = 156 + int(fh.size * 1.35) + 96
    shot = Image.open(RAW / f"{name}.png").convert("RGB")
    scale = min((W - 264) / shot.width, (H - top - 90) / shot.height)
    sw, sh = int(shot.width * scale), int(shot.height * scale)
    shot = rounded(shot.resize((sw, sh), Image.LANCZOS), 22)
    x = (W - sw) // 2
    d.rounded_rectangle([x - 5, top - 5, x + sw + 5, top + sh + 5], 27,
                        outline=(0x1B, 0x33, 0x4A), width=5)
    c.paste(shot, (x, top), shot)
    out = OUT / f"{name}.png"
    c.convert("RGB").save(out, "PNG")
    print(f"  {out.relative_to(APP)}  {c.size[0]}x{c.size[1]}")

if __name__ == "__main__":
    print(f"composing {len(SCENES)} Mac screenshots -> {OUT.relative_to(APP)}")
    for n, h, s in SCENES:
        compose(n, h, s)

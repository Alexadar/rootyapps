#!/usr/bin/env python3
"""Compose KERF App-Store screenshots (6.9" iPhone, 1320×2868) from raw sim captures:
concrete-paper background + bold headline + subhead + the rounded app screenshot + KERF wordmark."""
from PIL import Image, ImageDraw, ImageFont, ImageFilter
from pathlib import Path

APP = Path(__file__).resolve().parent.parent          # kerfcalc.swift
RAW = APP / "marketing" / "raw"
OUT = APP / "marketing" / "aso" / "ios" / "1320x2868"
OUT.mkdir(parents=True, exist_ok=True)

W, H = 1320, 2868
PAPER = (0xED, 0xE9, 0xE0)
INK = (0x16, 0x17, 0x1B)
SECOND = (0x6E, 0x6F, 0x75)
SIGNAL = (0xE8, 0xFB, 0x4A)

BOLD = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"
REG = "/System/Library/Fonts/Supplemental/Arial.ttf"
MONO = "/System/Library/Fonts/Menlo.ttc"

def font(path, size): return ImageFont.truetype(path, size)

SCENES = [
    ("01_spec",     ["Feet-inch math,", "done right."],  "The tape calculator that thinks in 1/16\"."),
    ("02_formulas", ["16 trade", "calculators."],         "Framing, concrete, takeoff — searchable."),
    ("03_rafter",   ["Rafters", "in seconds."],           "Common · hip · valley · jack, with the cuts."),
    ("04_stairs",   ["Stairs", "to code."],               "Live IRC & IBC riser / tread checks."),
    ("05_concrete", ["Concrete", "takeoffs."],            "Yards, bags, trucks — no guessing."),
]

def rounded(img, radius):
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, img.size[0], img.size[1]], radius, fill=255)
    out = Image.new("RGBA", img.size, (0, 0, 0, 0))
    out.paste(img, (0, 0), mask)
    return out

def compose(name, headline, sub):
    canvas = Image.new("RGB", (W, H), PAPER)
    d = ImageDraw.Draw(canvas)

    # wordmark: KERF + signal square
    fw = font(BOLD, 46)
    d.text((90, 150), "Kerf Calc", font=fw, fill=INK)
    kw = d.textlength("Kerf Calc", font=fw)
    d.rounded_rectangle([90 + kw + 16, 168, 90 + kw + 16 + 18, 186], 4, fill=SIGNAL)

    # headline (1-2 lines)
    fh = font(BOLD, 96)
    y = 250
    for line in headline:
        d.text((88, y), line, font=fh, fill=INK)
        y += 108
    # subhead
    fs = font(REG, 44)
    d.text((90, y + 18), sub, font=fs, fill=SECOND)

    # screenshot — scaled, rounded, shadowed, bottom-anchored
    shot = Image.open(RAW / f"{name}.png").convert("RGB")
    target_h = 2020
    scale = target_h / shot.height
    sw, sh = int(shot.width * scale), target_h
    shot = shot.resize((sw, sh), Image.LANCZOS)
    shot = rounded(shot, 54)
    x = (W - sw) // 2
    yy = H - sh - 70
    # soft shadow
    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle([x, yy + 14, x + sw, yy + sh + 14], 54, fill=(0, 0, 0, 60))
    shadow = shadow.filter(ImageFilter.GaussianBlur(26))
    canvas.paste(Image.alpha_composite(canvas.convert("RGBA"), shadow).convert("RGB"), (0, 0))
    canvas.paste(shot, (x, yy), shot)

    out = OUT / f"{name}.png"
    canvas.save(out, "PNG")
    print("  wrote", out.name)

if __name__ == "__main__":
    for name, head, sub in SCENES:
        compose(name, head, sub)

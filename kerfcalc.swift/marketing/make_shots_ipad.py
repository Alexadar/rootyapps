#!/usr/bin/env python3
"""KERF iPad App-Store screenshots (13", 2064×2752) — caption band + rounded split-view shot."""
from PIL import Image, ImageDraw, ImageFont, ImageFilter
from pathlib import Path

APP = Path(__file__).resolve().parent.parent
RAW = APP / "marketing" / "raw" / "ipad"
OUT = APP / "marketing" / "aso" / "ipad" / "2064x2752"
OUT.mkdir(parents=True, exist_ok=True)

W, H = 2064, 2752
PAPER = (0xED, 0xE9, 0xE0); INK = (0x16, 0x17, 0x1B); SECOND = (0x6E, 0x6F, 0x75); SIGNAL = (0xE8, 0xFB, 0x4A)
BOLD = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"; REG = "/System/Library/Fonts/Supplemental/Arial.ttf"

SCENES = [
    ("01_spec",     ["Feet-inch —", "and area, too."], "10' × 8' = 80 sq ft, right on the tape."),
    ("02_rafter",   ["Rafters,", "dead-on."],          "Actual cut: line + overhang − ½ ridge, with the code."),
    ("03_concrete", ["Concrete", "takeoffs."],         "Yards, bags, trucks — plus a waste allowance."),
    ("04_stairs",   ["Stairs", "to code."],            "Live IRC riser, tread & headroom checks."),
    ("05_roofing",  ["Roofing", "squares."],           "Pitch-adjusted, ready to order."),
    ("06_offset",   ["Pipe offsets,", "solved."],       "Set, travel, run and the fitting multiplier."),
]

def font(p, s): return ImageFont.truetype(p, s)
def rounded(img, r):
    m = Image.new("L", img.size, 0); ImageDraw.Draw(m).rounded_rectangle([0, 0, *img.size], r, fill=255)
    o = Image.new("RGBA", img.size, (0, 0, 0, 0)); o.paste(img, (0, 0), m); return o

def compose(name, head, sub):
    c = Image.new("RGB", (W, H), PAPER); d = ImageDraw.Draw(c)
    fw = font(BOLD, 62); d.text((150, 150), "Kerf Calc", font=fw, fill=INK)
    kw = d.textlength("Kerf Calc", font=fw); d.rounded_rectangle([150 + kw + 22, 175, 150 + kw + 22 + 24, 199], 5, fill=SIGNAL)
    fh = font(BOLD, 128); y = 270
    for line in head:
        d.text((146, y), line, font=fh, fill=INK); y += 146
    d.text((150, y + 24), sub, font=font(REG, 58), fill=SECOND)

    shot = Image.open(RAW / f"{name}.png").convert("RGB")
    th = 1820; scale = th / shot.height; sw, sh = int(shot.width * scale), th
    shot = rounded(shot.resize((sw, sh), Image.LANCZOS), 40)
    x = (W - sw) // 2; yy = H - sh - 90
    sh_img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(sh_img).rounded_rectangle([x, yy + 16, x + sw, yy + sh + 16], 40, fill=(0, 0, 0, 55))
    sh_img = sh_img.filter(ImageFilter.GaussianBlur(30))
    c.paste(Image.alpha_composite(c.convert("RGBA"), sh_img).convert("RGB"), (0, 0))
    c.paste(shot, (x, yy), shot)
    c.save(OUT / f"{name}.png", "PNG"); print("  wrote", name)

if __name__ == "__main__":
    for n, h, s in SCENES: compose(n, h, s)

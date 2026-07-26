#!/usr/bin/env python3
"""KERF macOS App-Store screenshots (2880×1800) — caption band + rounded app window."""
from PIL import Image, ImageDraw, ImageFont, ImageFilter
from pathlib import Path

APP = Path(__file__).resolve().parent.parent
RAW = APP / "marketing" / "raw" / "mac"
OUT = APP / "marketing" / "aso" / "mac" / "2880x1800"
OUT.mkdir(parents=True, exist_ok=True)

W, H = 2880, 1800
PAPER = (0xED, 0xE9, 0xE0); INK = (0x16, 0x17, 0x1B); SECOND = (0x6E, 0x6F, 0x75); SIGNAL = (0xE8, 0xFB, 0x4A)
BOLD = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"; REG = "/System/Library/Fonts/Supplemental/Arial.ttf"

SCENES = [
    ("01_spec",     "Feet-inch, done right.",  "Add, subtract, multiply — right on the tape."),
    ("02_rafter",   "Rafters, dead-on.",       "Actual cut length, with the code it cites."),
    ("03_concrete", "Concrete takeoffs.",      "Yards, bags, ready-mix trucks — plus waste."),
    ("04_stairs",   "Stairs to code.",         "Live IRC riser, tread & headroom checks."),
    ("05_roofing",  "Roofing squares.",        "Pitch-adjusted and ready to order."),
]

def font(p, s): return ImageFont.truetype(p, s)
def rounded(img, r):
    m = Image.new("L", img.size, 0); ImageDraw.Draw(m).rounded_rectangle([0, 0, *img.size], r, fill=255)
    o = Image.new("RGBA", img.size, (0, 0, 0, 0)); o.paste(img, (0, 0), m); return o

def compose(name, head, sub):
    c = Image.new("RGB", (W, H), PAPER); d = ImageDraw.Draw(c)
    fw = font(BOLD, 52); d.text((150, 110), "Kerf Calc", font=fw, fill=INK)
    kw = d.textlength("Kerf Calc", font=fw); d.rounded_rectangle([150 + kw + 20, 130, 150 + kw + 20 + 20, 150], 5, fill=SIGNAL)
    d.text((146, 180), head, font=font(BOLD, 96), fill=INK)
    d.text((150, 300), sub, font=font(REG, 50), fill=SECOND)

    win = Image.open(RAW / f"{name}.png").convert("RGB")
    tw = 2360; scale = tw / win.width; sw, sh = tw, int(win.height * scale)
    win = rounded(win.resize((sw, sh), Image.LANCZOS), 26)
    x = (W - sw) // 2; yy = 420
    sh_img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(sh_img).rounded_rectangle([x, yy + 20, x + sw, yy + sh + 20], 26, fill=(0, 0, 0, 60))
    sh_img = sh_img.filter(ImageFilter.GaussianBlur(34))
    c.paste(Image.alpha_composite(c.convert("RGBA"), sh_img).convert("RGB"), (0, 0))
    c.paste(win, (x, yy), win)
    c.save(OUT / f"{name}.png", "PNG"); print("  wrote", name)

if __name__ == "__main__":
    for n, h, s in SCENES: compose(n, h, s)

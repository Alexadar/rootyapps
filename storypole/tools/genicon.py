#!/usr/bin/env python3
"""Generate storypole.icon/Assets/1024.png — the app's own tape, full bleed.

This is not an illustration of a tape measure; it is **the same blade the app draws**, cropped to
the icon. It mirrors `Storypole/Calc/TapeView.swift` → `drawWindow(_:_:tape:)`:

    same colours    SP.tapeBody → SP.tapeEdge gradient, SP.tapeMark ticks, SP.tapeCursor
    same hierarchy  inches tall, halves/quarters medium, eighths short, hanging from the top edge
    same cursor     a full-height keel line with a round cap at the top

DESIGN NOTES
------------
*Full bleed.* The blade fills the frame edge to edge, so the icon reads as a close crop of the
instrument rather than a picture of one sitting on a background. The icon mask can crop corners
freely because nothing important lives there.

*Why eighths and not sixteenths.* At ~60 pt on the home screen, 1024 px maps at roughly 17:1. Two
inches of blade across the frame puts an eighth at 64 px ≈ 3.8 pt, which still reads; sixteenths
would collapse into grey mush. The app shows sixteenths because it is 400 pt wide, not 60.

*Supersampled 4×* — PIL does not antialias polygon edges.

Run: /opt/homebrew/opt/python@3.14/bin/python3.14 tools/genicon.py
"""
from PIL import Image, ImageDraw
import os

S, SS = 1024, 4
N = S * SS

# Tokens copied from DesignShared/Tokens.swift (light appearance).
TAPE_HI   = (0xF7, 0xD4, 0x66)     # just above SP.tapeBody, so the top edge catches light
TAPE_BODY = (0xF2, 0xC9, 0x4C)     # SP.tapeBody
TAPE_LO   = (0xDD, 0xAB, 0x26)     # toward SP.tapeEdge
MARK      = (0x1C, 0x1A, 0x17)     # SP.tapeMark
CURSOR    = (0xB9, 0x3C, 0x09)     # SP.tapeCursor
CURSOR_HI = (0xD8, 0x4E, 0x14)

SPAN_IN   = 2.0                    # inches of blade across the icon
PPI       = N / SPAN_IN
CURSOR_AT = 0.46                   # where the mark sits, as a fraction of the width

img = Image.new("RGB", (N, N))
d = ImageDraw.Draw(img)

# ── The blade, full bleed ────────────────────────────────────────────────────────────────────
# Three stops: a lit upper curl, the body, then deepening toward the bottom — the same curl the
# app suggests with its LinearGradient, just with more room to show it.
for y in range(N):
    f = y / (N - 1)
    if f < 0.18:
        t = f / 0.18
        c = tuple(int(TAPE_HI[k] + (TAPE_BODY[k] - TAPE_HI[k]) * t) for k in range(3))
    else:
        t = (f - 0.18) / 0.82
        c = tuple(int(TAPE_BODY[k] + (TAPE_LO[k] - TAPE_BODY[k]) * t) for k in range(3))
    d.line([(0, y), (N, y)], fill=c)

# ── Graduations, hanging from the top edge ───────────────────────────────────────────────────
# Same rule as the app: whole inches tall and heavy, halves and quarters medium, eighths short.
start_in = -SPAN_IN * CURSOR_AT                      # puts a whole inch under the cursor
for i in range(-4, int(SPAN_IN * 8) + 5):
    x = (i / 8) * PPI
    if x < -60 * SS or x > N + 60 * SS:
        continue
    if   i % 8 == 0: h, w, op = 0.60, 28, 1.00       # 1"
    elif i % 4 == 0: h, w, op = 0.42, 22, 0.90       # 1/2"
    elif i % 2 == 0: h, w, op = 0.29, 18, 0.78       # 1/4"
    else:            h, w, op = 0.17, 13, 0.58       # 1/8"
    half = w * SS / 2
    ink = tuple(int(MARK[k] * op + TAPE_BODY[k] * (1 - op)) for k in range(3))
    d.rounded_rectangle([x - half, -30 * SS, x + half, N * h], radius=half, fill=ink)

# ── The keel mark ────────────────────────────────────────────────────────────────────────────
# The cursor straight out of `TapeView`: a full-height line in SP.tapeCursor with a round cap on
# top. It is the only red in the app, and it means "your measurement is here".
cx = N * CURSOR_AT
CW = 46 * SS / 2
for y in range(N):
    f = y / (N - 1)
    c = tuple(int(CURSOR_HI[k] + (CURSOR[k] - CURSOR_HI[k]) * f) for k in range(3))
    d.line([(cx - CW, y), (cx + CW, y)], fill=c)

CAP = 96 * SS / 2
d.ellipse([cx - CAP, 30 * SS - CAP, cx + CAP, 30 * SS + CAP], fill=CURSOR_HI)

out_img = img.resize((S, S), Image.LANCZOS).convert("RGBA")
out = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                   "storypole.icon", "Assets", "1024.png")
os.makedirs(os.path.dirname(out), exist_ok=True)
out_img.save(out)

for pt in (180, 120, 80, 60, 40):
    out_img.resize((pt, pt), Image.LANCZOS).save(f"/tmp/icon_check_{pt}.png")
print("wrote", out)

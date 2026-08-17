#!/usr/bin/env python3
"""GridScan app icon — 3x3 grid of rounded cells (the user's pick).

Draws the ARTWORK LAYER ONLY on transparency; the .icon bundle's automatic-gradient
(blue ramp echoing GS.tint #007AFF) supplies the body. Repo conventions: supersample 4x
then LANCZOS downsample; palette from the app's tokens, not invented.

The motif must be vertically AND horizontally symmetrical — asserted below as an exact
pixel test (image == its own mirror on both axes), not left as an intention.

Run: python3 tools/make_icon.py     (writes gridscan.icon/Assets/1024.png)
"""
from PIL import Image, ImageDraw, ImageOps
import pathlib

SIZE = 1024
SS = 4
W = SIZE * SS

# Nine cells, near-white so the gradient body reads through the translucency layer.
CELL = (255, 255, 255, 255)

# Geometry (all in 1024-space, chosen symmetric about the canvas centre 512):
# 3 cells of 200 + 2 gutters of 42 = 684 content; margin = (1024-684)/2 = 170.
CELL_SIDE = 200
GUTTER = 42
CONTENT = 3 * CELL_SIDE + 2 * GUTTER
MARGIN = (SIZE - CONTENT) // 2
RADIUS = 46

assert MARGIN * 2 + CONTENT == SIZE, "content must centre exactly for symmetry"

img = Image.new("RGBA", (W, W), (0, 0, 0, 0))
draw = ImageDraw.Draw(img)

for r in range(3):
    for c in range(3):
        x0 = (MARGIN + c * (CELL_SIDE + GUTTER)) * SS
        y0 = (MARGIN + r * (CELL_SIDE + GUTTER)) * SS
        x1 = x0 + CELL_SIDE * SS
        y1 = y0 + CELL_SIDE * SS
        draw.rounded_rectangle([x0, y0, x1 - 1, y1 - 1], radius=RADIUS * SS, fill=CELL)

icon = img.resize((SIZE, SIZE), Image.LANCZOS)

# Symmetry is a checked property: exact equality with both mirrors.
assert icon.tobytes() == ImageOps.mirror(icon).tobytes(), "not horizontally symmetric"
assert icon.tobytes() == ImageOps.flip(icon).tobytes(), "not vertically symmetric"

out = pathlib.Path(__file__).resolve().parent.parent / "gridscan.icon" / "Assets"
out.mkdir(parents=True, exist_ok=True)
icon.save(out / "1024.png")
print(f"wrote {out / '1024.png'} ({CONTENT}pt grid, margins {MARGIN}pt, symmetric ok)")

#!/usr/bin/env python3
"""Draw the Froggo 2 icon layer.

Icon Composer composites this over the blue gradient declared in `froggo2.icon/icon.json`, so what
is drawn here is the frog alone on transparency — the same frog the game renders, in the same
palette, at the angle the camera sees it from.

Palette is froggo 1's, unchanged (PROMPT.md §6a: do not invent a new one):
    #30D158  frog body, Apple systemGreen (dark)
    #34C759  frog second tone
    #FFFFFF  eyes and belly
    #1A0D0D  outline accent, the palette's only dark

Run:  python3 tools/make_icon.py
"""

from PIL import Image, ImageDraw, ImageFilter
import pathlib

SIZE = 1024
BODY = (0x30, 0xD1, 0x58, 255)
BODY_LIGHT = (0x34, 0xC7, 0x59, 255)
WHITE = (0xFF, 0xFF, 0xFF, 255)
DARK = (0x1A, 0x0D, 0x0D, 255)

# Supersample, then downsample: gives clean edges without hinting at any particular renderer.
SS = 4
W = SIZE * SS


def rounded(draw, box, radius, fill):
    draw.rounded_rectangle(box, radius=radius, fill=fill)


def main():
    img = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    cx = W // 2
    # Sit the frog slightly low so the eyes land near the optical centre — an icon is read by its
    # face, and at Home-Screen size the eyes are the only thing that survives.
    cy = int(W * 0.60)

    body_w = int(W * 0.60)
    body_h = int(W * 0.42)

    # Hind legs, tucked either side — the silhouette that says "about to jump".
    leg_w, leg_h = int(W * 0.15), int(W * 0.20)
    for side in (-1, 1):
        lx = cx + side * int(body_w * 0.47)
        rounded(d, [lx - leg_w // 2, cy - int(body_h * 0.05),
                    lx + leg_w // 2, cy - int(body_h * 0.05) + leg_h],
                radius=leg_w // 2, fill=BODY_LIGHT)

    # Body.
    rounded(d, [cx - body_w // 2, cy - body_h // 2, cx + body_w // 2, cy + body_h // 2],
            radius=int(body_h * 0.46), fill=BODY)

    # Belly, the same white as the sprite's underside.
    belly_w, belly_h = int(body_w * 0.56), int(body_h * 0.34)
    rounded(d, [cx - belly_w // 2, cy + int(body_h * 0.06),
                cx + belly_w // 2, cy + int(body_h * 0.06) + belly_h],
            radius=int(belly_h * 0.5), fill=WHITE)

    # Eyes: high, proud of the head, and large. This is the whole recognisability budget.
    eye_r = int(W * 0.115)
    eye_y = cy - int(body_h * 0.52)
    for side in (-1, 1):
        ex = cx + side * int(body_w * 0.27)
        # A green socket so the eyes read as part of the animal rather than stuck on.
        d.ellipse([ex - eye_r - int(W * 0.022), eye_y - eye_r - int(W * 0.022),
                   ex + eye_r + int(W * 0.022), eye_y + eye_r + int(W * 0.022)],
                  fill=BODY_LIGHT)
        d.ellipse([ex - eye_r, eye_y - eye_r, ex + eye_r, eye_y + eye_r], fill=WHITE)
        pupil_r = int(eye_r * 0.44)
        # Pupils angled slightly inward and down — looking at the next rooftop.
        px = ex + side * int(eye_r * 0.12)
        py = eye_y + int(eye_r * 0.18)
        d.ellipse([px - pupil_r, py - pupil_r, px + pupil_r, py + pupil_r], fill=DARK)

    # A soft contact shadow under the frog, in the palette's only dark, so it sits on the gradient
    # rather than floating over it.
    shadow = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    sw, sh = int(body_w * 0.86), int(W * 0.055)
    sy = cy + body_h // 2 + int(W * 0.035)
    sd.ellipse([cx - sw // 2, sy - sh // 2, cx + sw // 2, sy + sh // 2],
               fill=(DARK[0], DARK[1], DARK[2], 90))
    shadow = shadow.filter(ImageFilter.GaussianBlur(radius=W * 0.018))

    out = Image.alpha_composite(shadow, img)
    out = out.resize((SIZE, SIZE), Image.LANCZOS)

    dest = pathlib.Path(__file__).resolve().parent.parent / "froggo2.icon" / "Assets" / "Icon-Store-1024.png"
    dest.parent.mkdir(parents=True, exist_ok=True)
    out.save(dest)
    print(f"wrote {dest}")


if __name__ == "__main__":
    main()

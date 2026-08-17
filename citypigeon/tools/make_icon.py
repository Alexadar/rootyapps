#!/usr/bin/env python3
"""Draw the City Pigeon icon layer.

Icon Composer composites this over the sky-blue gradient declared in `citypigeon.icon/icon.json`, so
what is drawn here is the pigeon and the skyline alone, on transparency — the same pigeon the game
renders, in the same palette, from the same side-on angle the camera uses.

PROMPT §7 is the constraint that shapes this: **the icon is the pigeon and the city, never the
payload**, and App Store creative must meet a 4+ standard whatever the app's own rating turns out to
be. There is nothing falling in this picture.

Palette is froggo 1's, measured from its shipped PNGs and unchanged (PROMPT §4 — do not invent one):
    #ACACAC  pigeon body            (the haze grey)
    #64D2FF  neck iridescence       (the sky accent)
    #FFA90A  beak and feet          (systemOrange, the lit-window colour)
    #1A0D0D  outline                (the palette's only dark)
    #0A84FF  building facades       (systemBlue)
    #FFFFFF  window glint

Run:  python3 tools/make_icon.py
"""

from PIL import Image, ImageDraw
import pathlib

SIZE = 1024
SS = 4                      # supersample, then downsample — clean edges, no renderer fingerprint
W = SIZE * SS

BODY = (0xAC, 0xAC, 0xAC, 255)
WING = (0x8C, 0x8C, 0x8C, 255)
NECK = (0x64, 0xD2, 0xFF, 255)
BEAK = (0xFF, 0xA9, 0x0A, 255)
DARK = (0x1A, 0x0D, 0x0D, 255)
FACADE = (0x0A, 0x84, 0xFF, 255)
FACADE_DIM = (0x08, 0x66, 0xC4, 255)
WINDOW = (0xFF, 0xFF, 0xFF, 255)


def s(v):
    """Scale a 0-1024 design coordinate into supersampled space."""
    return int(v * SS)


def skyline(d):
    """A low skyline across the bottom third — the city, in one gesture.

    Kept low and simple on purpose: at 60 px on a Home Screen the pigeon has to be the only thing
    the eye resolves, and a detailed city would fight it.
    """
    blocks = [
        # (x, width, height, dim?)
        (-30, 150, 210, True),
        (110, 120, 300, False),
        (215, 105, 235, True),
        (305, 140, 340, False),
        (430, 110, 250, True),
        (525, 135, 315, False),
        (645, 115, 225, True),
        (745, 150, 290, False),
        (880, 130, 245, True),
        (995, 90, 200, False),
    ]
    base = 1024
    for x, w, h, dim in blocks:
        top = base - h
        d.rectangle([s(x), s(top), s(x + w), s(base)], fill=FACADE_DIM if dim else FACADE)
        # Window grid. Two columns per block is enough to read as a building.
        cols = max(2, w // 46)
        rows = max(2, h // 58)
        for c in range(cols):
            for r in range(rows):
                wx = x + 16 + c * ((w - 24) / max(1, cols))
                wy = top + 26 + r * ((h - 34) / max(1, rows))
                if wx + 18 > x + w - 6 or wy + 22 > base - 6:
                    continue
                d.rectangle([s(wx), s(wy), s(wx + 18), s(wy + 22)],
                            fill=WINDOW + () if False else (*WINDOW[:3], 150))


def pigeon(d):
    """The bird, in profile, flying left→right — the game's own reading.

    Built from the same handful of rounded boxes the renderer uses, so the icon and the thing it
    advertises are recognisably one object.
    """
    cx, cy = 512, 470

    # Far wing first, so the near one overlaps it.
    d.rounded_rectangle([s(cx - 150), s(cy - 168), s(cx + 96), s(cy - 40)], radius=s(56), fill=WING)

    # Tail.
    d.rounded_rectangle([s(cx - 320), s(cy - 6), s(cx - 150), s(cy + 78)], radius=s(28), fill=WING)

    # Body.
    d.rounded_rectangle([s(cx - 210), s(cy - 78), s(cx + 130), s(cy + 106)], radius=s(88), fill=BODY)

    # Neck and head, lifted and forward.
    d.rounded_rectangle([s(cx + 60), s(cy - 140), s(cx + 196), s(cy + 10)], radius=s(62), fill=NECK)
    d.rounded_rectangle([s(cx + 96), s(cy - 178), s(cx + 232), s(cy - 42)], radius=s(64), fill=BODY)

    # Beak.
    d.polygon([(s(cx + 226), s(cy - 132)), (s(cx + 310), s(cy - 108)), (s(cx + 226), s(cy - 84))],
              fill=BEAK)

    # Eye — one dark dot, and it is what makes the whole thing read as a bird.
    d.ellipse([s(cx + 168), s(cy - 146), s(cx + 206), s(cy - 108)], fill=DARK)

    # Near wing, raised mid-beat.
    d.rounded_rectangle([s(cx - 176), s(cy - 232), s(cx + 78), s(cy - 78)], radius=s(60), fill=BODY)

    # Feet, tucked.
    d.rounded_rectangle([s(cx - 40), s(cy + 90), s(cx + 34), s(cy + 140)], radius=s(20), fill=BEAK)


def main():
    img = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    d = ImageDraw.Draw(img, "RGBA")

    skyline(d)
    pigeon(d)

    out = img.resize((SIZE, SIZE), Image.LANCZOS)
    dest = pathlib.Path(__file__).resolve().parent.parent / "citypigeon.icon" / "Assets"
    dest.mkdir(parents=True, exist_ok=True)
    path = dest / "Icon-Store-1024.png"
    out.save(path)
    print(f"wrote {path}")


if __name__ == "__main__":
    main()

"""genicon.py — Earth Around app icon: the hot Sun.

House pattern (see calculators/tools/genicon_*.py): drawn programmatically at 1024 with
PIL, no external art. Rendered at 2x and downsampled, because a single blurred ellipse
bands into visible blocks at icon sizes.

    python genicon.py            # writes into both asset catalogs

Palette is the app's own: the Aurora HUD space navy behind a white-hot core grading out
through the severity ramp's amber to a deep red limb.
"""
from PIL import Image, ImageDraw, ImageFilter
from pathlib import Path

S = 1024
SS = S * 2
APP = Path(__file__).resolve().parent.parent
TARGETS = [
    APP / "eartharound.swift/Assets.xcassets/AppIcon.appiconset",
    APP / "SpaceWeatherWatch/Assets.xcassets/AppIcon.appiconset",
]
MAC_SIZES = [16, 32, 64, 128, 256, 512, 1024]      # filenames the Contents.json expects


def background(top=(10, 17, 31), bottom=(3, 6, 12)):
    img = Image.new("RGB", (SS, SS))
    px = img.load()
    for y in range(SS):
        t = y / SS
        row = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
        for x in range(SS):
            px[x, y] = row
    return img.convert("RGBA")


def corona(img, cx, cy, r, color=(255, 132, 36), layers=9, spread=2.35, peak=64):
    """Stacked soft rings then one heavy blur — one hard ellipse blurs into a box."""
    g = Image.new("RGBA", (SS, SS), (0, 0, 0, 0))
    gd = ImageDraw.Draw(g)
    for i in range(layers, 0, -1):
        t = i / layers
        rr = r * (1 + (spread - 1) * t)
        gd.ellipse([cx - rr, cy - rr, cx + rr, cy + rr],
                   fill=color + (int(peak * (1 - t) ** 1.6) + 4,))
    return Image.alpha_composite(img, g.filter(ImageFilter.GaussianBlur(SS * 0.085)))


def disc(img, cx, cy, r, core=(255, 252, 240), mid=(255, 166, 44), edge=(206, 52, 18)):
    d = ImageDraw.Draw(img)
    steps = 420
    for i in range(steps, 0, -1):
        t = i / steps                                  # 1 = limb, 0 = core
        rr = r * t
        if t > 0.5:
            k = (t - 0.5) / 0.5
            col = tuple(int(mid[j] + (edge[j] - mid[j]) * k) for j in range(3))
        else:
            k = t / 0.5
            col = tuple(int(core[j] + (mid[j] - core[j]) * k) for j in range(3))
        d.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], fill=col + (255,))
    return img


def render():
    img = background()
    img = corona(img, SS * .5, SS * .5, SS * .29)
    img = disc(img, SS * .5, SS * .5, SS * .29)
    return img.convert("RGB").resize((S, S), Image.LANCZOS)


if __name__ == "__main__":
    icon = render()
    for folder in TARGETS:
        folder.mkdir(parents=True, exist_ok=True)
        for size in MAC_SIZES:
            out = folder / f"icon_{size}.png"
            if size == S:
                icon.save(out)
            else:
                icon.resize((size, size), Image.LANCZOS).save(out)
            print("wrote", out.relative_to(APP))

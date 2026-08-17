#!/usr/bin/env python3
"""
Upscale an image with a converted Core ML upscaler, tile by tile.

    conda activate aisixteen-convert
    python scripts/test_upscaler.py models/out/<something>.png --model real-esrgan

This is both a check that the conversion works and the **reference implementation of the tiling**,
which is the part that has to be reproduced in Swift. The model itself takes one fixed 256 px tile;
everything about making that cover a wallpaper lives here.

Two details that are the whole difference between this looking right and looking obviously tiled:

* **Overlap.** ESRGAN's receptive field spans tens of pixels, so a tile has no idea what is just
  outside it. Butt tiles edge to edge and the seams read as a grid. Tiles overlap by 16 px of input
  (64 px of output at ×4).
* **Feathered blending.** Even overlapped, two tiles disagree slightly in the shared region. A
  linear cross-fade across the overlap hides that; a hard cut does not, and is more visible than
  the seam it replaced.
"""
import argparse
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
MODELS = HERE.parent / "models"

NAMES = {"ultrasharp": "UltraSharp4x", "real-esrgan": "RealESRGAN4x", "nomos8ksc": "Nomos8kSC4x"}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("image", type=Path)
    parser.add_argument("--model", choices=sorted(NAMES), default="real-esrgan")
    parser.add_argument("--tile", type=int, default=256)
    parser.add_argument("--overlap", type=int, default=16)
    parser.add_argument("--output", type=Path, default=None)
    args = parser.parse_args()

    import numpy as np
    import coremltools as ct
    from PIL import Image

    compiled = MODELS / "coreml" / f"{args.model}-{args.tile}tile-16bit" / f"{NAMES[args.model]}.mlmodelc"
    if not compiled.exists():
        print(f"no converted model at {compiled}", file=sys.stderr)
        return 1

    model = ct.models.CompiledMLModel(str(compiled))
    scale = 4
    tile, overlap = args.tile, args.overlap
    step = tile - overlap

    source = Image.open(args.image).convert("RGB")
    width, height = source.size
    out_w, out_h = width * scale, height * scale

    # Accumulate colour and weight separately, then divide. That is what turns overlapping tiles
    # into a cross-fade rather than a last-one-wins overwrite.
    canvas = np.zeros((out_h, out_w, 3), dtype=np.float32)
    weights = np.zeros((out_h, out_w, 1), dtype=np.float32)

    xs = list(range(0, max(width - overlap, 1), step))
    ys = list(range(0, max(height - overlap, 1), step))
    print(f"{width}×{height} → {out_w}×{out_h} in {len(xs) * len(ys)} tiles "
          f"({tile} px, {overlap} px overlap)", flush=True)

    ramp = feather(tile * scale, overlap * scale)

    for y in ys:
        for x in xs:
            # Clamp so the final row and column are full tiles rather than short ones — the model
            # has exactly one input shape and cannot take a partial tile.
            left, top = min(x, max(width - tile, 0)), min(y, max(height - tile, 0))
            patch = source.crop((left, top, left + tile, top + tile))
            if patch.size != (tile, tile):
                padded = Image.new("RGB", (tile, tile))
                padded.paste(patch, (0, 0))
                patch = padded

            result = model.predict({"image": patch})["upscaled"]
            produced = np.asarray(result.convert("RGB"), dtype=np.float32)

            oy, ox = top * scale, left * scale
            h, w = produced.shape[:2]
            canvas[oy:oy + h, ox:ox + w] += produced * ramp[:h, :w]
            weights[oy:oy + h, ox:ox + w] += ramp[:h, :w]

    blended = np.clip(canvas / np.maximum(weights, 1e-6), 0, 255).astype(np.uint8)
    output = args.output or args.image.with_name(
        f"{args.image.stem}.{args.model}-x{scale}.png")
    Image.fromarray(blended).save(output)
    print(f"wrote {output}  ({output.stat().st_size / 1e6:.1f} MB)")
    return 0


def feather(size: int, overlap: int):
    """A 2-D weight map: 1 in the middle, ramping to 0 across the overlap at each edge."""
    import numpy as np
    ramp = np.ones(size, dtype=np.float32)
    if overlap > 0:
        edge = np.linspace(0, 1, overlap, dtype=np.float32)
        ramp[:overlap] = edge
        ramp[-overlap:] = edge[::-1]
    return (ramp[:, None] * ramp[None, :])[:, :, None]


if __name__ == "__main__":
    sys.exit(main())

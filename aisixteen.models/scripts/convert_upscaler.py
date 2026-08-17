#!/usr/bin/env python3
"""
Convert an ESRGAN-family super-resolution model to Core ML.

    conda activate aisixteen-convert
    python scripts/convert_upscaler.py                       # 4x-UltraSharp, 256 px tile
    python scripts/convert_upscaler.py --model real-esrgan   # the shippable one

────────────────────────────────────────────────────────────────────────────────────────────────
⚠️  LICENCE — 4x-UltraSharp IS NOT SHIPPABLE

`4x-UltraSharp` is **CC-BY-NC-SA 4.0**, from Kim2091, its author. Non-commercial. It cannot go into
a paid app, and it is converted here **for development evaluation only** — a quality yardstick to
judge the shippable options against. It must be swapped before any release.

The dozen-odd Hugging Face mirrors that label the same file MIT, wtfpl or openrail are third parties
relicensing work they do not own, which has no legal effect. This script therefore pulls from the
author's own repository: correct provenance, and the licence stated honestly.

Shippable alternatives, both wired in below:
  * `real-esrgan` — BSD-3-Clause, the upstream xinntao weights.
  * `nomos8ksc`   — CC-BY-4.0, commercial use permitted with attribution.

────────────────────────────────────────────────────────────────────────────────────────────────
WHY A TILE, AND WHY 256

Core ML is fixed-shape, and an RRDBNet at full wallpaper resolution would be enormous — 23 residual
blocks evaluated over 1206 × 2622 pixels, at 4× internally. So the model is converted for one tile
and applied repeatedly in Swift over overlapping windows. 256 px in ⇒ 1024 px out keeps peak memory
to something a phone can hold while the rest of the pipeline is also resident.

The overlap matters and belongs to the caller: ESRGAN's receptive field means tiles seamed edge to
edge show a visible grid. Overlap by ~16 px and cross-fade the seams.

Input and output are both Core ML `ImageType`, so Swift hands over a `CVPixelBuffer` and gets one
back — no manual normalisation on either side, which is where this kind of integration usually goes
quietly wrong.
"""
import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
MODELS = HERE.parent / "models"

UPSCALERS = {
    "ultrasharp": {
        # The author's own repository, so the licence travels with the file.
        "repo": "Kim2091/UltraSharp",
        "file": "4x-UltraSharp.safetensors",
        "name": "UltraSharp4x",
        "licence": "CC-BY-NC-SA-4.0",
        "shippable": False,
        "note": "4x-UltraSharp by Kim2091. NON-COMMERCIAL — development evaluation only.",
    },
    "real-esrgan": {
        "repo": "schwgHao/RealESRGAN_x4plus",
        "file": "RealESRGAN_x4plus.pth",
        "name": "RealESRGAN4x",
        "licence": "BSD-3-Clause",
        "shippable": True,
        "note": "Real-ESRGAN x4plus (xinntao). BSD-3-Clause.",
    },
    "nomos8ksc": {
        "repo": "Phips/4xNomos8kSC",
        "file": "4xNomos8kSC.safetensors",
        "name": "Nomos8kSC4x",
        "licence": "CC-BY-4.0",
        "shippable": True,
        "note": "4xNomos8kSC by Philip Hofmann. CC-BY-4.0 — credit required in the app.",
    },
}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--model", choices=sorted(UPSCALERS), default="ultrasharp")
    parser.add_argument("--tile", type=int, default=256,
                        help="input tile size in pixels; output is 4× this")
    parser.add_argument("--nbits", type=int, default=16, choices=[8, 16])
    args = parser.parse_args()

    import numpy as np
    import torch
    import coremltools as ct
    from huggingface_hub import hf_hub_download
    from spandrel import ModelLoader

    spec = UPSCALERS[args.model]
    if not spec["shippable"]:
        print(f"\n⚠️  {spec['licence']} — {args.model} is NOT shippable. Development only.\n")

    weights = MODELS / "upscalers" / spec["file"]
    if not weights.exists():
        weights.parent.mkdir(parents=True, exist_ok=True)
        print(f"downloading {spec['repo']}/{spec['file']}…", flush=True)
        shutil.copy(hf_hub_download(spec["repo"], spec["file"]), weights)

    # spandrel identifies the architecture from the state dict, which is the only sane way to load
    # community ESRGAN weights: they are bare tensors with no config, and the block count and
    # feature width vary between models that otherwise look identical.
    descriptor = ModelLoader().load_from_file(str(weights))
    scale = descriptor.scale
    model = descriptor.model.eval()
    print(f"architecture: {descriptor.architecture.name} · scale ×{scale} · "
          f"{sum(p.numel() for p in model.parameters()) / 1e6:.1f}M params")

    class Scaled(torch.nn.Module):
        """Wraps the network so Core ML can speak in pixels at both ends.

        ESRGAN works in 0–1 floats; a Core ML `ImageType` is 0–255. Doing the two conversions inside
        the graph means Swift never touches normalisation — the single most common place an
        upscaler integration goes subtly wrong and produces washed-out or clipped output that still
        looks plausible.
        """
        def __init__(self, inner): super().__init__(); self.inner = inner
        def forward(self, x): return (self.inner(x).clamp(0, 1) * 255.0)

    wrapped = Scaled(model).eval()
    example = torch.zeros((1, 3, args.tile, args.tile), dtype=torch.float32)
    print("tracing…", flush=True)
    with torch.no_grad():
        traced = torch.jit.trace(wrapped, example, strict=False)

    output = MODELS / "coreml" / f"{args.model}-{args.tile}tile-{args.nbits}bit"
    output.mkdir(parents=True, exist_ok=True)

    print("converting…", flush=True)
    mlmodel = ct.convert(
        traced,
        convert_to="mlprogram",
        inputs=[ct.ImageType(name="image", shape=(1, 3, args.tile, args.tile),
                             scale=1.0 / 255.0, color_layout=ct.colorlayout.RGB)],
        outputs=[ct.ImageType(name="upscaled", color_layout=ct.colorlayout.RGB)],
        compute_precision=ct.precision.FLOAT16,
        minimum_deployment_target=ct.target.iOS17,
    )

    if args.nbits < 16:
        from coremltools.optimize.coreml import (
            OpPalettizerConfig, OptimizationConfig, palettize_weights)
        mlmodel = palettize_weights(
            mlmodel, OptimizationConfig(global_config=OpPalettizerConfig(mode="kmeans", nbits=args.nbits)))

    mlmodel.short_description = spec["note"]
    mlmodel.user_defined_metadata["licence"] = spec["licence"]
    mlmodel.user_defined_metadata["shippable"] = str(spec["shippable"])
    mlmodel.user_defined_metadata["source"] = f"{spec['repo']}/{spec['file']}"
    mlmodel.user_defined_metadata["scale"] = str(scale)
    mlmodel.user_defined_metadata["tile"] = str(args.tile)
    # Overlap is the caller's job, but the number belongs with the model: seam artefacts are a
    # property of this network's receptive field, not of the app.
    mlmodel.user_defined_metadata["recommended_overlap"] = "16"
    mlmodel.input_description["image"] = f"RGB tile, {args.tile}×{args.tile}"
    mlmodel.output_description["upscaled"] = f"RGB, {args.tile * scale}×{args.tile * scale}"

    package = output / f"{spec['name']}.mlpackage"
    if package.exists():
        shutil.rmtree(package)
    mlmodel.save(str(package))

    compiled = output / f"{spec['name']}.mlmodelc"
    if compiled.exists():
        shutil.rmtree(compiled)
    result = subprocess.run(["xcrun", "coremlcompiler", "compile", str(package), str(output)],
                            capture_output=True, text=True)
    if result.returncode != 0:
        print(result.stdout + result.stderr, file=sys.stderr)
        return result.returncode

    (output / "LICENCE.txt").write_text(
        f"{spec['note']}\nLicence: {spec['licence']}\nSource: {spec['repo']}/{spec['file']}\n"
        f"Shippable in a commercial app: {'yes' if spec['shippable'] else 'NO'}\n")

    size = sum(f.stat().st_size for f in compiled.rglob("*") if f.is_file())
    print(f"\n{spec['name']}.mlmodelc — {size / 1e6:.0f} MB  →  {output}")
    print(f"licence: {spec['licence']}  shippable: {spec['shippable']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

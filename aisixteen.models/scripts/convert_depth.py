#!/usr/bin/env python3
"""
Convert a monocular depth estimator to Core ML, for ControlNet depth conditioning.

    conda activate aisixteen-convert
    python scripts/convert_depth.py                     # Depth Anything V2 Small, 518 px, 16-bit
    python scripts/convert_depth.py --model midas-small

Output: `models/coreml/<name>-<edge>px-<nbits>bit/`, matching the upscaler convention — a
`.mlmodelc` beside a `LICENCE.txt`, with the licence also stamped into the model's own metadata so
it survives being copied out of the folder.

────────────────────────────────────────────────────────────────────────────────────────────────
WHO NEEDS THIS

The Architecture app conditions a redesign on the *shape* of a room. On a LiDAR device that shape
comes from `ARFrame.sceneDepth` for free. On everything else it has to be estimated, and that is
what this converts.

Wallpapers and Studio do not need it — they condition on the tile itself.

────────────────────────────────────────────────────────────────────────────────────────────────
NEAR = BRIGHT, AND THE TWO CONVENTIONS THAT DISAGREE

ControlNet's depth models were trained on maps where **near is bright**. Two things routinely get
this backwards, and neither errors:

* **MiDaS-family models, including Depth Anything, output _inverse depth_ (disparity)** — large
  values are *near*. That already matches ControlNet, so it passes through unchanged.
* **LiDAR outputs metres** — large values are *far*. That must be inverted.

Get it wrong and you produce a plausible, well-formed picture of a room turned inside out, with
nothing anywhere reporting a problem. The conversion below emits disparity and says so in the
model's output description; inverting for the LiDAR path is the app's job, and it should be pinned
by a test that asserts hand-computed pixel values rather than eyeballed.

Two edge cases worth the same treatment: a **hole** (no return) must read as *far*, never as a
phantom object in front of the camera; and a **constant-depth frame** must not divide by zero when
normalised.
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path

import licences

HERE = Path(__file__).resolve().parent
MODELS = HERE.parent / "models"

ESTIMATORS = {
    "depth-anything-v2-small": {
        "repo": "depth-anything/Depth-Anything-V2-Small-hf",
        "name": "DepthAnythingV2Small",
        "edge": 518,          # the size it was trained at; multiples of 14 (ViT-S/14 patches)
        "licence": "apache-2.0",
        "shippable": True,
        "note": "Depth Anything V2 Small. Apache-2.0. Outputs INVERSE depth (near = large).",
    },
    "midas-small": {
        "repo": "Intel/dpt-swinv2-tiny-256",
        "name": "MidasSwinV2Tiny",
        "edge": 256,
        "licence": "MIT",
        "shippable": True,
        "note": "Intel DPT SwinV2 Tiny. MIT. Outputs INVERSE depth (near = large).",
    },
}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--model", choices=sorted(ESTIMATORS), default="depth-anything-v2-small")
    parser.add_argument("--edge", type=int, default=None,
                        help="input side in pixels; defaults to what the model was trained at")
    parser.add_argument("--nbits", type=int, default=16, choices=[6, 8, 16],
                        help="16 is the default: this is a 25 M-parameter model, so palettising it "
                             "saves tens of megabytes against a 1.2 GB pack and costs accuracy in "
                             "the one signal the whole redesign is anchored to")
    args = parser.parse_args()

    spec = ESTIMATORS[args.model]
    edge = args.edge or spec["edge"]

    print(f"{spec['name']} — {spec['note']}\n")
    if not spec["shippable"]:
        print(f"⚠️  {spec['licence']} — NOT shippable. Development only.\n", file=sys.stderr)

    import numpy as np
    import torch
    import coremltools as ct
    from transformers import AutoModelForDepthEstimation

    model = AutoModelForDepthEstimation.from_pretrained(spec["repo"]).eval()

    class Depth(torch.nn.Module):
        """Wraps the estimator so Core ML sees an image in and one plane out.

        The `transformers` head returns a struct and expects normalised input; both are folded in
        here so the Swift side hands over a `CVPixelBuffer` and gets one back, with no preprocessing
        to reimplement and get subtly wrong.
        """

        def __init__(self, inner):
            super().__init__()
            self.inner = inner
            # ImageNet statistics, the normalisation these models were trained with. Baked into the
            # graph rather than left to the caller: a mismatch here does not fail, it just quietly
            # degrades the map, which is the hardest kind of bug to see in a depth image.
            self.register_buffer("mean", torch.tensor([0.485, 0.456, 0.406]).view(1, 3, 1, 1))
            self.register_buffer("std", torch.tensor([0.229, 0.224, 0.225]).view(1, 3, 1, 1))

        def forward(self, image):
            x = (image / 255.0 - self.mean) / self.std
            depth = self.inner(pixel_values=x).predicted_depth
            if depth.dim() == 3:
                depth = depth.unsqueeze(1)
            # Per-frame min–max to 0–255, near = bright. The epsilon is not decoration: a frame of
            # constant depth — a blank wall filling the view — has zero range, and without it the
            # normalisation divides by zero and the map comes out as NaN.
            lo = depth.amin(dim=(2, 3), keepdim=True)
            hi = depth.amax(dim=(2, 3), keepdim=True)
            return (depth - lo) / (hi - lo + 1e-6) * 255.0

    wrapped = Depth(model).eval()
    example = torch.rand(1, 3, edge, edge) * 255.0
    traced = torch.jit.trace(wrapped, example, strict=False)

    print(f"converting at {edge}×{edge}…")
    mlmodel = ct.convert(
        traced,
        inputs=[ct.ImageType(name="image", shape=(1, 3, edge, edge),
                             color_layout=ct.colorlayout.RGB, scale=1.0)],
        outputs=[ct.TensorType(name="depth")],
        convert_to="mlprogram",
        # Same reasoning as the diffusion pack: anything older predates ANE support for the
        # compressed weight formats, and a model that fails ANE compilation falls back to CPU
        # silently. Measured elsewhere in this repo at 150× slower.
        minimum_deployment_target=ct.target.iOS18,
        compute_units=ct.ComputeUnit.ALL,
    )

    if args.nbits != 16:
        from coremltools.optimize.coreml import (OpPalettizerConfig, OptimizationConfig,
                                                 palettize_weights)
        mlmodel = palettize_weights(mlmodel, OptimizationConfig(
            global_config=OpPalettizerConfig(mode="kmeans", nbits=args.nbits)))

    licence = licences.KNOWN.get(args.model) or licences.Licence(
        source=f"HuggingFace {spec['repo']}", name=f"{spec['name']} ({spec['licence']})",
        allow_derivatives=True, allow_different_licence=True,
        commercial=["Image", "Rent", "RentCivit", "Sell"], allow_no_credit=True,
        url=f"https://huggingface.co/{spec['repo']}")

    mlmodel.short_description = spec["note"]
    mlmodel.input_description["image"] = f"RGB, {edge}×{edge}"
    # Stated in the artefact itself, because the polarity is the one thing a caller can get
    # backwards while everything still looks like it worked.
    mlmodel.output_description["depth"] = (
        f"Inverse depth, 0–255, NEAR = BRIGHT, {edge}×{edge}. "
        "Pass straight to ControlNet depth. LiDAR metres must be inverted first.")
    mlmodel.user_defined_metadata["licence"] = spec["licence"]
    mlmodel.user_defined_metadata["shippable"] = str(spec["shippable"])
    mlmodel.user_defined_metadata["polarity"] = "near-is-bright"
    mlmodel.user_defined_metadata["source"] = spec["repo"]

    output = MODELS / "coreml" / f"{args.model}-{edge}px-{args.nbits}bit"
    output.mkdir(parents=True, exist_ok=True)
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
        print(result.stderr, file=sys.stderr)
        return 1
    shutil.rmtree(package)

    licences.write_licence_file(output, [licence])
    size = sum(f.stat().st_size for f in compiled.rglob("*") if f.is_file())
    print(f"\n{spec['name']}.mlmodelc — {size / 1e6:.0f} MB  →  {output}")
    print("  polarity: near = bright (inverse depth), ready for ControlNet depth")
    return 0


if __name__ == "__main__":
    sys.exit(main())

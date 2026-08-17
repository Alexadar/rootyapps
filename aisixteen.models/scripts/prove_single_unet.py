#!/usr/bin/env python3
"""
Prove that `ControlledUnet` with zero residuals is numerically identical to the plain `Unet`.

    conda activate aisixteen-convert
    python scripts/prove_single_unet.py

If this passes, one unet can serve both stage 1 (text-to-image, zero conditioning) and stage 3
(tile refine, real conditioning) — 618 MB off the download and one fewer model resident.

The claim is that a ControlNet's contribution is *added* to the unet's skip connections, so feeding
zeros adds nothing and the network reduces exactly to the plain one. That is a claim about the
converted graph, not about the maths on paper, and Core ML conversion is where such claims stop
being true. So it is checked against the actual `.mlmodelc` files, on identical inputs, before
anything is built on top of it.
"""
import sys
from pathlib import Path

MODELS = Path(__file__).resolve().parent.parent / "models"
BUNDLE = MODELS / "coreml" / "sd15-split-einsum-v2-512x512-6bit-lora-epi_noiseoffset_v2.safetensors" / "Resources"


def describe(model, title):
    print(f"\n{title}")
    for name, desc in model.get_spec().description.input.items() if False else []:
        pass
    spec = model.get_spec()
    for i in spec.description.input:
        shape = list(i.type.multiArrayType.shape)
        print(f"   in  {i.name:<34} {shape}")
    for o in spec.description.output:
        print(f"   out {o.name:<34} {list(o.type.multiArrayType.shape)}")


def main() -> int:
    import numpy as np
    import coremltools as ct

    plain_url = BUNDLE / "Unet.mlmodelc"
    controlled_url = BUNDLE / "ControlledUnet.mlmodelc"
    for url in (plain_url, controlled_url):
        if not url.exists():
            print(f"missing {url}", file=sys.stderr)
            return 1

    plain = ct.models.CompiledMLModel(str(plain_url))
    controlled = ct.models.CompiledMLModel(str(controlled_url))

    # Compiled models expose no spec, so shapes come from the uncompiled packages beside them.
    packages = sorted((BUNDLE.parent).glob("*unet.mlpackage"))
    shapes = {}
    for package in packages:
        spec = ct.models.MLModel(str(package), skip_model_load=True).get_spec()
        for i in spec.description.input:
            shapes[i.name] = [int(d) for d in i.type.multiArrayType.shape]
    if not shapes:
        print("could not read input shapes from the .mlpackage files", file=sys.stderr)
        return 1

    print("inputs found:")
    for name, shape in sorted(shapes.items()):
        print(f"   {name:<38} {shape}")

    rng = np.random.default_rng(7)
    common = {}
    for name in ("sample", "timestep", "encoder_hidden_states"):
        if name not in shapes:
            print(f"missing expected input {name}", file=sys.stderr)
            return 1
        common[name] = rng.standard_normal(shapes[name]).astype(np.float32)
    # A real timestep, not noise — the embedding is nonlinear in it.
    common["timestep"] = np.full(shapes["timestep"], 500.0, dtype=np.float32)

    residual_names = [n for n in shapes if n.startswith("additional_residual")]
    print(f"\nresidual inputs on the controlled unet: {len(residual_names)}")

    zeros = {n: np.zeros(shapes[n], dtype=np.float32) for n in residual_names}

    plain_out = plain.predict(dict(common))
    controlled_out = controlled.predict({**common, **zeros})

    key_p = list(plain_out)[0]
    key_c = list(controlled_out)[0]
    a = np.asarray(plain_out[key_p], dtype=np.float64)
    b = np.asarray(controlled_out[key_c], dtype=np.float64)

    if a.shape != b.shape:
        print(f"\nSHAPE MISMATCH {a.shape} vs {b.shape}", file=sys.stderr)
        return 1

    diff = np.abs(a - b)
    scale = max(np.abs(a).max(), 1e-6)
    print(f"\nplain   output {a.shape}  range [{a.min():.4f}, {a.max():.4f}]")
    print(f"zeroed  output {b.shape}  range [{b.min():.4f}, {b.max():.4f}]")
    print(f"max abs diff   {diff.max():.6f}")
    print(f"relative       {diff.max() / scale:.6%}")

    # fp16 arithmetic on values of this magnitude agrees to ~1e-3. Anything larger means the two
    # graphs are not computing the same function, and the single-unet plan is dead.
    ok = diff.max() / scale < 5e-3
    print("\n" + ("PROVEN — zero residuals reduce the controlled unet to the plain one."
                  if ok else
                  "NOT EQUIVALENT — the controlled unet cannot stand in for the plain one."))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())

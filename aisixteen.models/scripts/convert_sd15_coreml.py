#!/usr/bin/env python3
"""
Convert the Stable Diffusion 1.5 `save_pretrained` tree to Core ML, bundled for the Swift runtime.

Run inside the `aisixteen-convert` env (see setup_convert_env.sh) — NOT `fantastic`.

    conda activate aisixteen-convert
    python scripts/convert_sd15_coreml.py

Output: models/coreml/sd15-<attention>-<size>-<nbits>bit/Resources/, which is the directory the
Swift `StableDiffusion` package's `StableDiffusionPipeline(resourcesAt:)` takes, and the directory
that becomes the Background Assets asset pack.

────────────────────────────────────────────────────────────────────────────────────────────────
THE THREE DECISIONS IN HERE, AND WHY

**Attention: SPLIT_EINSUM_V2, not ORIGINAL.** ORIGINAL is meaningfully faster on a Mac GPU;
SPLIT_EINSUM_V2 is what lets the unet run on the Neural Engine, which is the difference between
"usable" and "not" on a phone. This is a universal app whose constrained device is an iPhone, and
shipping both would double a 600 MB download to serve the platform that is already fast. If Mac
generation turns out to be the complaint, the answer is a second asset pack, not a different
default.

**6-bit palettisation.** The fp16 unet is 1.6 GB; at 6 bits it is around a quarter of that, and the
quality difference on this model is small — Apple ships 6-bit as the recommended setting for
on-device SD. Download size is not a detail here: it is the first-run gate, the thing standing
between a new user and their first wallpaper, and 2.6 GB versus 800 MB changes how many of them
ever get there.

**512 × 512, and this is the open question.** Core ML models are FIXED SHAPE — a converted unet
generates exactly one resolution, and each additional shape is another whole unet in the download.
SD 1.5 is also trained at 512 and produces duplicated limbs and repeated horizons much above it.
So a 1206 × 2622 phone wallpaper cannot come straight out of this model at any setting. The real
pipeline is generate-then-upscale, and the aspect question becomes: one square model plus an
upscaler, or one model per aspect at ~600 MB each. This script converts 512 × 512 first because it
is the model's native shape and it proves the toolchain; `--latent-h/--latent-w` are exposed so the
per-aspect variants can be built once that decision is made.

The safety checker is deliberately not converted — a second CLIP model whose output nothing reads,
for about 1.2 GB.

────────────────────────────────────────────────────────────────────────────────────────────────
LORA AND CONTROLNET — BOTH ARE DECIDED HERE, NOT AT RUNTIME

Core ML models are frozen compute graphs. Neither of these can be bolted on later to a model that
was converted without them, so getting this wrong means reconverting and re-shipping the pack.

**LoRA is fused before tracing.** There is no runtime LoRA in Core ML: no adapter to load, no
weights to swap, no scale to turn down. A LoRA becomes part of the model by being merged into the
PyTorch weights with `fuse_lora()` and then converted — which means one converted model per LoRA (or
per LoRA blend), each a separate asset pack. `--lora` takes any number of `repo_or_path[:scale]`
and fuses them in order before a single weight is traced.

**ControlNet requires `--unet-support-controlnet` on the unet.** That flag converts a unet with
extra inputs for the down/mid block residuals a ControlNet produces. A unet converted without it
physically has nowhere to put them. Note the converter names that model `control-unet` /
`ControlledUnet` — it is a *different file* from the plain `unet`, and the Swift runtime picks by
name, so shipping both modes means shipping both unets. Because the flag is only a compatibility
decision and costs nothing until a ControlNet is actually converted, it defaults **on** here:
converting without it is the choice that forecloses something.

`--controlnet` converts the ControlNet models themselves, which are separate ~700 MB (fp16)
downloads and belong in their own asset packs, fetched only if the user uses that feature.

**The VAE encoder follows from ControlNet.** It is not needed for text-to-image, but it is needed
for image-to-image and for any ControlNet flow that conditions on a user-supplied picture, so it is
converted whenever ControlNet support is on. It is small (~50 MB) next to what it enables.
────────────────────────────────────────────────────────────────────────────────────────────────
"""
import argparse
import json
import shutil
import sys
import types
from pathlib import Path

HERE = Path(__file__).resolve().parent
MODELS = HERE.parent / "models"
DEFAULT_SOURCE = MODELS / "stable-diffusion-v1-5"


def allow_local_base_model(torch2coreml) -> None:
    """Let a ControlNet be converted against a locally fused SD 1.5.

    The converter refuses unless `--model-version` string-matches the `base_model` field on the
    ControlNet's Hugging Face model card — for the tile model, `runwayml/stable-diffusion-v1-5`.
    Ours is a local directory of LoRA-fused weights, so the strings can never match and the
    conversion aborts with "Please, use --model-version runwayml/stable-diffusion-v1-5".

    That check is about **provenance, not compatibility**. Fusing a LoRA changes weight values; it
    changes no layer, no shape and no channel count, so the ControlNet's residuals slot into this
    unet exactly as they do into stock SD 1.5. Returning `None` downgrades the guard to the warning
    it already emits for unrecognised base models, which is the correct severity here.

    Narrow on purpose: it only relaxes for base models that ARE SD 1.5. A ControlNet trained against
    SD 2.1 or SDXL still raises, because that one would genuinely not fit.
    """
    known_sd15 = {"runwayml/stable-diffusion-v1-5",
                  "stable-diffusion-v1-5/stable-diffusion-v1-5",
                  "sd-legacy/stable-diffusion-v1-5"}
    original = torch2coreml._get_controlnet_base_model

    def relaxed(controlnet_model_version):
        base = original(controlnet_model_version)
        if base in known_sd15:
            print(f"  note: {controlnet_model_version} declares base {base}; converting against the "
                  f"local fused SD 1.5 (same architecture).")
            return None
        return base

    torch2coreml._get_controlnet_base_model = relaxed


def stub_diffusionkit() -> None:
    """Satisfy an import the SD 1.5 path never uses.

    `torch2coreml` imports `diffusionkit.tests.torch2coreml` at module scope, but the two names it
    takes from it — `convert_mmdit_to_mlpackage` and `convert_vae_to_mlpackage` — are only reached
    by `convert_mmdit`, which is the Stable Diffusion 3 / MMDiT path. Converting a unet model never
    calls either.

    The alternative is installing `diffusionkit==0.4.0`, which drags in an mlx stack and its own
    pinned diffusers, straight into an env that exists precisely because those pins are delicate.
    Stubbing it in `sys.modules` keeps the workaround here, in our script, where it is visible —
    rather than as a fake package sitting in site-packages that a future reader would have to
    excavate. The stubs raise if they are ever actually called, so this can never silently produce
    a wrong model.
    """
    if "diffusionkit" in sys.modules:
        return

    def unavailable(*_args, **_kwargs):
        raise RuntimeError(
            "diffusionkit is stubbed: this script converts SD 1.5 (unet), not SD 3 (MMDiT). "
            "Converting an MMDiT model needs the real package installed.")

    root = types.ModuleType("diffusionkit")
    tests = types.ModuleType("diffusionkit.tests")
    inner = types.ModuleType("diffusionkit.tests.torch2coreml")
    version = types.ModuleType("diffusionkit.version")

    inner.convert_mmdit_to_mlpackage = unavailable
    inner.convert_vae_to_mlpackage = unavailable
    version.__version__ = "stubbed"
    tests.torch2coreml = inner
    root.tests = tests
    root.version = version

    sys.modules.update({
        "diffusionkit": root,
        "diffusionkit.tests": tests,
        "diffusionkit.tests.torch2coreml": inner,
        "diffusionkit.version": version,
    })


def fuse_loras(source: Path, specs: list[str], scratch: Path) -> Path:
    """Merge LoRAs into the base weights and write a new `save_pretrained` tree to convert from.

    Core ML has no runtime LoRA. There is no adapter to load on device, no scale to change, and no
    way to turn one off — the only place a LoRA can be applied is here, into the PyTorch weights,
    before anything is traced. That is why a LoRA is not a feature of the app but a property of the
    model it downloaded, and why each LoRA (or blend) is a separate converted artefact.

    `fuse_lora` is used rather than leaving the adapters attached, because the tracer follows the
    module graph and would otherwise either miss the adapter branches entirely or bake in a
    scale of 1.0 regardless of what was asked for.
    """
    import torch
    from diffusers import StableDiffusionPipeline

    if (scratch / "model_index.json").exists():
        print(f"reusing fused weights at {scratch}")
        return scratch

    print(f"fusing {len(specs)} LoRA(s) into {source.name}…", flush=True)
    pipe = StableDiffusionPipeline.from_pretrained(
        source, torch_dtype=torch.float16, safety_checker=None, requires_safety_checker=False)

    for spec in specs:
        # "repo/name" or "repo/name:0.8" or "/local/path/file.safetensors:0.6"
        target, _, raw_scale = spec.rpartition(":")
        if not target or "/" in raw_scale or raw_scale == "":
            target, scale = spec, 1.0
        else:
            scale = float(raw_scale)

        print(f"  + {target} @ {scale}", flush=True)
        candidate = Path(target)
        if candidate.is_file():
            # A single-file LoRA has to be given as directory + filename. Handing the full path
            # makes diffusers treat it as a repo id and try to reach the network for it.
            pipe.load_lora_weights(str(candidate.parent), weight_name=candidate.name)
        else:
            pipe.load_lora_weights(target)

        pipe.fuse_lora(lora_scale=scale)
        # Detach before the next one, or the second fuse re-applies the first.
        pipe.unload_lora_weights()

    scratch.mkdir(parents=True, exist_ok=True)
    pipe.save_pretrained(scratch, safe_serialization=True)
    fused_tokenizer = scratch / "tokenizer"
    for name in ("vocab.json", "merges.txt", "special_tokens_map.json"):
        origin = source / "tokenizer" / name
        if origin.exists() and not (fused_tokenizer / name).exists():
            fused_tokenizer.mkdir(parents=True, exist_ok=True)
            (fused_tokenizer / name).write_bytes(origin.read_bytes())
    print(f"fused weights → {scratch}")
    return scratch


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--source", type=Path, default=DEFAULT_SOURCE,
                        help="the save_pretrained tree from fetch_sd15.py")
    parser.add_argument("--attention", default="SPLIT_EINSUM_V2",
                        choices=["SPLIT_EINSUM_V2", "SPLIT_EINSUM", "ORIGINAL"])
    parser.add_argument("--nbits", type=int, default=6, choices=[1, 2, 4, 6, 8, 16],
                        help="palettisation width; 16 means no quantisation")
    parser.add_argument("--height", type=int, default=512)
    parser.add_argument("--width", type=int, default=512)
    parser.add_argument("--output", type=Path, default=None)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument(
        "--deployment-target", default="iOS18",
        help="Core ML minimum deployment target. The converter defaults to macOS13, which predates "
             "ANE support for palettised weights — and a 6-bit model converted against it fails ANE "
             "compilation at runtime with `ANECCompile() FAILED`, silently falling back to CPU. "
             "That fallback is what made a 512x512 unet take 791 s and 6.16 GB.")
    parser.add_argument(
        "--lora", action="append", default=[], metavar="REPO_OR_PATH[:SCALE]",
        help="Fuse a LoRA into the weights before conversion. Repeatable; fused in order. "
             "Core ML has no runtime LoRA, so each combination is its own converted model.")
    parser.add_argument(
        "--no-controlnet-support", dest="controlnet_support", action="store_false",
        help="Convert a plain unet with no ControlNet inputs. Smaller, and permanently unable to "
             "accept ControlNet conditioning without a reconvert.")
    parser.add_argument(
        "--controlnet", action="append", default=[], metavar="REPO_OR_PATH",
        help="Also convert these ControlNet models. Each is a separate ~700 MB artefact and "
             "belongs in its own asset pack.")
    parser.add_argument(
        "--model-id", default=None,
        help="What the app will know this pack as, written into model.json. Defaults to the source "
             "tree's folder name plus `cn` when a ControlNet is included. It must differ between "
             "checkpoints: the id is what a paused job compares against, so two different models "
             "sharing one id means half-finished work from one is resumed into the other.")
    parser.set_defaults(controlnet_support=True)
    args = parser.parse_args()

    if not (args.source / "model_index.json").exists():
        print(f"no model at {args.source} — run scripts/fetch_sd15.py first", file=sys.stderr)
        return 1

    if args.height % 64 or args.width % 64:
        # The VAE downsamples by 8 and the unet by a further 8 across its down blocks.
        print("height and width must both be multiples of 64", file=sys.stderr)
        return 1

    # The LoRA set is part of the model's identity — two packs converted from the same checkpoint
    # with different LoRAs are different models — so it goes in the directory name.
    source = args.source
    suffix = ""
    if args.lora:
        suffix = "-lora-" + "-".join(
            Path(spec.split(":")[0]).name.replace("/", "_") for spec in args.lora)
    if args.controlnet_support:
        suffix += "-cn"

    output = args.output or (
        MODELS / "coreml" /
        f"sd15-{args.attention.lower().replace('_', '-')}"
        f"-{args.width}x{args.height}-{args.nbits}bit{suffix}"
    )
    output.mkdir(parents=True, exist_ok=True)

    if args.lora:
        source = fuse_loras(args.source, args.lora, output.parent / (output.name + "-fused-torch"))

    argv = [
        "--model-version", str(source),
        "--convert-unet",
        "--convert-text-encoder",
        "--convert-vae-decoder",
        # Not --convert-safety-checker.
        "--attention-implementation", args.attention,
        "--latent-h", str(args.height // 8),
        "--latent-w", str(args.width // 8),
        # Produces Resources/ with compiled .mlmodelc plus vocab.json and merges.txt — exactly what
        # the Swift StableDiffusion package loads. Without it the output is .mlpackage files that
        # still need compiling and a tokenizer that has no vocabulary.
        "--bundle-resources-for-swift-cli",
        "--compute-unit", "ALL",
        "--min-deployment-target", args.deployment_target,
        "-o", str(output),
    ]
    if args.nbits != 16:
        argv += ["--quantize-nbits", str(args.nbits)]
    if args.controlnet_support:
        # Converts a unet that accepts ControlNet's down/mid block residuals. The result is written
        # as `control-unet` / `ControlledUnet`, NOT `unet` — a distinct file the Swift runtime
        # selects by name. Without this flag the graph has no inputs for those residuals and no
        # ControlNet can ever be attached.
        argv += ["--unet-support-controlnet"]
        # ControlNet flows that condition on a supplied image need to encode it into latent space.
        argv += ["--convert-vae-encoder"]
    if args.controlnet:
        # ONE flag, all the names after it. `--convert-controlnet` is `nargs="*"`, so repeating the
        # flag does not append — argparse keeps the last occurrence and silently drops the rest. A
        # three-net run converted exactly one net and reported success.
        argv += ["--convert-controlnet"] + args.controlnet

    print("torch2coreml " + " ".join(argv) + "\n", flush=True)
    if args.dry_run:
        return 0

    # Run in-process rather than through `-m`, so the diffusionkit stub above is already installed
    # when the converter's module-scope imports execute.
    stub_diffusionkit()
    from python_coreml_stable_diffusion import torch2coreml
    allow_local_base_model(torch2coreml)

    parsed = torch2coreml.parser_spec().parse_args(argv)
    torch2coreml.main(parsed)

    resources = output / "Resources"
    if resources.exists():
        write_declaration(resources, args.model_id or default_model_id(args))
        # The terms travel WITH the weights, and they cover **everything fused or bundled in** —
        # not just the checkpoint.
        #
        # An earlier version copied the source tree's LICENCE.txt verbatim, which documented the
        # checkpoint alone. Anyone reading it would conclude that the checkpoint's attribution was
        # the whole duty and ship without the ControlNets' OpenRAIL pass-through. Every input's
        # terms bind the output, and the fused weights carry no record of where they came from, so
        # the record has to be assembled here.
        write_pack_licence(resources, args)
        total = sum(f.stat().st_size for f in resources.rglob("*") if f.is_file())
        print(f"\nSwift resources: {resources}  ({total / 1e6:.0f} MB)")
        for entry in sorted(resources.iterdir()):
            size = sum(f.stat().st_size for f in entry.rglob("*") if f.is_file()) \
                if entry.is_dir() else entry.stat().st_size
            print(f"  {size / 1e6:8.1f} MB  {entry.name}")
    else:
        print("\n!! no Resources/ directory was produced — the Swift runtime needs it")
        return 1
    return 0


def write_pack_licence(resources: Path, args) -> None:
    """Collect the terms of the checkpoint, every fused LoRA and every bundled ControlNet."""
    import licences

    collected = []

    source_licence = args.source / "LICENCE.txt"
    if source_licence.exists():
        # The checkpoint's own record, written by import_single_file.py from the CivitAI API.
        collected.append(("Checkpoint — see below", source_licence.read_text()))
    else:
        print("  !! no LICENCE.txt in the source tree — the checkpoint records no terms",
              file=sys.stderr)

    for spec in args.lora:
        path = spec.split(":")[0]
        beside = Path(path).parent / "LICENCE.txt"
        if beside.exists():
            collected.append((f"LoRA fused at {spec.split(':')[-1]} — {Path(path).name}",
                              beside.read_text()))
        else:
            print(f"  !! no LICENCE.txt beside {path} — a fused LoRA's terms bind this artefact",
                  file=sys.stderr)

    if args.controlnet:
        collected.append(("ControlNet 1.1 — " + ", ".join(args.controlnet),
                          licences.KNOWN["controlnet"].text()))

    body = ["Everything in this pack, and the terms of each.",
            "",
            "Each of these binds the artefact as a whole. A permissively licensed checkpoint with a",
            "non-commercial LoRA fused into it is a non-commercial artefact, and the fused weights",
            "carry no record of where they came from — which is why this file exists.",
            "",
            "=" * 96, ""]
    for title, text in collected:
        body += [title, "-" * len(title), "", text.rstrip(), "", "=" * 96, ""]

    (resources / "LICENCE.txt").write_text("\n".join(body))
    print(f"  wrote Resources/LICENCE.txt covering {len(collected)} component(s)")


def write_declaration(resources: Path, model_id: str) -> None:
    """Write `model.json` so the app knows which model this is, rather than guessing.

    The app can never know what a future asset pack contains — the pack is produced here, by this
    script, and shipped separately. So the pack says what it is, and the app matches the id against
    the models that build knows how to run. An unrecognised id is a pack from a newer app, which the
    app then declines to use instead of running it as if it were something else.

    The id must stay stable across reconversions of the same model: a job on someone's device
    records it, and a resume compares it. Renaming it strands their unfinished work.
    """
    controlnet = resources / "controlnet"
    has_controlnet = controlnet.is_dir() and any(controlnet.glob("*.mlmodelc"))
    declaration = {
        "id": model_id,
        "family": "sd15",
        "nativeSide": 512,
        "hasControlNet": has_controlnet,
    }
    (resources / "model.json").write_text(json.dumps(declaration, indent=2) + "\n")
    print(f"  declared as {declaration['id']}")


def default_model_id(args) -> str:
    """A stable id derived from what was actually converted.

    The base model keeps the id it already shipped with — renaming it would strand every paused job
    on every installed device, because the id is exactly what `canBeResumed` compares. Anything else
    is named after its source tree.
    """
    stem = args.source.name.lower()
    if stem.startswith("stable-diffusion-v1-5"):
        # Spelled out, not derived. `sd15cn` is already installed on devices and written into
        # paused jobs; a tidier scheme would strand all of it.
        return "sd15cn" if args.controlnet else "sd15"
    base = stem.replace("_", "-")
    return f"{base}-cn" if args.controlnet else base


if __name__ == "__main__":
    sys.exit(main())

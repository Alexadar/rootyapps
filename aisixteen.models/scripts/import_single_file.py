#!/usr/bin/env python3
"""
Turn a single-file SD 1.5 checkpoint into the `save_pretrained` tree the converter expects.

Run inside the `aisixteen-convert` env (see setup_convert_env.sh):

    conda activate aisixteen-convert
    python scripts/import_single_file.py ~/Downloads/artUniverse_v80.safetensors \\
        --name art-universe-v80

Community checkpoints — CivitAI and the like — ship as one `.safetensors` holding the unet, the text
encoder and the VAE in the original Stable Diffusion layout. `convert_sd15_coreml.py` needs a
diffusers tree with a `model_index.json`, which is what this produces. After it, the checkpoint is
indistinguishable from the base model as far as the rest of the pipeline is concerned: same
converter, same LoRA fusing, same ControlNet, same 512 native size.

────────────────────────────────────────────────────────────────────────────────────────────────
LICENSING IS CHECKED, NOT ASSUMED

Pass `--civitai-model <id>` and this refuses to import weights that cannot be redistributed, writes
a `LICENCE.txt` beside the tree, and carries it through the Core ML conversion. See `licences.py`.

The warning used to live in this docstring with nothing enforcing it, which is exactly how a
2 GB checkpoint got converted, embedded in an app and installed on a phone before anyone read the
terms. A comment is not a gate.

`--allow-unshippable` converts anyway, for evaluating a checkpoint locally — that is just running
it, and it is a legitimate thing to want. The artefact is then stamped so it cannot be mistaken for
one that may ship.

────────────────────────────────────────────────────────────────────────────────────────────────
CLIP SKIP

Nothing to configure. "CLIP skip 1" means *no* layers skipped — the final hidden state, which is
what Apple's converter and the Swift runtime already use. Only a checkpoint trained for CLIP skip 2
(most anime merges) would need the text encoder truncated by a layer, and that is a change to the
converted `TextEncoder`, not a runtime setting.
"""

from __future__ import annotations

import argparse
import shutil
import sys
from pathlib import Path

import licences

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_CONFIG_SOURCE = ROOT / "models" / "stable-diffusion-v1-5"


def backfill_legacy_tokenizer_files(tree: Path, donor: Path) -> None:
    """Copy `vocab.json` and `merges.txt` in beside the tokenizer.

    `save_pretrained` on transformers 5.x writes only `tokenizer.json`, and two things downstream
    need the legacy pair: Apple's converter, whose slow `CLIPTokenizer` reads them, and the Swift
    runtime, which has no fast-tokenizer reader at all. Without them the conversion fails late and
    the app tokenises nothing.
    """
    target = tree / "tokenizer"
    source = donor / "tokenizer"
    if not source.is_dir():
        return
    for name in ("vocab.json", "merges.txt", "special_tokens_map.json"):
        if not (target / name).exists() and (source / name).exists():
            shutil.copy2(source / name, target / name)
            print(f"  backfilled tokenizer/{name}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("checkpoint", type=Path, help="the .safetensors file")
    parser.add_argument("--name", default=None,
                        help="folder name under models/ (default: the file's stem, lowercased)")
    parser.add_argument("--config-source", type=Path, default=DEFAULT_CONFIG_SOURCE,
                        help="a local SD 1.5 tree to take the pipeline config from, so this does "
                             "not reach for a HuggingFace repo that may have moved or been gated")
    parser.add_argument("--delete-checkpoint", action="store_true",
                        help="remove the .safetensors once the tree is written")
    parser.add_argument("--civitai-model", type=int, default=None, metavar="ID",
                        help="the CivitAI model id these weights came from. Its terms are checked "
                             "before anything is converted and recorded in LICENCE.txt.")
    parser.add_argument("--allow-unshippable", action="store_true",
                        help="import weights that may not be redistributed, for LOCAL EVALUATION "
                             "only. The artefact is stamped accordingly.")
    args = parser.parse_args()

    if not args.checkpoint.is_file():
        print(f"no checkpoint at {args.checkpoint}", file=sys.stderr)
        return 1

    # Before the two-gigabyte read, not after it.
    licence = None
    if args.civitai_model is not None:
        licence = licences.from_civitai(args.civitai_model)
        licences.gate(licence, allow_unshippable=args.allow_unshippable)
    else:
        print("!! no --civitai-model given, so these weights arrive with no recorded terms.\n"
              "   Nothing downstream can tell whether they may ship. Pass the id.", file=sys.stderr)

    name = args.name or args.checkpoint.stem.lower()
    output = ROOT / "models" / name
    if output.exists():
        print(f"{output} already exists — remove it first", file=sys.stderr)
        return 1

    import torch
    from diffusers import StableDiffusionPipeline

    print(f"reading {args.checkpoint.name} ({args.checkpoint.stat().st_size / 1e9:.2f} GB)")
    kwargs = {"torch_dtype": torch.float16, "safety_checker": None}
    # Point at the local base tree rather than a repo id. The conversion env is pinned and offline
    # reproducibility matters more here than tracking whatever `from_single_file` defaults to this
    # month — that default has already been renamed once under this project.
    if args.config_source.is_dir():
        kwargs["config"] = str(args.config_source)
        print(f"  config from {args.config_source}")

    pipeline = StableDiffusionPipeline.from_single_file(str(args.checkpoint), **kwargs)
    pipeline.save_pretrained(output, safe_serialization=True)
    backfill_legacy_tokenizer_files(output, args.config_source)

    if licence is not None:
        licences.write_licence_file(output, [licence])

    total = sum(f.stat().st_size for f in output.rglob("*") if f.is_file())
    print(f"\nwrote {output}  ({total / 1e9:.2f} GB)")
    for entry in sorted(output.iterdir()):
        print(f"  {entry.name}")

    if not (output / "model_index.json").exists():
        print("\n!! no model_index.json — the converter will refuse this tree", file=sys.stderr)
        return 1

    if args.delete_checkpoint:
        args.checkpoint.unlink()
        print(f"\nremoved {args.checkpoint}")

    # No `--lora epi_noiseoffset` in this hint any more. That LoRA is `allowCommercialUse:
    # ['Image', 'RentCivit']` with no 'Sell', and it fuses INTO the weights being distributed — so
    # it makes a shippable checkpoint unshippable, permanently and invisibly.
    print(f"\nnext:\n  python scripts/convert_sd15_coreml.py --source models/{name} \\\n"
          f"      --controlnet lllyasviel/control_v11f1e_sd15_tile")
    return 0


if __name__ == "__main__":
    sys.exit(main())

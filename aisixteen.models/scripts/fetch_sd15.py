#!/usr/bin/env python3
"""
Fetch Stable Diffusion 1.5 into a real `save_pretrained` tree.

Why not just `snapshot_download`: the Hugging Face cache stores every file as a content-addressed
blob with a symlink farm pointing at it. That is fine for Python, and useless as an input to a
Core ML conversion or as something to read, diff or copy — half the tools that walk the directory
follow a symlink to `blobs/<sha256>` and lose the filename. This loads the pipeline and writes it
back out with `save_pretrained`, which produces the canonical diffusers layout with real files:

    models/stable-diffusion-v1-5/
      model_index.json
      unet/{config.json, diffusion_pytorch_model.safetensors}
      vae/{config.json, diffusion_pytorch_model.safetensors}
      text_encoder/{config.json, model.safetensors}
      tokenizer/{...}
      scheduler/scheduler_config.json

fp16 only. The fp32 weights double the download and the disk for no benefit here: the Core ML
conversion quantises anyway, and the ANE never sees float64.

    python scripts/fetch_sd15.py [--output models/stable-diffusion-v1-5] [--keep-cache]
"""
import argparse
import shutil
import sys
from pathlib import Path

# The original `runwayml/stable-diffusion-v1-5` was withdrawn in 2024; this is the official
# re-upload under the model's own org. Both currently resolve, but this is the one that is
# maintained.
REPO = "stable-diffusion-v1-5/stable-diffusion-v1-5"

HERE = Path(__file__).resolve().parent
DEFAULT_OUTPUT = HERE.parent / "models" / "stable-diffusion-v1-5"


def fetch_legacy_tokenizer_files(repo: str, tokenizer_dir: Path) -> None:
    """Put `vocab.json` and `merges.txt` back beside the tokenizer.

    transformers 5.x saves a CLIP tokenizer as a single `tokenizer.json` and drops the legacy pair.
    Two things downstream still need them, so their absence is not cosmetic:

    * Apple's converter runs on transformers 4.44, whose slow `CLIPTokenizer` reads `vocab.json`
      directly and fails with `TypeError: expected str, bytes or os.PathLike object, not NoneType`
      — a message that says nothing about the actual cause.
    * The Swift `StableDiffusion` runtime tokenises with `vocab.json` + `merges.txt`. There is no
      `tokenizer.json` reader on the device side at all.

    So they are fetched from the source repo rather than regenerated, which keeps them byte-identical
    to what the model was trained against.
    """
    from huggingface_hub import hf_hub_download

    tokenizer_dir.mkdir(parents=True, exist_ok=True)
    for name in ("vocab.json", "merges.txt", "special_tokens_map.json"):
        target = tokenizer_dir / name
        if target.exists():
            continue
        downloaded = hf_hub_download(repo_id=repo, filename=f"tokenizer/{name}")
        target.write_bytes(Path(downloaded).read_bytes())
        print(f"  + tokenizer/{name}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--repo", default=REPO)
    parser.add_argument("--keep-cache", action="store_true",
                        help="Leave the Hugging Face blob cache in place. Off by default because "
                             "it is a second full copy of the weights.")
    args = parser.parse_args()

    import torch
    from diffusers import StableDiffusionPipeline

    if args.output.exists() and (args.output / "model_index.json").exists():
        print(f"already present: {args.output}")
        return 0

    print(f"downloading {args.repo} (fp16)…", flush=True)
    pipe = StableDiffusionPipeline.from_pretrained(
        args.repo,
        variant="fp16",
        torch_dtype=torch.float16,
        # The safety checker is a second CLIP model — ~1.2 GB that this app has no use for. It
        # classifies output images, and nothing downstream of the conversion calls it.
        safety_checker=None,
        # Without this, diffusers warns on every load about the checker it was told not to fetch.
        requires_safety_checker=False,
    )

    args.output.parent.mkdir(parents=True, exist_ok=True)
    print(f"writing save_pretrained tree → {args.output}", flush=True)
    pipe.save_pretrained(args.output, safe_serialization=True)

    fetch_legacy_tokenizer_files(args.repo, args.output / "tokenizer")

    if not args.keep_cache:
        from huggingface_hub import scan_cache_dir
        cache = scan_cache_dir()
        for repo in cache.repos:
            if repo.repo_id == args.repo:
                print(f"removing the blob cache copy ({repo.size_on_disk / 1e9:.1f} GB)")
                shutil.rmtree(repo.repo_path, ignore_errors=True)

    total = sum(f.stat().st_size for f in args.output.rglob("*") if f.is_file())
    print(f"done — {total / 1e9:.2f} GB in {args.output}")
    for entry in sorted(p for p in args.output.iterdir()):
        print("  ", entry.name + ("/" if entry.is_dir() else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())

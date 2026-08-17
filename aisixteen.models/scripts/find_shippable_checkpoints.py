#!/usr/bin/env python3
"""
Find CivitAI checkpoints whose terms actually permit shipping the weights in a product.

    python scripts/find_shippable_checkpoints.py                    # SD 1.5, wallpaper-suitable
    python scripts/find_shippable_checkpoints.py --all              # no aesthetic filter
    python scripts/find_shippable_checkpoints.py --base "SDXL 1.0"

Stdlib only, no API key. Exists because "search CivitAI, read the licence" is a job that will be
done again — for SDXL, for a replacement fine-tune, for a LoRA — and doing it by hand is how the
wrong answer gets accepted twice.

────────────────────────────────────────────────────────────────────────────────────────────────
THE BAR, AND WHY IT IS ALL THREE

    allowDerivatives      a Core ML conversion, especially with a LoRA merged in, is a derivative
    allowDifferentLicense the converted artefact ships under the app's terms, not CivitAI's
    allowCommercialUse    must contain "Sell"

`Image` permits selling *pictures you generated*; `Rent`/`RentCivit` cover hosted generation. It is
easy to read either as permission and both are wrong — neither lets you put the weights in a product
someone buys.

`allowNoCredit: false` does not disqualify a model. It obliges attribution in the app, which is
cheap; the finder reports it so the obligation is known before the model is chosen, not after.

Permissions are recorded on the **model**, not the version: the version endpoint carries no
permission fields at all, so a model's terms govern every file under it. Verifying "per version"
is therefore not something the API can express — this checks the model and lists its versions so
the exact file being shipped is identified.

────────────────────────────────────────────────────────────────────────────────────────────────
THE AESTHETIC FILTER

This is a wallpaper generator. Faces are where these models fail most visibly, and a wallpaper with
a face on it is a photograph — so by default the character, portrait and photoreal-person models
that dominate the download charts are filtered out, and style, landscape and illustration models are
kept. `--all` turns that off.
"""

from __future__ import annotations

import argparse
import json
import sys
import time
import urllib.parse
import urllib.request

CIVITAI_API = "https://civitai.com/api/v1"

# Tags that make a model a poor fit for a wallpaper regardless of its licence.
FIGURATIVE = {"girls", "woman", "female", "man", "1man", "1boy", "1guy", "person", "people",
              "portrait", "portraits", "photorealistic", "sexy", "nsfw", "hentai", "porn",
              "celebrity", "character", "clothing", "body", "old man", "asian"}
# Tags that suggest the range a wallpaper wants.
PICTORIAL = {"landscapes", "landscape", "art style", "style", "illustration", "illustrations",
             "art", "paintings", "painting", "concept art", "fantasy", "abstract", "scenery",
             "3d", "sci-fi", "architecture", "nature", "space", "texture", "background",
             "backgrounds", "digital illustration", "objects", "graphic design"}


def fetch(url: str) -> dict:
    request = urllib.request.Request(url, headers={"User-Agent": "aisixteen-models/1.0"})
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            return json.load(response)
    except Exception as error:                      # noqa: BLE001 — one bad page must not stop a sweep
        print(f"  (skipped {url.split('?')[-1][:60]}: {error})", file=sys.stderr)
        return {}


def sweep(base: str) -> dict[int, dict]:
    """Several queries, deduplicated by model id.

    One query is not enough: the `page` parameter is ignored on some sorts and silently returns page
    one again, so a naive loop produces the same hundred models three times over and looks thorough.
    Different sorts and tags reach genuinely different parts of the catalogue.
    """
    found: dict[int, dict] = {}
    encoded = urllib.parse.quote(base)
    queries = [f"sort={s}" for s in ["Most%20Downloaded", "Highest%20Rated", "Most%20Liked", "Newest"]]
    # Percent-encoded: a bare space in "concept art" makes urllib refuse the whole request, and the
    # sweep then silently covers one fewer corner of the catalogue.
    queries += [f"tag={urllib.parse.quote(t)}&sort=Most%20Downloaded" for t in
                ["art", "artstyle", "illustration", "painting", "landscape",
                 "fantasy", "abstract", "scenery", "background", "concept art"]]
    for query in queries:
        payload = fetch(f"{CIVITAI_API}/models?types=Checkpoint&baseModels={encoded}&limit=100&{query}")
        for model in payload.get("items", []):
            found[model["id"]] = model
        time.sleep(0.4)                             # courtesy to a free, unauthenticated API
    return found


def shippable(model: dict) -> bool:
    commercial = model.get("allowCommercialUse") or []
    return (bool(model.get("allowDerivatives"))
            and bool(model.get("allowDifferentLicense"))
            and "Sell" in commercial)


def pictorial_score(model: dict) -> int:
    tags = {t.lower() for t in (model.get("tags") or [])}
    return len(tags & PICTORIAL) - 2 * len(tags & FIGURATIVE)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--base", default="SD 1.5", help="baseModel to search")
    parser.add_argument("--all", action="store_true", help="skip the wallpaper-suitability filter")
    parser.add_argument("--limit", type=int, default=20)
    args = parser.parse_args()

    models = sweep(args.base)
    print(f"\nscanned {len(models)} {args.base} checkpoints")

    passing = [m for m in models.values() if shippable(m)]
    print(f"{len(passing)} pass allowDerivatives + allowDifferentLicense + 'Sell'")

    rows = passing if args.all else [m for m in passing if pictorial_score(m) > 0]
    if not args.all:
        print(f"{len(rows)} of those look like wallpaper material rather than character models")
    rows.sort(key=lambda m: (pictorial_score(m), m["stats"].get("downloadCount", 0) or 0),
              reverse=True)

    print(f"\n{'model':>7} {'downloads':>9} {'nsfw':<5} {'credit':<7} name")
    for model in rows[:args.limit]:
        versions = [v for v in model.get("modelVersions") or []
                    if str(v.get("baseModel", "")).startswith(args.base)]
        print(f"{model['id']:>7} {model['stats'].get('downloadCount', 0) or 0:>9} "
              f"{str(bool(model.get('nsfw'))):<5} "
              f"{'free' if model.get('allowNoCredit') else 'REQ':<7} {model['name'][:40]}")
        print(f"{'':>7} tags: {', '.join((model.get('tags') or [])[:8])}")
        for version in versions[:2]:
            files = version.get("files") or [{}]
            primary = next((f for f in files if f.get("primary")), files[0])
            print(f"{'':>7}   version {version['id']:>8}  {version.get('name', '')[:18]:<18} "
                  f"{primary.get('name', '?')[:40]:<40} {primary.get('sizeKB', 0) / 1e6:.2f} GB")
    print("\nRe-check the chosen model with scripts/licences.py before converting; "
          "import_single_file.py --civitai-model <id> does it automatically.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

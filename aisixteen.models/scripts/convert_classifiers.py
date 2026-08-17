#!/usr/bin/env python3
"""
Fetch and convert the content-safety classifiers to Core ML.

    conda activate aisixteen-convert
    python scripts/convert_classifiers.py                 # all three
    python scripts/convert_classifiers.py --only nsfw-image

────────────────────────────────────────────────────────────────────────────────────────────────
THREE MODELS, BECAUSE ONE DOES NOT COVER THIS

| key          | model                                          | what it answers                  |
|--------------|------------------------------------------------|----------------------------------|
| `profanity`  | unitary/toxic-bert                              | is the PROMPT abusive?           |
| `nsfw-text`  | eliasalbouzidi/distilbert-nsfw-text-classifier  | is the PROMPT sexual?            |
| `nsfw-image` | Falconsai/nsfw_image_detection                  | is the RESULT pornographic?      |

**`toxic-bert` does not detect NSFW.** Its labels come from the Jigsaw dataset, where `obscene`
means *swearing*, not sexual content. "a naked woman on a beach" scores near zero on every one of
its six labels. Using it as an NSFW filter would produce a filter that is confidently wrong, which
is worse than no filter — so the sexual-content question gets its own model.

**The image classifier is the one that actually works.** A prompt filter is trivially defeated:
misspellings, euphemism, foreign languages, or wording that is innocent in isolation. And the
inverse also happens — diffusion models produce nudity from prompts that contain nothing sexual at
all, because of what is in the training data. Only checking the generated pixels catches both. If
only one of these three ships, it should be this one.

All three are Apache-2.0. That is not incidental: the strongest domain match for prompt filtering,
`AdamCodd/distilroberta-nsfw-prompt-stable-diffusion`, is trained on actual Stable Diffusion
prompts and would be the better text model — but it is CC-BY-NC-4.0, which forbids commercial use
and therefore cannot ship in a paid app. Same for `TostAI/nsfw-image-detection-large`. They are
excluded on licence, not on quality.

────────────────────────────────────────────────────────────────────────────────────────────────
SHAPES

Text models take a fixed 128 wordpiece tokens. `PromptRules` caps a prompt at 500 characters and
CLIP truncates at 77 tokens before the diffusion model sees it, so 128 is already beyond what the
pipeline uses. The tokenizer is not part of the Core ML model — it runs on device from `vocab.txt`,
which is copied out beside each compiled model.

The image model takes a Core ML `ImageType`, not a tensor, so the app hands it a `CVPixelBuffer`
directly and Core ML does the resize and normalisation on the way in. Passing a tensor instead
would mean reimplementing ViT's preprocessing in Swift and getting the mean/std exactly right —
a silent-failure path where a slightly wrong normalisation yields a classifier that looks like it
works and is quietly miscalibrated.
────────────────────────────────────────────────────────────────────────────────────────────────
"""
import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
MODELS = HERE.parent / "models"

MAX_TOKENS = 128

CLASSIFIERS = {
    "profanity": {
        "repo": "unitary/toxic-bert",
        "kind": "text",
        "name": "PromptToxicity",
        "note": "Jigsaw labels: toxic, severe_toxic, obscene, threat, insult, identity_hate. "
                "`obscene` means swearing, NOT sexual content.",
    },
    "nsfw-text": {
        "repo": "eliasalbouzidi/distilbert-nsfw-text-classifier",
        "kind": "text",
        "name": "PromptNSFW",
        "note": "Binary safe / nsfw over the prompt.",
    },
    "nsfw-image": {
        "repo": "Falconsai/nsfw_image_detection",
        "kind": "image",
        "name": "ImageNSFW",
        "note": "ViT over the generated picture. The filter that cannot be talked around.",
    },
}


def convert_text(spec, source: Path, output: Path, tokens: int, nbits: int) -> list[str]:
    import numpy as np
    import torch
    import coremltools as ct
    from transformers import AutoModelForSequenceClassification, AutoTokenizer

    if not (source / "config.json").exists():
        print(f"  downloading {spec['repo']}…", flush=True)
        AutoModelForSequenceClassification.from_pretrained(spec["repo"]).save_pretrained(
            source, safe_serialization=True)
        AutoTokenizer.from_pretrained(spec["repo"]).save_pretrained(source)

    # torchscript=True makes the model return a tuple; the default dict output cannot be traced.
    model = AutoModelForSequenceClassification.from_pretrained(source, torchscript=True).eval()
    labels = [model.config.id2label[i] for i in range(len(model.config.id2label))]

    example = (torch.zeros((1, tokens), dtype=torch.int32),
               torch.ones((1, tokens), dtype=torch.int32))
    with torch.no_grad():
        traced = torch.jit.trace(model, example, strict=False)

    mlmodel = ct.convert(
        traced,
        convert_to="mlprogram",
        # int32, not int64: the Neural Engine has no int64, and a token id that silently truncates
        # would classify a different sentence than the one the user typed.
        # `np.int32`, not the string "int32" — coremltools takes a numpy type here and rejects the
        # string with `dtype=int32 is unsupported`, which reads like the dtype itself is the problem.
        inputs=[ct.TensorType(name="input_ids", shape=(1, tokens), dtype=np.int32),
                ct.TensorType(name="attention_mask", shape=(1, tokens), dtype=np.int32)],
        outputs=[ct.TensorType(name="logits")],
        compute_precision=ct.precision.FLOAT16,
        minimum_deployment_target=ct.target.iOS17,
    )
    mlmodel.input_description["input_ids"] = f"BERT wordpiece ids, padded to {tokens}"
    mlmodel.input_description["attention_mask"] = "1 for real tokens, 0 for padding"
    mlmodel.output_description["logits"] = "one logit per label; apply a sigmoid"
    finish(mlmodel, spec, source, output, labels, nbits, extra={"max_tokens": str(tokens)})
    return labels


def convert_image(spec, source: Path, output: Path, nbits: int) -> list[str]:
    import torch
    import coremltools as ct
    from transformers import AutoImageProcessor, AutoModelForImageClassification

    if not (source / "config.json").exists():
        print(f"  downloading {spec['repo']}…", flush=True)
        AutoModelForImageClassification.from_pretrained(spec["repo"]).save_pretrained(
            source, safe_serialization=True)
        AutoImageProcessor.from_pretrained(spec["repo"]).save_pretrained(source)

    model = AutoModelForImageClassification.from_pretrained(source, torchscript=True).eval()
    processor = AutoImageProcessor.from_pretrained(source)
    labels = [model.config.id2label[i] for i in range(len(model.config.id2label))]

    size = processor.size
    side = size.get("height") or size.get("shortest_edge") or 224
    mean = processor.image_mean
    std = processor.image_std

    example = torch.zeros((1, 3, side, side), dtype=torch.float32)
    with torch.no_grad():
        traced = torch.jit.trace(model, example, strict=False)

    # Core ML applies `pixel * scale + bias` per channel to the 0–255 input. That reproduces
    # (pixel/255 - mean) / std exactly, so the normalisation matches what the model was trained on
    # without a line of Swift.
    scale = 1.0 / (255.0 * std[0])
    bias = [-mean[i] / std[i] for i in range(3)]

    mlmodel = ct.convert(
        traced,
        convert_to="mlprogram",
        inputs=[ct.ImageType(name="image", shape=(1, 3, side, side),
                             scale=scale, bias=bias, color_layout=ct.colorlayout.RGB)],
        outputs=[ct.TensorType(name="logits")],
        compute_precision=ct.precision.FLOAT16,
        minimum_deployment_target=ct.target.iOS17,
    )
    mlmodel.input_description["image"] = f"RGB, {side}×{side}; Core ML normalises on input"
    mlmodel.output_description["logits"] = "one logit per label; apply a softmax"
    finish(mlmodel, spec, source, output, labels, nbits,
           extra={"input_size": str(side), "image_mean": json.dumps(mean),
                  "image_std": json.dumps(std)})
    return labels


def finish(mlmodel, spec, source: Path, output: Path, labels, nbits: int, extra: dict) -> None:
    import coremltools as ct

    if nbits < 16:
        from coremltools.optimize.coreml import (
            OpPalettizerConfig, OptimizationConfig, palettize_weights)
        print(f"  palettising to {nbits} bits…", flush=True)
        mlmodel = palettize_weights(
            mlmodel, OptimizationConfig(
                global_config=OpPalettizerConfig(mode="kmeans", nbits=nbits)))

    # The label order travels inside the model. A classifier whose output order lives only in a
    # comment in some Swift file is one refactor away from reporting `threat` when it meant
    # `obscene` — and nothing would fail loudly.
    mlmodel.user_defined_metadata["labels"] = json.dumps(labels)
    mlmodel.user_defined_metadata["source"] = spec["repo"]
    mlmodel.user_defined_metadata["note"] = spec["note"]
    for key, value in extra.items():
        mlmodel.user_defined_metadata[key] = value
    mlmodel.short_description = spec["note"]

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
        raise RuntimeError(result.stdout + result.stderr)

    vocab = source / "vocab.txt"
    if vocab.exists():
        shutil.copy(vocab, output / "vocab.txt")

    (output / "labels.json").write_text(json.dumps(labels, indent=2))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--only", choices=sorted(CLASSIFIERS), action="append", default=[])
    parser.add_argument("--tokens", type=int, default=MAX_TOKENS)
    parser.add_argument("--nbits", type=int, default=16, choices=[4, 8, 16],
                        help="16 = fp16. A binary classifier tolerates 8 or 4 far better than a "
                             "diffusion unet does, if size matters.")
    args = parser.parse_args()

    chosen = args.only or list(CLASSIFIERS)
    for key in chosen:
        spec = CLASSIFIERS[key]
        source = MODELS / key
        output = MODELS / "coreml" / f"{key}-{args.nbits}bit"
        output.mkdir(parents=True, exist_ok=True)

        print(f"\n── {key}: {spec['repo']}", flush=True)
        if spec["kind"] == "text":
            labels = convert_text(spec, source, output, args.tokens, args.nbits)
        else:
            labels = convert_image(spec, source, output, args.nbits)

        total = sum(f.stat().st_size for f in (output / f"{spec['name']}.mlmodelc").rglob("*")
                    if f.is_file())
        print(f"   labels: {labels}")
        print(f"   {spec['name']}.mlmodelc — {total / 1e6:.0f} MB  →  {output}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

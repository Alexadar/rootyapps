#!/usr/bin/env python3
"""
Check the converted classifiers against the PyTorch models they came from.

    conda activate aisixteen-convert
    python scripts/verify_classifiers.py

This is a **parity** test, not an accuracy test, and the distinction matters. Whether
`Falconsai/nsfw_image_detection` is good at its job is the upstream author's business and is
measured on their benchmark. What is ours is whether tracing, fp16 conversion and compilation
preserved it — and that failure is silent. A model that lost its head during tracing, or got its
image normalisation wrong by a factor of 255, still returns two plausible-looking numbers for every
input. Nothing throws. You find out from a review rejection.

So every model is run both ways on the same input and the logits compared. Anything above a small
tolerance means the converted model is not the model that was evaluated.

The image parity check uses the wallpaper the pipeline itself produced, because the thing this
classifier will actually see is Stable Diffusion output — not a photograph.
"""
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
MODELS = HERE.parent / "models"

# fp16 has ~3 decimal digits of mantissa; logits of this magnitude agree to about this much. A
# genuine conversion fault (a dropped head, wrong normalisation, transposed input) is off by whole
# units, not hundredths — this threshold separates those two cases comfortably.
TOLERANCE = 0.05

PROMPTS = [
    "molten glass poppies at dusk, macro, shallow depth of field",
    "an alpine lake at first light, large-format film",
    "you are a worthless piece of shit",
    "a naked woman lying on a bed, explicit",
]


def check_text(key: str, model_name: str) -> bool:
    import numpy as np
    import torch
    import coremltools as ct
    from transformers import AutoModelForSequenceClassification, AutoTokenizer

    source = MODELS / key
    compiled = MODELS / "coreml" / f"{key}-16bit" / f"{model_name}.mlmodelc"
    labels = json.loads((MODELS / "coreml" / f"{key}-16bit" / "labels.json").read_text())

    torch_model = AutoModelForSequenceClassification.from_pretrained(source).eval()
    tokenizer = AutoTokenizer.from_pretrained(source)
    mlmodel = ct.models.CompiledMLModel(str(compiled))

    print(f"\n── {key}  ({', '.join(labels)})")
    ok = True
    for prompt in PROMPTS:
        encoded = tokenizer(prompt, padding="max_length", truncation=True,
                            max_length=128, return_tensors="pt")
        with torch.no_grad():
            reference = torch_model(input_ids=encoded["input_ids"],
                                    attention_mask=encoded["attention_mask"]).logits[0].numpy()
        converted = mlmodel.predict({
            "input_ids": encoded["input_ids"].numpy().astype(np.int32),
            "attention_mask": encoded["attention_mask"].numpy().astype(np.int32),
        })["logits"][0]

        drift = float(np.max(np.abs(reference - converted)))
        scores = 1 / (1 + np.exp(-converted))
        top = labels[int(np.argmax(converted))]
        verdict = "ok " if drift <= TOLERANCE else "OFF"
        if drift > TOLERANCE:
            ok = False
        print(f"  {verdict} drift {drift:6.4f}  top={top:<14} "
              f"{ {l: round(float(s), 3) for l, s in zip(labels, scores)} }")
        print(f"       “{prompt[:64]}”")
    return ok


def check_image(key: str, model_name: str, image_path: Path) -> bool:
    import numpy as np
    import torch
    import coremltools as ct
    from PIL import Image
    from transformers import AutoImageProcessor, AutoModelForImageClassification

    source = MODELS / key
    compiled = MODELS / "coreml" / f"{key}-16bit" / f"{model_name}.mlmodelc"
    labels = json.loads((MODELS / "coreml" / f"{key}-16bit" / "labels.json").read_text())

    torch_model = AutoModelForImageClassification.from_pretrained(source).eval()
    processor = AutoImageProcessor.from_pretrained(source)
    mlmodel = ct.models.CompiledMLModel(str(compiled))
    side = processor.size.get("height") or processor.size.get("shortest_edge") or 224

    print(f"\n── {key}  ({', '.join(labels)})")
    image = Image.open(image_path).convert("RGB")

    with torch.no_grad():
        reference = torch_model(**processor(images=image, return_tensors="pt")).logits[0].numpy()
    # Core ML does the normalisation itself, so it is handed the plain resized RGB.
    converted = mlmodel.predict({"image": image.resize((side, side), Image.BICUBIC)})["logits"][0]

    drift = float(np.max(np.abs(reference - converted)))
    exp = np.exp(converted - np.max(converted))
    scores = exp / exp.sum()
    verdict = "ok " if drift <= TOLERANCE else "OFF"
    print(f"  {verdict} drift {drift:6.4f}  top={labels[int(np.argmax(converted))]:<8} "
          f"{ {l: round(float(s), 4) for l, s in zip(labels, scores)} }")
    print(f"       {image_path.name}")
    return drift <= TOLERANCE


def main() -> int:
    results = {
        "profanity": check_text("profanity", "PromptToxicity"),
        "nsfw-text": check_text("nsfw-text", "PromptNSFW"),
    }

    generated = sorted((MODELS / "out").glob("*.png"))
    if generated:
        results["nsfw-image"] = check_image("nsfw-image", "ImageNSFW", generated[0])
    else:
        print("\n!! no generated image to check the image classifier against — "
              "run scripts/test_raw_model.sh first")

    print("\n" + "─" * 70)
    for key, ok in results.items():
        print(f"  {key:<12} {'parity ok' if ok else 'DRIFTED — the converted model is not the reference'}")
    return 0 if all(results.values()) else 1


if __name__ == "__main__":
    sys.exit(main())

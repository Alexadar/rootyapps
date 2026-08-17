#!/usr/bin/env python3
"""
Whether a model may be shipped, asked before it is converted rather than after.

`convert_upscaler.py` already worked this way — it refuses non-shippable weights, stamps the licence
into `mlmodel.user_defined_metadata` and writes a `LICENCE.txt` beside the output. This is the same
gate for checkpoints and LoRAs, so nothing can be converted silently and then discovered to be
unshippable a fortnight later with an app built on top of it. That has now happened twice in this
project: 4x-UltraSharp (CC-BY-NC-SA) and Art Universe.

────────────────────────────────────────────────────────────────────────────────────────────────
WHAT "SHIPPABLE" MEANS HERE

Shipping means **redistributing the weights inside a product a user pays for**, whether they arrive
in the app bundle or as a downloaded asset pack. That is a higher bar than most people assume when
they download a checkpoint, and CivitAI records the answer in three fields that all have to pass:

    allowDerivatives      a Core ML conversion — especially with a LoRA merged in — is a derivative
    allowDifferentLicense the converted artefact ships under the app's terms, not CivitAI's
    allowCommercialUse    must include "Sell"

`Image` means you may sell *pictures you generated*. `Rent`/`RentCivit` cover hosted generation
services. **Neither permits putting the weights in a product.** Getting this wrong is the single
most expensive mistake available here, because it is invisible until someone reads the licence.

`allowNoCredit: false` does not block shipping — it obliges attribution in the app.

Permissions live on the **model**, not the version: the CivitAI version endpoint carries no
permission fields at all, so the model's terms govern every file under it.
"""

from __future__ import annotations

import json
import urllib.request
from dataclasses import dataclass
from pathlib import Path

CIVITAI_API = "https://civitai.com/api/v1"


@dataclass
class Licence:
    source: str
    name: str
    allow_derivatives: bool
    allow_different_licence: bool
    commercial: list[str]
    allow_no_credit: bool
    url: str = ""
    #: An obligation that survives the three booleans. OpenRAIL-M is the reason this field exists:
    #: it permits commercial redistribution *provided the Attachment A use restrictions pass through
    #: into the downstream licence*. Encoding that as "shippable" and nothing else would hide a real
    #: contractual duty behind a green tick.
    obligation: str = ""

    @property
    def shippable(self) -> bool:
        return (self.allow_derivatives
                and self.allow_different_licence
                and "Sell" in self.commercial)

    @property
    def requires_attribution(self) -> bool:
        return not self.allow_no_credit

    def report(self) -> str:
        verdict = "SHIPPABLE" if self.shippable else "NOT SHIPPABLE"
        lines = [
            f"{self.name}  ({self.source})",
            f"  allowDerivatives      : {self.allow_derivatives}",
            f"  allowDifferentLicense : {self.allow_different_licence}",
            f"  allowCommercialUse    : {self.commercial}",
            f"  allowNoCredit         : {self.allow_no_credit}",
            f"  => {verdict}",
        ]
        if self.shippable and self.requires_attribution:
            lines.append("  NOTE: attribution required — credit the author in the app.")
        if self.obligation:
            lines.append(f"  OBLIGATION: {self.obligation}")
        if not self.shippable:
            lines.append("  Reason: " + ", ".join(self.reasons()))
        return "\n".join(lines)

    def reasons(self) -> list[str]:
        why = []
        if not self.allow_derivatives:
            why.append("allowDerivatives is false — a converted, LoRA-merged artefact is a derivative")
        if not self.allow_different_licence:
            why.append("allowDifferentLicense is false — it cannot ship under the app's terms")
        if "Sell" not in self.commercial:
            why.append(f"allowCommercialUse {self.commercial} has no 'Sell' — "
                       "selling generated images is not the same as selling the weights")
        return why

    def text(self) -> str:
        return (f"{self.name}\nSource: {self.url or self.source}\n\n"
                f"allowDerivatives:      {self.allow_derivatives}\n"
                f"allowDifferentLicense: {self.allow_different_licence}\n"
                f"allowCommercialUse:    {self.commercial}\n"
                f"allowNoCredit:         {self.allow_no_credit}\n\n"
                f"Shippable in a commercial app: {'yes' if self.shippable else 'NO'}\n"
                + ("Attribution required in the app.\n" if self.requires_attribution else "")
                + (f"Obligation: {self.obligation}\n" if self.obligation else ""))


def from_civitai(model_id: int) -> Licence:
    url = f"{CIVITAI_API}/models/{model_id}"
    request = urllib.request.Request(url, headers={"User-Agent": "aisixteen-models/1.0"})
    with urllib.request.urlopen(request, timeout=60) as response:
        payload = json.load(response)
    if "name" not in payload:
        raise LookupError(f"CivitAI model {model_id}: {payload}")
    return Licence(source=f"CivitAI model {model_id}",
                   name=payload["name"],
                   allow_derivatives=bool(payload.get("allowDerivatives")),
                   allow_different_licence=bool(payload.get("allowDifferentLicense")),
                   commercial=list(payload.get("allowCommercialUse") or []),
                   allow_no_credit=bool(payload.get("allowNoCredit")),
                   url=f"https://civitai.com/models/{model_id}")


def gate(licence: Licence, *, allow_unshippable: bool) -> None:
    """Print the verdict, and stop unless the caller has said in as many words that it is fine.

    The override is deliberately long to type. A short `--force` gets reached for reflexively; this
    one has to be meant, and it shows up in shell history and CI logs as a decision someone made.
    """
    print(licence.report())
    if licence.shippable or allow_unshippable:
        if not licence.shippable:
            print("\n⚠️  Converting anyway — LOCAL EVALUATION ONLY. This artefact must not ship.\n")
        return
    raise SystemExit(
        "\nRefusing to convert: these weights cannot be redistributed in a product.\n"
        "Pass --allow-unshippable to convert it anyway for local evaluation, or pick a checkpoint "
        "whose terms permit shipping (see scripts/find_shippable_checkpoints.py).")


def write_licence_file(directory: Path, licences: list[Licence]) -> None:
    """A `LICENCE.txt` beside the artefact, listing everything merged into it.

    Every input's terms bind the output. A permissively licensed checkpoint with a non-commercial
    LoRA fused in at 0.7 is a non-commercial artefact, and the fused weights carry no record of
    where they came from — so the record has to be written down next to them.
    """
    directory.mkdir(parents=True, exist_ok=True)
    shippable = all(item.shippable for item in licences)
    body = ["Everything merged into this artefact, and the terms of each.",
            "",
            f"SHIPPABLE IN A COMMERCIAL APP: {'yes' if shippable else 'NO'}",
            ""]
    if not shippable:
        body += ["Blocked by:"] + [f"  - {i.name}: {'; '.join(i.reasons())}" for i in licences
                                   if not i.shippable] + [""]
    attribution = [i.name for i in licences if i.shippable and i.requires_attribution]
    if attribution:
        body += ["Attribution required in the app for: " + ", ".join(attribution), ""]
    duties = [f"  - {i.name}: {i.obligation}" for i in licences if i.obligation]
    if duties:
        body += ["Obligations that survive the permission flags:"] + duties + [""]
    body += ["-" * 96, ""]
    for item in licences:
        body += [item.text(), "-" * 96, ""]
    (directory / "LICENCE.txt").write_text("\n".join(body))
    print(f"  wrote {directory / 'LICENCE.txt'}  (shippable: {'yes' if shippable else 'NO'})")


# Licences for inputs that are not CivitAI models, recorded by hand from the upstream source.
KNOWN: dict[str, Licence] = {
    "stable-diffusion-v1-5": Licence(
        source="HuggingFace stable-diffusion-v1-5/stable-diffusion-v1-5",
        name="Stable Diffusion 1.5 (CreativeML OpenRAIL-M)",
        allow_derivatives=True, allow_different_licence=True,
        commercial=["Image", "Rent", "RentCivit", "Sell"], allow_no_credit=True,
        url="https://huggingface.co/stable-diffusion-v1-5/stable-diffusion-v1-5",
        obligation="OpenRAIL-M permits commercial redistribution ONLY IF the Attachment A use "
                   "restrictions are passed through into the app's own EULA, and the licence is "
                   "supplied to every recipient. That is a real, drafted obligation on the app's "
                   "terms of service — not boilerplate to tick off."),
    # All of ControlNet 1.1 is CreativeML OpenRAIL-M, NOT Apache-2.0. Recorded wrongly here once;
    # verified against the HuggingFace API for tile, mlsd and depth alike.
    "controlnet": Licence(
        source="HuggingFace lllyasviel/ControlNet-v1-1",
        name="ControlNet 1.1 (CreativeML OpenRAIL-M)",
        allow_derivatives=True, allow_different_licence=True,
        commercial=["Image", "Rent", "RentCivit", "Sell"], allow_no_credit=True,
        url="https://huggingface.co/lllyasviel",
        obligation="OpenRAIL-M — the Attachment A use restrictions must pass through into the "
                   "app's own EULA, exactly as for Stable Diffusion 1.5."),
    "depth-anything-v2-small": Licence(
        source="HuggingFace depth-anything/Depth-Anything-V2-Small-hf",
        name="Depth Anything V2 Small (Apache-2.0)",
        allow_derivatives=True, allow_different_licence=True,
        commercial=["Image", "Rent", "RentCivit", "Sell"], allow_no_credit=True,
        url="https://huggingface.co/depth-anything/Depth-Anything-V2-Small-hf"),
}

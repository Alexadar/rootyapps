#!/usr/bin/env python3
"""Stamp out marketing/aso/<locale>/<platform>/params.yaml for every media language.

The English params.yaml for each platform is the template: style, size and paths are copied
verbatim and only the caption text and the two folder paths change. One template per platform is
what stops a style tweak having to be re-applied by hand in every language.

Ported from eartharound.swift/marketing/gen_params.py — same contract, different caption keys
(this app has separate ipad/mac caption sets because those canvases carry 4 shots, not 6).

    python3 gen_params.py            # every media locale, every platform
    python3 gen_params.py de ja      # just these
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
_DATA = json.loads((ROOT / "captions.json").read_text())
CAPTION_SETS = {
    "ios": _DATA["captions"],
    "ipad": _DATA["ipad_captions"],
    "mac": _DATA["mac_captions"],
}
# Locales the store gets images for. Everything else inherits the primary language's screenshots
# by Apple's own default — shooting all 17 would only buy a maintenance tax on every UI change.
MEDIA_LOCALES = tuple(l for l in _DATA["media_locales"] if l != "en")


def render(template: str, locale: str, platform: str, texts) -> str:
    """Rewrite the two paths and replace the whole `texts:` block."""
    head = template.split("texts:")[0].rstrip() + "\n"
    head = head.replace(f"/marketing/raw/en/{platform}", f"/marketing/raw/{locale}/{platform}")
    head = head.replace(f"/marketing/aso/en/{platform}", f"/marketing/aso/{locale}/{platform}")

    lines = ["texts:"]
    for title, subtitle in texts:
        # Quoted so a caption containing ':' or '?' can never break the YAML — and Japanese
        # is written non-ASCII-escaped so the file stays readable.
        lines.append(f"  - title: {json.dumps(title, ensure_ascii=False)}")
        lines.append(f"    subtitle: {json.dumps(subtitle, ensure_ascii=False)}")
    return head + "\n".join(lines) + "\n"


def main() -> None:
    wanted = sys.argv[1:] or list(MEDIA_LOCALES)
    written = 0
    for platform, caption_set in CAPTION_SETS.items():
        tpl_path = ROOT / "aso" / "en" / platform / "params.yaml"
        if not tpl_path.exists():
            print(f"skip {platform}: no English template at {tpl_path.relative_to(ROOT)}")
            continue
        template = tpl_path.read_text()
        for locale in wanted:
            if locale == "en":
                continue                       # the template IS English
            if locale not in caption_set:
                print(f"skip {locale}/{platform}: no captions")
                continue
            dest = ROOT / "aso" / locale / platform
            dest.mkdir(parents=True, exist_ok=True)
            (dest / "params.yaml").write_text(render(template, locale, platform, caption_set[locale]))
            print(f"wrote aso/{locale}/{platform}/params.yaml  ({len(caption_set[locale])} captions)")
            written += 1
    print(f"\n{written} params files")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Stamp out marketing/aso/<locale>/<platform>/params.yaml for every shot locale.

The English params.yaml for each platform is the template: style, sizes and everything else are
copied verbatim, and only the two folder paths and the `texts:` block change. One template per
platform is what stops a style tweak from having to be applied 12 times by hand.

    python3 gen_params.py            # every shot locale, every platform
    python3 gen_params.py de fr      # just these
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
CAPTIONS = json.loads((ROOT / "captions.json").read_text())
PLATFORMS = ("ios", "ipad", "mac")

# Screenshot locales only. Every other storefront inherits the primary language's images by
# Apple's own default, so shooting them would buy nothing but a maintenance tax on each future
# UI change. See marketing/aso/metadata/ for the 17 locales that DO get localized text.
SHOT_LOCALES = ("en", "de", "fr", "ja")


def render(template: str, locale: str, platform: str, texts) -> str:
    """Rewrite the two paths and replace the whole `texts:` block."""
    head = template.split("texts:")[0].rstrip() + "\n\n"
    head = head.replace(f"marketing/raw/en/{platform}", f"marketing/raw/{locale}/{platform}")
    head = head.replace(f"marketing/aso/en/{platform}", f"marketing/aso/{locale}/{platform}")

    lines = ["texts:"]
    for title, subtitle in texts:
        # JSON-quoted so a caption containing ':' or '?' can never break the YAML, and so CJK
        # survives without depending on the YAML writer's escaping.
        lines.append(f"  - title: {json.dumps(title, ensure_ascii=False)}")
        lines.append(f"    subtitle: {json.dumps(subtitle, ensure_ascii=False)}")
    return head + "\n".join(lines) + "\n"


def main() -> None:
    wanted = sys.argv[1:] or list(SHOT_LOCALES)
    for platform in PLATFORMS:
        template = (ROOT / "aso" / "en" / platform / "params.yaml").read_text()
        expected = len(CAPTIONS[platform]["en"])
        for locale in wanted:
            # English is stamped too, from its own file's head. It used to be skipped because the
            # en params.yaml *was* the template — which meant every caption change had to be hand
            # applied to English and generated for the rest, and the two drifted the moment a shot
            # was added. Only `style:` and the paths come from the file now; `texts:` always comes
            # from captions.json, for every locale including English.
            texts = CAPTIONS[platform][locale]
            if len(texts) != expected:
                sys.exit(f"{locale}/{platform}: {len(texts)} captions, English has {expected} — "
                         "the count must match the raw captures")
            dest = ROOT / "aso" / locale / platform / "params.yaml"
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_text(render(template, locale, platform, texts))
            print(f"wrote {dest.relative_to(ROOT)}  ({len(texts)} captions)")


if __name__ == "__main__":
    main()

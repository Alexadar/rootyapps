#!/usr/bin/env python3
"""Stamp out marketing/aso/<locale>/params.yaml for every shipped language.

The English params.yaml for each platform is the template: style, size and paths are copied
verbatim and only the caption text and the two folder paths change. Keeping one template per
platform is what stops a style tweak having to be applied 19 times by hand.

    python3 gen_params.py            # all locales, ios + ipad
    python3 gen_params.py de fr      # just these
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
_DATA = json.loads((ROOT / "captions.json").read_text())
CAPTIONS = _DATA["captions"]
WATCH_CAPTIONS = _DATA["watch_captions"]
PLATFORMS = ("ios", "ipad", "mac", "watch")

# Screenshot locales. Everything else inherits the primary language's images by Apple's own
# default, so shooting them would only buy a maintenance tax on every future UI change.
SHOT_LOCALES = ("de", "ja", "fr", "es")


def render(template: str, locale: str, platform: str, texts) -> str:
    """Rewrite the two paths and replace the whole `texts:` block."""
    head = template.split("texts:")[0].rstrip() + "\n"
    head = head.replace(f"raw_folder: {ROOT}/raw/en/{platform}",
                        f"raw_folder: {ROOT}/raw/{locale}/{platform}")
    head = head.replace(f"output_folder: {ROOT}/aso/en/{platform}",
                        f"output_folder: {ROOT}/aso/{locale}/{platform}")

    lines = ["texts:"]
    for title, subtitle in texts:
        # Quoted so a caption containing ':' or '?' can never break the YAML.
        lines.append(f"  - title: {json.dumps(title, ensure_ascii=False)}")
        lines.append(f"    subtitle: {json.dumps(subtitle, ensure_ascii=False)}")
    return head + "\n".join(lines) + "\n"


def main() -> None:
    wanted = sys.argv[1:] or list(SHOT_LOCALES)
    for platform in PLATFORMS:
        template = (ROOT / "aso" / "en" / platform / "params.yaml").read_text()
        for locale in wanted:
            if locale == "en":
                continue                      # the template IS English
            texts = (WATCH_CAPTIONS if platform == "watch" else CAPTIONS)[locale]
            dest = ROOT / "aso" / locale / platform
            dest.mkdir(parents=True, exist_ok=True)
            (dest / "params.yaml").write_text(render(template, locale, platform, texts))
            print(f"wrote aso/{locale}/{platform}/params.yaml")


if __name__ == "__main__":
    main()

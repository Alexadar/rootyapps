#!/usr/bin/env python3
"""Stamp scenes_<locale>.json for every reel locale from the English scenes.json.

Timing, canvas, style and the scene KEYS all come from the English file — those drive the demo
tour alignment and must not drift per language. Only the caption words and the outro tagline
are replaced. The app NAME stays untranslated.

    python3 gen_scenes.py           # every locale in reel_captions.json
    python3 gen_scenes.py de ja
"""
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
CAPTIONS = json.loads((HERE / "reel_captions.json").read_text())["locales"]

# base scene file -> output prefix. Each platform has its own canvas and framing but the SAME
# timing and scene keys, because those align to the markers the app's demo tour emits.
BASES = {
    "scenes.json":      "scenes",
    "scenes_ipad.json": "scenes_ipad",
    "scenes_mac.json":  "scenes_mac",
}


def main() -> None:
    wanted = sys.argv[1:] or list(CAPTIONS)
    for base_name, prefix in BASES.items():
        base_path = HERE / base_name
        if not base_path.exists():
            continue
        base = json.loads(base_path.read_text())
        for locale in wanted:
            row = CAPTIONS[locale]
            lines = row["scenes"]
            scenes = json.loads(json.dumps(base))          # deep copy
            if len(lines) != len(scenes["scenes"]):
                raise SystemExit(f"{locale}/{prefix}: {len(lines)} captions for "
                                 f"{len(scenes['scenes'])} scenes")
            for scene, (title, subtitle) in zip(scenes["scenes"], lines):
                scene["title"] = title
                scene["subtitle"] = subtitle
            scenes["app"]["tagline"] = row["tagline"]
            out = HERE / f"{prefix}_{locale}.json"
            out.write_text(json.dumps(scenes, ensure_ascii=False, indent=2) + "\n")
            print(f"wrote {out.name}")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Stamp scenes_<locale>.json for every reel locale from the English scenes.json.

Timing, canvas, style and the scene KEYS all come from the English file — those drive the
DemoDriver alignment and must not drift per language. Only the caption words and the outro
tagline are replaced.

    python3 gen_scenes.py           # all locales in reel_captions.json
    python3 gen_scenes.py de ja
"""
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
CAPTIONS = json.loads((HERE / "reel_captions.json").read_text())["locales"]

# base scene file -> output prefix. Each platform has its own canvas and framing but the SAME
# timing and scene keys, because those align to the DemoDriver markers the app emits.
# base file -> (output prefix, caption source). The watch tour has 3 beats, not 6, and its lines
# are the same ones already written for the watch screenshots — reused, not duplicated.
BASES = {
    "scenes.json":       ("scenes", "reel"),
    "scenes_ipad.json":  ("scenes_ipad", "reel"),
    "scenes_mac.json":   ("scenes_mac", "reel"),
    "scenes_watch.json": ("scenes_watch", "watch"),
}
WATCH_CAPTIONS = json.loads((HERE.parent / "captions.json").read_text())["watch_captions"]


def main() -> None:
    wanted = sys.argv[1:] or list(CAPTIONS)
    for base_name, (prefix, source) in BASES.items():
      base_path = HERE / base_name
      if not base_path.exists():
          continue
      base = json.loads(base_path.read_text())
      for locale in wanted:
        row = CAPTIONS[locale]
        lines = row["scenes"] if source == "reel" else WATCH_CAPTIONS[locale]
        scenes = json.loads(json.dumps(base))          # deep copy
        if len(lines) != len(scenes["scenes"]):
            raise SystemExit(
                f"{locale}/{prefix}: {len(lines)} captions for {len(scenes['scenes'])} scenes")
        for scene, (title, subtitle) in zip(scenes["scenes"], lines):
            scene["title"] = title
            scene["subtitle"] = subtitle
        scenes["app"]["tagline"] = row["tagline"]       # the app NAME stays untranslated
        out = HERE / f"{prefix}_{locale}.json"
        out.write_text(json.dumps(scenes, ensure_ascii=False, indent=2) + "\n")
        print(f"wrote {out.name}")


if __name__ == "__main__":
    main()

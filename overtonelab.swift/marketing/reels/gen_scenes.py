#!/usr/bin/env python3
"""Stamp scenes_<locale>.json for every reel locale from the English scene files.

Timing, canvas, style, the `src` cut windows and the scene KEYS all come from the English file —
those align to the ReelTour walkthrough and must not drift per language. Only the caption words
change.

Ported from eartharound.swift/marketing/reels/gen_scenes.py.

    python3 gen_scenes.py           # every locale in reel_captions.json
    python3 gen_scenes.py de ja
"""
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
_CAP = json.loads((HERE / "reel_captions.json").read_text())
CAPTIONS = _CAP["locales"]
MAC_CAPTIONS = _CAP["mac_locales"]

# base scene file -> (output prefix, caption source). The Mac cut keys its scenes lower-case
# because they come from the window-recorder scene names, not the XCUITest tour markers.
BASES = {
    "scenes.json":            ("scenes", CAPTIONS),
    "scenes_ipad.json":       ("scenes_ipad", CAPTIONS),
    "scenes_mac_store.json":  ("scenes_mac_store", MAC_CAPTIONS),
}


def main() -> None:
    wanted = sys.argv[1:] or list(CAPTIONS)
    written = 0
    for base_name, (prefix, source) in BASES.items():
        base_path = HERE / base_name
        if not base_path.exists():
            print(f"skip {base_name}: not found")
            continue
        base = json.loads(base_path.read_text())
        for locale in wanted:
            words = source.get(locale)
            if not words:
                print(f"skip {locale}/{prefix}: no captions")
                continue
            out = json.loads(json.dumps(base))          # deep copy
            missing = [s["key"] for s in out["scenes"] if s["key"] not in words]
            if missing:
                print(f"!! {locale}/{prefix}: no caption for scene key(s) {missing} — left English")
            for scene in out["scenes"]:
                if scene["key"] in words:
                    scene["title"], scene["subtitle"] = words[scene["key"]]
            out["_generated"] = f"gen_scenes.py from {base_name} — edit reel_captions.json, not this"
            dest = HERE / f"{prefix}_{locale}.json"
            dest.write_text(json.dumps(out, ensure_ascii=False, indent=2) + "\n")
            print(f"wrote {dest.name}")
            written += 1
    print(f"\n{written} scene files")


if __name__ == "__main__":
    main()

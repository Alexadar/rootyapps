#!/usr/bin/env python3
"""Generate one Localizable.xcstrings per target from Localization/strings.json.

One catalog for everything: DesignShared/ is a synchronized group belonging to all four targets, so
its Localizable.xcstrings lands in every bundle (app, widget, watch app, complication). Xcode
rejects more than one catalog per target, which is what proves a single shared file is the design.

Keys are the English source string, because SwiftUI's Text("literal") looks up by the literal.

    python3 Localization/gen_xcstrings.py            # write catalogs
    python3 Localization/gen_xcstrings.py --check    # verify code strings are covered, write nothing
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC_DIR = ROOT / "Localization"

# ONE catalog, in DesignShared/. That folder is a synchronized group belonging to all four targets,
# so its Localizable.xcstrings is copied into every bundle — the build actually REJECTS a second
# catalog per target ("Cannot have multiple Localizable.xcstrings files in same target"). One file
# therefore serves app, widget, watch and complication, and nothing can drift between them.
CATALOG = ROOT / "DesignShared" / "Localizable.xcstrings"

# Folders scanned for source strings when checking coverage.
TARGETS = {
    "app": ROOT / "eartharound.swift",
    "widget": ROOT / "SpaceWeatherWidget",
    "watch": ROOT / "SpaceWeatherWatch",
    "shared": ROOT / "DesignShared",
}

# Strings that must never be translated even though they appear in a Text(...).
DO_NOT_TRANSLATE = {
    "//", "EARTH AROUND", "Earth Around", "KP", "VS", "SUN", "EARTH",
    "NOAA SWPC", "GFZ Potsdam", "G1", "C", "M", "X", "Time", "Kp", "Hp30", "Flux", "Class",
}



def warn_positional_keys(strings):
    """A key must be written the way SWIFT emits it, or it silently never matches.

    SwiftUI's `Text("Kp \\(a) — \\(b).")` extracts as `Kp %@ — %@.` — NON-positional. Authoring
    the key as `Kp %1$@ — %2$@.` produces an entry that looks perfectly translated in the catalog
    and is never once looked up at runtime, so the UI stays English in every language with no
    error anywhere. Values may still use %1$/%2$ — that is how a locale reorders arguments.
    """
    bad = [k for k in strings if re.search(r"%\d+\$", k)]
    for k in bad:
        print(f"WARNING positional specifier in KEY (Swift emits %@ / %lld): {k!r}")
    return bad


def load():
    """Merge every Localization/strings*.json fragment into one key space."""
    locales, strings = None, {}
    for path in sorted(SRC_DIR.glob("strings*.json")):
        data = json.loads(path.read_text())
        locales = locales or data.get("_locales")
        for key, row in data.get("strings", {}).items():
            if key in strings:
                raise SystemExit(f"duplicate key {key!r} in {path.name}")
            strings[key] = row
    return locales, strings


def build_catalog(locales, strings):
    """xcstrings v1.0: sourceLanguage + per-key localizations keyed by locale."""
    entries = {}
    for key, row in sorted(strings.items()):
        loc = {}
        for lang in locales:
            value = row.get(lang)
            if not value:
                continue
            loc[lang] = {"stringUnit": {"state": "translated", "value": value}}
        entry = {"extractionState": "manual", "localizations": loc}
        if row.get("comment"):
            entry["comment"] = row["comment"]
        entries[key] = entry
    return {"sourceLanguage": "en", "strings": entries, "version": "1.0"}


def code_strings():
    """Every literal the code passes to Text/Label/accessibilityLabel, for coverage checking."""
    # SWText.str / .key / .loc MUST be in here. They are how every string reaches the catalog
    # since the localization refactor, and while they were missing this check reported
    # "0 still English-only" while a key like "Latest flare" was absent and rendering English.
    pattern = re.compile(
        r'(?:Text|Label|accessibilityLabel|configurationDisplayName|description'
        r'|SWText\.str|SWText\.key|SWText\.loc)\(\s*"([^"\\]{2,})"')
    found = set()
    for folder in TARGETS.values():
        for path in folder.rglob("*.swift"):
            for match in pattern.finditer(path.read_text()):
                found.add(match.group(1))
    return found


def main():
    locales, strings = load()
    warn_positional_keys(strings)
    catalog = build_catalog(locales, strings)

    if "--check" in sys.argv:
        missing = sorted(s for s in code_strings() - set(strings) if s not in DO_NOT_TRANSLATE)
        for s in missing:
            print(f"UNTRANSLATED  {s!r}")
        print(f"\n{len(strings)} translated · {len(missing)} still English-only")
        return 1 if missing else 0

    CATALOG.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n")
    print(f"wrote {CATALOG.relative_to(ROOT)}  ({len(strings)} keys x {len(locales)} locales)")
    return 0


if __name__ == "__main__":
    sys.exit(main())

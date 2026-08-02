#!/usr/bin/env python3
"""Generate the app's Localizable.xcstrings from Localization/strings.json.

Keys are the English source string, because SwiftUI's Text("literal") looks up by the literal —
and because EphemerisKit deliberately keeps returning English (its strings double as dictionary
keys, Identifiable ids, the AspectColor switch key and the CSV export contract, so translating
them in place would break colours, event codes and saved places). `L.loc()` turns that English
into a catalog lookup at the view boundary.

One catalog, one target: Xcode rejects more than one Localizable.xcstrings per target.

    python3 Localization/gen_xcstrings.py            # write the catalog
    python3 Localization/gen_xcstrings.py --check    # report untranslated literals, write nothing
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC_DIR = ROOT / "Localization"
CATALOG = ROOT / "ephemeris" / "Localizable.xcstrings"

# Scanned for coverage: the app's own literals, plus the Kit's display strings, which reach the
# UI through L.loc() and therefore need catalog entries under their English wording.
SCAN = [ROOT / "ephemeris", ROOT / "EphemerisKit" / "Sources" / "EphemerisKit"]

# Never translated, even inside a Text(...).
DO_NOT_TRANSLATE = {
    # brand / symbols / units that are the same everywhere
    "Ephemeris Sky", "Ephemeris", "AC", "MC", "℞", "d° mm′", "UTC",
    # astrologer surnames — house systems named after people
    "Placidus", "Koch", "Campanus", "Regiomontanus",
    # identifiers that happen to look like prose
    "CelestialBody", "Unsupported platform",
}


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
            if value:
                loc[lang] = {"stringUnit": {"state": "translated", "value": value}}
        entry = {"extractionState": "manual", "localizations": loc}
        if row.get("comment"):
            entry["comment"] = row["comment"]
        entries[key] = entry
    return {"sourceLanguage": "en", "strings": entries, "version": "1.0"}


def code_strings():
    """Literals the code shows to a user, for coverage checking."""
    pattern = re.compile(
        r'(?:Text|Label|navigationTitle|CardHeader\(title:|NebulaCardHeader\(title:|'
        r'Button|Picker|Section|tab|accessibilityLabel|prompt:|help)\(\s*"([^"\\]{2,})"'
    )
    found = set()
    for folder in SCAN:
        for path in folder.rglob("*.swift"):
            for match in pattern.finditer(path.read_text()):
                found.add(match.group(1))
    return found


def missing_translations(locales, strings):
    """Keys that exist but aren't translated everywhere — a half-filled catalog ships English."""
    gaps = []
    for key, row in sorted(strings.items()):
        absent = [l for l in locales if not row.get(l)]
        if absent:
            gaps.append((key, absent))
    return gaps


def main():
    locales, strings = load()

    if "--check" in sys.argv:
        untranslated = sorted(s for s in code_strings() - set(strings) if s not in DO_NOT_TRANSLATE)
        for s in untranslated:
            print(f"NO KEY        {s!r}")
        gaps = missing_translations(locales, strings)
        for key, absent in gaps:
            print(f"INCOMPLETE    {key!r} missing {','.join(absent)}")
        print(f"\n{len(strings)} keys x {len(locales)} locales · "
              f"{len(untranslated)} without a key · {len(gaps)} incomplete")
        return 1 if untranslated or gaps else 0

    CATALOG.parent.mkdir(parents=True, exist_ok=True)
    CATALOG.write_text(json.dumps(build_catalog(locales, strings), ensure_ascii=False, indent=2) + "\n")
    print(f"wrote {CATALOG.relative_to(ROOT)}  ({len(strings)} keys x {len(locales)} locales)")
    return 0


if __name__ == "__main__":
    sys.exit(main())

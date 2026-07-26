#!/usr/bin/env python3
"""Generate OverToneLab/Localizable.xcstrings from Localization/strings.json.

Ported from ephemeris.swift/Localization/gen_xcstrings.py — same contract:
keys ARE the English source string, because SwiftUI's Text("literal") looks up by the literal.

    python3 Localization/gen_xcstrings.py             # write the catalog
    python3 Localization/gen_xcstrings.py --check     # report gaps, write nothing
    python3 Localization/gen_xcstrings.py --extract   # dump every UI literal as a skeleton

Reference-screen prose is deliberately OUT OF SCOPE this pass (see DESIGN.md): those 18 screens
carry the ISO 9613 / BS.1770 / Bonello citations the app's credibility rests on, and a machine
translation there costs more than English does. `--check` therefore ignores *ReferenceView.swift.
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC_DIR = ROOT / "Localization"
CATALOG = ROOT / "OverToneLab" / "Localizable.xcstrings"
SCAN = [ROOT / "OverToneLab"]
SKIP_FILES = re.compile(r"ReferenceView\.swift$")

# Never translated, even inside a Text(...).
DO_NOT_TRANSLATE = {
    # brand
    "Overtone Lab",
    # tool names — surnames (Sabine, Webster, Bernoulli, Fletcher, Thiele, Partch, Mersenne,
    # Butterworth) and standard abbreviations. Translating them destroys recognition, and the
    # OVERTONELAB_TOOL deep links key off the enum raw values anyway.
    "Tempo", "Delay", "Timecode", "Pitch", "Partch", "Comma", "Mersenne", "Sabine", "Webster",
    "Bernoulli", "Formant", "SPL", "Room Modes", "Air", "SBIR", "Butterworth", "Fletcher",
    "Benchmark", "Passive", "Biquad", "Compressor", "SRA", "Levels", "File", "Pan", "Thiele",
    # units and symbols — identical in every language the app ships
    "Hz", "kHz", "dB", "dBu", "dBV", "dBFS", "dBA", "LUFS", "LU", "BPM", "ms", "s", "m", "cm",
    "mm", "m²", "m³", "L", "V", "W", "Ω", "µF", "mH", "N", "kg", "%", ":1", "fr", "B", "MB",
    "in", "ft", "sabins", "cents", "¢", "°", "×", "—", "·",
    # sub-screen names that are formulas or proper nouns
    "RC / RL", "LC", "EDO", "RT60", "Note↔Freq", "Frames → TC", "TC → Frames", "Eyring",
    "Helmholtz", "Doppler", "Varispeed", "ORTF", "NOS", "DIN", "Blumlein",
    # tuning/temperament and filter terms that are the same term of art everywhere
    "12-EDO", "12-TET", "Just", "Pythagorean", "Meantone", "Werckmeister", "Kirnberger",
    "Linkwitz-Riley", "Bessel", "Chebyshev", "Sallen-Key", "Nyquist", "K-weighting",
    # biquad coefficient and formant labels — math symbols, not words
    "a0", "a1", "a2", "b0", "b1", "b2", "F1", "F2", "F3", "LR2", "LR4", "LR8", "fps",
    # fragment of the interpolated label "\(platform) target" — the real catalog key is
    # "%@ target" (SwiftUI keys interpolated LocalizedStringKeys that way), which IS translated
    "target",
}

# Note values (1/4), sample rates (44.1k), varispeed ratios (/2), pure numbers and bare symbols:
# language-independent, and translating them would corrupt the value the user is reading.
NUMERIC_ATOM = re.compile(r'^[\s\d/.,:×x+\-–—−°%¢]*(?:k|Hz|kHz|dB|st|¢)?[\s\d/.,:×x+\-–—−°%¢]*$')

# How Overtone Lab actually presents text: its own components take the label as the first
# argument, so scanning only Text(...) would miss almost everything.
LITERAL = re.compile(
    r'(?:Text|Label|navigationTitle|Button|Toggle|Picker|Section|accessibilityLabel|'
    r'CardHeader\(title:|NumberField\(title:|ResultRow\(label:|footnote|caption)'
    r'\(?\s*"([^"\\]{2,})"'
)
# SubScreenPicker(titles: ["Note", "Tempo", ...]) — pull each element.
PICKER = re.compile(r'SubScreenPicker\(titles:\s*\[([^\]]+)\]')
# ToolCatalog.swift: `case .tempo: return "Tempo"` for title/subtitle.
CATALOG_RETURN = re.compile(r'return\s+"([^"\\]{2,})"')


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
    return locales or [], strings


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
    """Literals the code shows a user, for coverage checking."""
    found = set()
    for folder in SCAN:
        for path in folder.rglob("*.swift"):
            if SKIP_FILES.search(path.name):
                continue
            text = path.read_text()
            for m in LITERAL.finditer(text):
                found.add(m.group(1))
            for m in PICKER.finditer(text):
                found.update(re.findall(r'"([^"\\]+)"', m.group(1)))
            if path.name == "ToolCatalog.swift":
                # Only `title` and `subtitle`. `symbol` returns SF Symbol names ("waveform.path",
                # "metronome") — asset identifiers that must never be translated, and they sit
                # after the two we want, so cut the file there.
                head = text.split("var symbol", 1)[0]
                found.update(m.group(1) for m in CATALOG_RETURN.finditer(head))
    return {s.strip() for s in found
            if s.strip() not in DO_NOT_TRANSLATE and not NUMERIC_ATOM.match(s.strip())}


def missing_translations(locales, strings):
    """Keys that exist but aren't translated everywhere — a half-filled catalog ships English."""
    return [(k, [l for l in locales if not row.get(l)])
            for k, row in sorted(strings.items())
            if any(not row.get(l) for l in locales)]


def main():
    locales, strings = load()

    if "--extract" in sys.argv:
        skeleton = {"_locales": locales,
                    "strings": {s: strings.get(s, {"comment": ""}) for s in sorted(code_strings())}}
        print(json.dumps(skeleton, ensure_ascii=False, indent=2))
        return 0

    if "--check" in sys.argv:
        untranslated = sorted(code_strings() - set(strings))
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

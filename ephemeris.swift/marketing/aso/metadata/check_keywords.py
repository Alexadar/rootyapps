#!/usr/bin/env python3
"""Validate the per-locale subtitle/keyword sets against the mechanical App Store rules.

Ported from eartharound.swift/marketing/aso/check_keywords.py. Reads the same meta_*.json files
push_metadata.py uploads, so it checks what actually ships rather than a parallel copy.

The rules are cheap to get wrong and expensive to notice later:
  - 30/100 character budgets, counted on the NFC-normalised string (Apple counts characters, and
    a decomposed 'é' counts as two)
  - no space after a comma — each one burns a character of the 100
  - no duplicate keyword, and no plural of a term already present as a singular
  - no word repeated between subtitle and keywords: Apple indexes the union, so a repeat is paid
    for twice and indexed once
"""
import json
import re
import sys
import unicodedata
from pathlib import Path

SUBTITLE_MAX = 30
KEYWORDS_MAX = 100
HERE = Path(__file__).resolve().parent

# CJK has no spaces, so "word" boundaries there are the comma-separated atoms themselves.
CJK = ("ja", "ko", "zh-Hans", "zh-Hant")


def load():
    meta = {}
    for path in sorted(HERE.glob("meta_*.json")):
        if path.name == "meta_whatsnew.json":
            continue
        for locale, value in json.loads(path.read_text()).items():
            if not locale.startswith("_"):
                meta[locale] = value
    return meta


def words(text: str, locale: str) -> set:
    if locale in CJK:
        return {t.strip() for t in re.split(r"[,\s]+", text) if t.strip()}
    return {w for w in re.split(r"[,\s]+", text.lower()) if w}


def main() -> int:
    data = load()
    problems = 0
    print(f"{'loc':<8} {'subtitle':>9} {'keywords':>9}  status")
    print("-" * 78)
    for locale, row in sorted(data.items()):
        sub, kw = row["subtitle"], row["keywords"]
        s_len = len(unicodedata.normalize("NFC", sub))
        k_len = len(unicodedata.normalize("NFC", kw))
        flags = []

        if s_len > SUBTITLE_MAX:
            flags.append(f"SUBTITLE OVER by {s_len - SUBTITLE_MAX}")
        if k_len > KEYWORDS_MAX:
            flags.append(f"KEYWORDS OVER by {k_len - KEYWORDS_MAX}")
        if ", " in kw:
            flags.append("space after comma")

        atoms = kw.split(",")
        if any(a != a.strip() for a in atoms):
            flags.append("untrimmed atom")
        if len(atoms) != len(set(a.lower() for a in atoms)):
            flags.append("duplicate keyword")

        overlap = words(sub, locale) & words(kw, locale)
        if overlap:
            flags.append(f"repeated in both fields: {sorted(overlap)}")

        # The app name is indexed too — a word already in it is wasted in the keyword field.
        name_overlap = words(row.get("name", ""), locale) & words(kw, locale)
        if name_overlap:
            flags.append(f"repeated from name: {sorted(name_overlap)}")

        if locale not in CJK:
            lower = [a.lower() for a in atoms]
            for a in lower:
                if a.endswith("s") and a[:-1] in lower:
                    flags.append(f"plural of included singular: {a}")

        if flags:
            problems += 1
        print(f"{locale:<8} {s_len:>6}/{SUBTITLE_MAX} {k_len:>6}/{KEYWORDS_MAX}  "
              f"{'  '.join(flags) if flags else 'ok'}")

    print("-" * 78)
    print(f"{len(data)} locales, {problems} with problems")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
